// The package's real ACP host on localhost, for the demo, AgentChatLive's tests and the end-to-end walkthrough: its
// handler and rooms over its in-memory sessions, with test knobs. Swift talks to it through LiveDevHost
// (AgentChatLiveTesting); nothing re-implements the host in Swift.
//
//   node server/dev/host.ts [--port 8788] [--exit-with-stdin]   # prints "ready <port>"; --port 0 picks a free one
//
// /acp is the profile. Any bearer is let in unless a session asks for one (/accept). Sessions are made on first use.
// Sessions named "live…" have a scripted agent (the demo's chat): it greets, answers prompts, asks before it merges.
//
// Knobs, POST /control/<session>/<knob> with a JSON body:
//   publish {update}                 a session/update of the agent's or the host's, as the host would write it
//   status {messageId, status}       one of the person's messages moves on (delivering, delivered, failed)
//   state {state, activity?, problem?}
//   ask {message, options[{id,label}], multiple?, freeText?}   the agent asks (elicitation/create)
//   expire                           every cursor handed out so far can't be resumed (-32602)
//   refuse {status}                  the session's next request after initialize answers this HTTP status
//   accept {bearer|null}             only this bearer from now on
//   forget                           the session's connections are forgotten: their next request gets 404
//   drop                             the session's open streams end
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import type { LiveAdapter } from "../src/adapter.ts";
import type { SessionUpdate } from "../src/acp.ts";
import { localRooms } from "../src/conformance.ts";
import { CONNECTION_HEADER, handleAcp, SESSION_HEADER } from "../src/handler.ts";
import { MemorySessions, type MemoryWho } from "../src/memory.ts";
import { notifyChat, platformTimers } from "../src/room.ts";

const portArg = process.argv.indexOf("--port");
const port = portArg > 0 ? Number(process.argv[portArg + 1]) : Number(process.env.PORT ?? 8788);
const secret = "dev-host-secret";
const sessions = new MemorySessions({ names: { jai: "Jai" } });

interface Knobs {
  bearer: string | null;
  refuse: number | null;
  forgottenAt: number;
}
const knobs = new Map<string, Knobs>();
const scripted = (id: string) => id.startsWith("live");
const greeting = {
  sessionUpdate: "agent_message",
  messageId: "greeting",
  _meta: { agentchatkit: { at: new Date().toISOString() } },
  content: [
    {
      type: "text",
      text: "Hi! I'm the scripted agent behind a **real ACP host** on this Mac. Ask me anything, or ask me to *merge*.",
    },
  ],
} as SessionUpdate;
/** When each connection id was first seen, by session: `forget` refuses those first seen before it. */
const seen = new Map<string, number>();

function session(id: string): Knobs {
  if (!sessions.has(id)) {
    sessions.create(id, "jai");
    if (scripted(id)) {
      sessions.apply(id, greeting);
    }
  }
  let found = knobs.get(id);
  if (!found) {
    found = { bearer: null, refuse: null, forgottenAt: 0 };
    knobs.set(id, found);
  }
  return found;
}

const base = sessions.adapter();
const adapter: LiveAdapter<MemoryWho> = {
  ...base,
  authorize: async (request, id) => {
    const wanted = session(id).bearer;
    if (wanted !== null && request.headers.get("Authorization") !== `Bearer ${wanted}`) {
      return { refusal: { status: 401, message: "not the bearer this session takes" } };
    }
    return { login: "jai", name: "Jai" };
  },
  prompt: async (who, id, body) => {
    const taken = await base.prompt(who, id, body);
    if (!("refusal" in taken) && !taken.repeat && scripted(id)) {
      agent.answer(
        id,
        taken.messageId,
        body.prompt.map((block) => (block.type === "text" ? block.text : "")).join(" "),
      );
    }
    return taken;
  },
  answer: async (who, id, question, answer) => {
    const done = await base.answer(who, id, question, answer);
    if (scripted(id)) {
      agent.afterAnswer(id);
    }
    return done;
  },
};
let rooms = localRooms(adapter, platformTimers);

async function change(id: string, update: SessionUpdate) {
  session(id);
  sessions.apply(id, update);
  await notifyChat(rooms, id);
}

// The demo's agent, in every session named "live…".
const pause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const at = () => ({ agentchatkit: { at: new Date().toISOString() } });
const working = (activity: string): SessionUpdate => ({
  sessionUpdate: "state_update",
  state: "running",
  _meta: { agentchatkit: { activity } },
});
const idle: SessionUpdate = {
  sessionUpdate: "state_update",
  state: "idle",
  stopReason: "end_turn",
  _meta: { agentchatkit: {} },
};
const agent = {
  queue: Promise.resolve() as Promise<void>,
  counter: 0,
  answer(id: string, messageId: string, words: string) {
    this.queue = this.queue.then(() => this.run(id, messageId, words));
  },
  afterAnswer(id: string) {
    this.queue = this.queue.then(async () => {
      await change(id, working("Merging"));
      await pause(800);
      await this.write(id, "Merged, and tagged. CI is running on main.");
      await change(id, idle);
    });
  },
  async status(id: string, messageId: string, status: string) {
    await change(id, {
      sessionUpdate: "user_message",
      messageId,
      _meta: { agentchatkit: { status } },
    } as SessionUpdate);
  },
  async run(id: string, messageId: string, words: string) {
    await this.status(id, messageId, "delivering");
    await pause(300);
    await this.status(id, messageId, "delivered");
    if (/merge/i.test(words)) {
      await change(id, working("Checking CI"));
      await pause(800);
      sessions.ask(id, {
        mode: "form",
        message: "CI is green. Merge now, or wait for review?",
        requestedSchema: {
          type: "object",
          properties: {
            choice: { type: "string", enum: ["merge", "wait"], enumNames: ["Merge now", "Wait for review"] },
            text: { type: "string" },
          },
        },
      });
      await notifyChat(rooms, id);
      return;
    }
    await change(id, working("Reading the code"));
    await pause(600);
    this.counter += 1;
    await change(id, {
      sessionUpdate: "tool_call_update",
      toolCallId: `tool-${this.counter}`,
      title: 'rg "ChatView(" Sources/',
      name: "Grep",
      kind: "search",
      status: "completed",
      _meta: at(),
    } as SessionUpdate);
    await pause(600);
    await this.write(
      id,
      "`ChatView` draws the whole chat screen: the messages, the reply box, and whatever the host hangs under them. " +
        "This answer came over **ACP**, from the server package running on this Mac.",
    );
    await change(id, idle);
  },
  async write(id: string, text: string) {
    this.counter += 1;
    const messageId = `them-${this.counter}`;
    const meta = at();
    const words = text.split(" ");
    for (let end = 6; end < words.length; end += 6) {
      await change(id, {
        sessionUpdate: "agent_message",
        messageId,
        content: [{ type: "text", text: words.slice(0, end).join(" ") }],
        _meta: meta,
      });
      await pause(250);
    }
    await change(id, { sessionUpdate: "agent_message", messageId, content: [{ type: "text", text }], _meta: meta });
  },
};
session("live");

async function knob(id: string, name: string, body: Record<string, unknown>): Promise<unknown> {
  const own = session(id);
  switch (name) {
    case "publish":
      await change(id, body.update as SessionUpdate);
      return {};
    case "status":
      await change(id, {
        sessionUpdate: "user_message",
        messageId: body.messageId,
        _meta: { agentchatkit: { status: body.status } },
      } as SessionUpdate);
      return {};
    case "state":
      await change(id, {
        sessionUpdate: "state_update",
        state: body.state,
        ...(body.state === "idle" ? { stopReason: "end_turn" } : {}),
        _meta: { agentchatkit: { activity: body.activity ?? null, problem: body.problem ?? null } },
      } as SessionUpdate);
      return {};
    case "ask": {
      const options = (body.options as { id: string; label: string }[]) ?? [];
      const choice = { type: "string", enum: options.map((o) => o.id), enumNames: options.map((o) => o.label) };
      const properties: Record<string, unknown> = {};
      if (body.multiple) {
        properties.choices = { type: "array", items: choice };
      } else if (options.length > 0) {
        properties.choice = choice;
      }
      if (body.freeText !== false) {
        properties.text = { type: "string" };
      }
      const question = sessions.ask(id, {
        mode: "form",
        message: String(body.message),
        requestedSchema: { type: "object", properties },
      });
      await notifyChat(rooms, id);
      return { id: question };
    }
    case "expire":
      sessions.expire(id);
      return {};
    case "refuse":
      own.refuse = Number(body.status);
      return {};
    case "accept":
      own.bearer = (body.bearer as string | null) ?? null;
      return {};
    case "forget":
      own.forgottenAt = Date.now() + 1;
      rooms.room(id).closeAll();
      return {};
    case "drop":
      rooms.room(id).closeAll();
      return {};
    default:
      throw new Error(`no knob ${name}`);
  }
}

async function toRequest(req: IncomingMessage): Promise<Request> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(chunk as Buffer);
  }
  const headers = new Headers();
  for (const [key, value] of Object.entries(req.headers)) {
    if (typeof value === "string") {
      headers.set(key, value);
    }
  }
  const body = chunks.length > 0 && req.method !== "GET" ? Buffer.concat(chunks) : undefined;
  return new Request(`http://127.0.0.1${req.url}`, { method: req.method, headers, body });
}

async function send(response: Response, res: ServerResponse) {
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.flushHeaders(); // Node holds headers until the first write; a stream's first may be a while away.
  if (!response.body) {
    return void res.end();
  }
  const reader = response.body.getReader();
  res.on("close", () => void reader.cancel());
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    res.write(value);
  }
  res.end();
}

/** The session knobs that act before the package: a refused or forgotten request. */
function interfere(request: Request): Response | null {
  const id = request.headers.get(SESSION_HEADER);
  const connection = request.headers.get(CONNECTION_HEADER);
  if (!id || !connection) {
    return null;
  }
  const own = session(id);
  const first = seen.get(`${id} ${connection}`) ?? Date.now();
  seen.set(`${id} ${connection}`, first);
  if (first < own.forgottenAt) {
    return Response.json({ error: "connection forgotten" }, { status: 404 });
  }
  if (own.refuse !== null && request.method === "POST") {
    const status = own.refuse;
    own.refuse = null;
    return Response.json({ error: `refused (${status})` }, { status });
  }
  return null;
}

const server = createServer(async (req, res) => {
  try {
    const path = (req.url ?? "/").split("?")[0] ?? "/";
    const control = /^\/control\/([^/]+)\/([a-z]+)$/.exec(path);
    if (control?.[1] && control[2]) {
      const request = await toRequest(req);
      const body = request.headers.get("content-type")?.includes("json")
        ? ((await request.json()) as Record<string, unknown>)
        : {};
      return void send(Response.json(await knob(decodeURIComponent(control[1]), control[2], body)), res);
    }
    if (path !== "/acp") {
      res.statusCode = 404;
      return void res.end();
    }
    const request = await toRequest(req);
    await send(interfere(request) ?? (await handleAcp(request, { adapter, rooms, secret })), res);
  } catch (error) {
    console.error(error);
    res.statusCode = 500;
    res.end();
  }
});
server.listen(port, "127.0.0.1", () => console.log(`ready ${(server.address() as AddressInfo).port}`));
// A parent that started us (AgentChatLive's tests) ends us by closing our stdin.
if (process.argv.includes("--exit-with-stdin")) {
  process.stdin.on("end", () => process.exit(0));
  process.stdin.resume();
}
