// A real ACP host on this Mac, for the demo and the end-to-end walkthrough (docs/end-to-end-walkthrough.md): the
// server package's handler and room (server/src), over its in-memory sessions, with a scripted agent behind them.
// The demo app follows it over real HTTP with `-DemoServer http://127.0.0.1:8788/acp`.
//
//   node Demo/server/dev-host.ts            # http://127.0.0.1:8788/acp, bearer "token-jai", session "live"
//
// Control routes, for the walkthrough and the UI test: POST /control/drop ends every open stream (the app resumes
// from its cursor); POST /control/restart forgets every connection (the app initializes again); POST
// /control/expire makes every cursor stale (the app resumes from start); GET /control/log is what happened.
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { handleAcp } from "../../server/src/handler.ts";
import { localRooms } from "../../server/src/conformance.ts";
import { MemorySessions, type MemoryWho } from "../../server/src/memory.ts";
import { notifyChat, platformTimers } from "../../server/src/room.ts";
import type { LiveAdapter } from "../../server/src/adapter.ts";

const port = Number(process.env.PORT ?? 8788);
const SESSION = "live";
const sessions = new MemorySessions({ names: { jai: "Jai" } });
sessions.create(SESSION, "jai");
let secret = "dev-host-secret";
const log: string[] = [];
const say = (line: string) => {
  const stamped = `${new Date().toISOString().slice(11, 23)} ${line}`;
  log.push(stamped);
  console.log(stamped);
};

const base = sessions.adapter();
const adapter: LiveAdapter<MemoryWho> = {
  ...base,
  prompt: async (who, id, body) => {
    const taken = await base.prompt(who, id, body);
    if (!("refusal" in taken) && !taken.repeat) {
      const words = body.prompt.map((block) => (block.type === "text" ? block.text : "")).join(" ");
      say(`prompt ${taken.messageId}: ${words}`);
      agent.answer(taken.messageId, words);
    }
    return taken;
  },
  answer: async (who, id, question, answer) => {
    const done = await base.answer(who, id, question, answer);
    say(`answer ${question}: ${JSON.stringify(answer.content ?? answer.action)}`);
    agent.afterAnswer();
    return done;
  },
};
let rooms = localRooms(adapter, platformTimers);

const pause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const meta = (extra: Record<string, unknown> = {}) => ({ agentchatkit: { at: new Date().toISOString(), ...extra } });

/** What the host does when the agent changes the chat: put it in the session, then tell the room. */
async function change(update: Parameters<MemorySessions["apply"]>[1]) {
  sessions.apply(SESSION, update);
  await notifyChat(rooms, SESSION);
}

const agent = {
  queue: Promise.resolve() as Promise<void>,
  counter: 0,
  answer(messageId: string, words: string) {
    this.queue = this.queue.then(() => this.run(messageId, words));
  },
  afterAnswer() {
    this.queue = this.queue.then(async () => {
      await change({ sessionUpdate: "state_update", state: "running", _meta: { agentchatkit: { activity: "Merging" } } });
      await pause(800);
      await this.write("Merged, and tagged. CI is running on main.");
      await change({ sessionUpdate: "state_update", state: "idle", stopReason: "end_turn", _meta: { agentchatkit: {} } });
    });
  },
  async status(messageId: string, status: "delivering" | "delivered") {
    const held = sessions.message(SESSION, messageId);
    if (held?.sessionUpdate === "user_message") {
      await change({ ...held, _meta: { ...held._meta, agentchatkit: { ...held._meta?.agentchatkit, status } } });
    }
  },
  async run(messageId: string, words: string) {
    await this.status(messageId, "delivering");
    await pause(300);
    await this.status(messageId, "delivered");
    if (/merge/i.test(words)) {
      await change({ sessionUpdate: "state_update", state: "running", _meta: { agentchatkit: { activity: "Checking CI" } } });
      await pause(800);
      sessions.ask(SESSION, {
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
      await notifyChat(rooms, SESSION);
      say("asked q");
      return;
    }
    await change({ sessionUpdate: "state_update", state: "running", _meta: { agentchatkit: { activity: "Reading the code" } } });
    await pause(600);
    this.counter += 1;
    await change({
      sessionUpdate: "tool_call_update", toolCallId: `tool-${this.counter}`, title: "rg \"ChatView(\" Sources/",
      name: "Grep", kind: "search", status: "completed", _meta: meta(),
    });
    await pause(600);
    await this.write(
      "`ChatView` draws the whole chat screen: the messages, the reply box, and whatever the host hangs under them. " +
        "This answer came over **ACP**, from the server package running on this Mac.",
    );
    await change({ sessionUpdate: "state_update", state: "idle", stopReason: "end_turn", _meta: { agentchatkit: {} } });
  },
  async write(text: string) {
    this.counter += 1;
    const id = `them-${this.counter}`;
    const at = new Date().toISOString();
    const words = text.split(" ");
    for (let end = 6; end < words.length; end += 6) {
      await change({ sessionUpdate: "agent_message", messageId: id, content: [{ type: "text", text: words.slice(0, end).join(" ") }], _meta: { agentchatkit: { at } } });
      await pause(250);
    }
    await change({ sessionUpdate: "agent_message", messageId: id, content: [{ type: "text", text }], _meta: { agentchatkit: { at } } });
  },
};

await change({
  sessionUpdate: "agent_message", messageId: "greeting",
  content: [{ type: "text", text: "Hi! I'm the scripted agent behind a **real ACP host** on this Mac. Ask me anything, or ask me to *merge*." }],
  _meta: meta(),
});

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
  return new Request(`http://127.0.0.1:${port}${req.url}`, { method: req.method, headers, body });
}

async function send(response: Response, res: ServerResponse) {
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.flushHeaders(); // Node holds headers until the first write; a stream's first may be 15 s away.
  if (!response.body) {
    res.end();
    return;
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

createServer(async (req, res) => {
  const path = (req.url ?? "/").split("?")[0];
  if (path === "/control/drop") {
    rooms.closeAll();
    say("control: dropped every stream");
    return void res.end("dropped\n");
  }
  if (path === "/control/restart") {
    rooms.closeAll();
    rooms = localRooms(adapter, platformTimers);
    secret = `dev-host-secret-${Date.now()}`;
    say("control: restarted (connections forgotten)");
    return void res.end("restarted\n");
  }
  if (path === "/control/expire") {
    sessions.expire(SESSION);
    say("control: every cursor expired");
    return void res.end("expired\n");
  }
  if (path === "/control/log") {
    return void res.end(log.join("\n") + "\n");
  }
  if (path !== "/acp") {
    res.statusCode = 404;
    return void res.end();
  }
  const request = await toRequest(req);
  const kind = req.method === "GET" ? "stream" : (req.headers["acp-connection-id"] ? "post" : "initialize");
  say(`${req.method} /acp ${kind}`);
  await send(await handleAcp(request, { adapter, rooms, secret }), res);
}).listen(port, "127.0.0.1", () => say(`dev host on http://127.0.0.1:${port}/acp, session ${SESSION}, bearer token-jai`));
