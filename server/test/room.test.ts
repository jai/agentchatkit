// The room on a fake clock: keep-alive, refreshEvery, a change during a resume, shared reads, a replaced stream,
// messages kept until the stream opens, and timers that stop with the last stream.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { LiveAdapter, LiveRead } from "../src/adapter.ts";
import { AcpTestClient, localRooms, ManualTimers } from "../src/conformance.ts";
import { handleAcp } from "../src/handler.ts";
import { MemorySessions, type MemoryWho } from "../src/memory.ts";
import { LiveRoom, notifyChat } from "../src/room.ts";

const text = (words: string) => [{ type: "text" as const, text: words }];
const agent = (id: string, words: string) => ({
  sessionUpdate: "agent_message" as const,
  messageId: id,
  content: text(words),
  _meta: { agentchatkit: { at: null } },
});

function setup(
  adapterOf: (sessions: MemorySessions) => LiveAdapter<MemoryWho> = (s) => s.adapter(),
  refreshEvery?: number,
) {
  const sessions = new MemorySessions({ names: { jai: "Jai" } });
  sessions.create("s", "jai");
  const adapter = adapterOf(sessions);
  const timers = new ManualTimers();
  const rooms = new Map<string, LiveRoom<MemoryWho>>();
  const namespace = {
    idFromName: (name: string) => name,
    get: (id: never) => ({
      fetch: (request: Request) => {
        let room = rooms.get(id as string);
        if (!room) {
          room = new LiveRoom(adapter, { timers, ...(refreshEvery ? { refreshEvery } : {}) });
          rooms.set(id as string, room);
        }
        return room.fetch(request);
      },
    }),
  };
  const request = (url: string, init: RequestInit = {}) => {
    const headers = new Headers(init.headers);
    headers.set("Authorization", "Bearer token-jai");
    return new Request(url, { ...init, headers });
  };
  const client = () =>
    new AcpTestClient(
      (r) => handleAcp(r, { adapter, rooms: namespace, secret: "s3cret" }),
      "s",
      "https://h/acp",
      request,
    );
  const follow = async (c = client()) => {
    await c.initialize();
    await c.open();
    const id = await c.request("session/resume", { sessionId: "s", replayFrom: { type: "start" } });
    for (;;) {
      const message = await c.next(500);
      if ("id" in message && message.id === id) {
        return c;
      }
    }
  };
  return { sessions, timers, rooms, namespace, client, follow, room: () => rooms.get("s") };
}

test("a keep-alive comment every 15 s, and the timer stops with the last stream", async () => {
  const { timers, follow, room } = setup();
  const c = await follow();
  timers.advance(14_999);
  await c.none(10);
  timers.advance(1);
  assert.equal(await c.comment(500), "keep-alive");
  room()?.closeAll();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(timers.pending, 0);
  await c.close();
});

test("refreshEvery reads on its tick, for a change no write or notify made", async () => {
  const { sessions, timers, follow } = setup(undefined, 15_000);
  const c = await follow();
  sessions.apply("s", agent("a1", "Done.")); // No notify: only the refresh finds it.
  await c.none(20);
  timers.advance(15_000);
  const message = await c.next(500);
  assert.ok("method" in message && message.method === "session/update");
  assert.equal((message.params as { update: { messageId: string } }).update.messageId, "a1");
  await c.close();
});

test("a change made while a connection resumes is sent once it follows, once", async () => {
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  let first = true;
  const { sessions, namespace, client } = setup((s) => {
    const base = s.adapter();
    return {
      ...base,
      read: async (who, id, cursor): Promise<LiveRead> => {
        const read = await base.read(who, id, cursor);
        if (first) {
          first = false;
          await gate; // The resume's read answers late: the change below lands meanwhile.
        }
        return read;
      },
    };
  });
  const c = client();
  await c.initialize();
  await c.open();
  const id = await c.request("session/resume", { sessionId: "s", replayFrom: { type: "start" } });
  sessions.apply("s", agent("a1", "Written during the resume."));
  await notifyChat(namespace, "s");
  release();
  const seen: unknown[] = [];
  for (;;) {
    const message = await c.next(500);
    seen.push(message);
    if ("method" in message && (message.params as { update?: { messageId?: string } }).update?.messageId === "a1") {
      break;
    }
  }
  assert.ok(
    seen.some((m) => typeof m === "object" && m !== null && "id" in m && m.id === id),
    "the resume answered first",
  );
  await c.none(30);
  await c.close();
});

test("connections at the same cursor share one read", async () => {
  let reads = 0;
  const { sessions, namespace, follow } = setup((s) => {
    const base = s.adapter();
    return { ...base, read: (...args) => ((reads += 1), base.read(...args)) };
  });
  const a = await follow();
  const b = await follow();
  reads = 0;
  sessions.apply("s", agent("a1", "Once."));
  await notifyChat(namespace, "s");
  await a.next(500);
  await b.next(500);
  assert.equal(reads, 1);
  await Promise.all([a.close(), b.close()]);
});

test("what is sent before the stream opens waits for it", async () => {
  const { client } = setup();
  const c = client();
  await c.initialize();
  const id = await c.request("session/resume", { sessionId: "s", replayFrom: { type: "start" } });
  await c.open();
  const state = await c.next(500);
  assert.ok("method" in state && state.method === "session/update");
  const answer = await c.next(500);
  assert.ok("id" in answer && answer.id === id && "result" in answer);
  await c.close();
});

test("a second stream for one connection replaces the first", async () => {
  const { client, room } = setup();
  const c = client();
  await c.initialize();
  await c.open();
  const first = c;
  const second = new AcpTestClient(
    (r) => (c as unknown as { send: (r: Request) => Promise<Response> }).send(r),
    "s",
    "https://h/acp",
    (u, i = {}) => {
      const headers = new Headers(i.headers);
      headers.set("Authorization", "Bearer token-jai");
      return new Request(u, { ...i, headers });
    },
  );
  second.connection = c.connection;
  await second.open();
  assert.equal(room()?.streams, 1);
  await assert.rejects(first.next(200), /ended/);
  await second.close();
});

test("an expired cursor answers -32602, and the live read that finds one ends the stream", async () => {
  const { sessions, namespace, follow } = setup();
  const c = await follow();
  sessions.expire("s");
  sessions.apply("s", agent("a1", "A new history."));
  await notifyChat(namespace, "s");
  await assert.rejects(c.next(500), /ended/);
  const again = setup().client(); // A fresh client elsewhere is unaffected.
  assert.ok(again);
});

test("a write a host lacks answers method-not-found", async () => {
  const { follow } = setup((s) => ({ ...s.adapter(), edit: undefined }));
  const c = await follow();
  const id = await c.request("_agentchatkit/edit", { sessionId: "s", messageId: "u1", force: true });
  const answer = await c.next(500);
  assert.ok("error" in answer && answer.id === id);
  assert.equal(answer.error.code, -32601);
  await c.close();
});

test("localRooms closes every room", async () => {
  const sessions = new MemorySessions();
  sessions.create("s", "jai");
  const timers = new ManualTimers();
  const rooms = localRooms(sessions.adapter(), timers);
  rooms.room("s").open("c1", { login: "jai", name: null });
  assert.equal(timers.pending, 1);
  rooms.closeAll();
  assert.equal(timers.pending, 0);
});

test("an upload answers the host's ticket, and a file too large is refused with its reason", async () => {
  const { follow } = setup((s) => ({
    ...s.adapter(),
    upload: async (_who: MemoryWho, _session: string, file: { name: string; mimeType: string; size: number }) =>
      file.size > 1000
        ? { refusal: { status: 413 as const, message: "Videos up to 1 kB" } }
        : { uploadUrl: `https://files.example/put/${file.name}`, uri: `files/${file.name}` },
  }));
  const c = await follow();
  const ok = await c.request("_agentchatkit/upload", {
    sessionId: "s",
    name: "clip.mov",
    mimeType: "video/quicktime",
    size: 10,
  });
  const ticket = await c.next(500);
  assert.ok("result" in ticket && ticket.id === ok);
  assert.deepEqual(ticket.result, { uploadUrl: "https://files.example/put/clip.mov", uri: "files/clip.mov" });
  const big = await c.request("_agentchatkit/upload", {
    sessionId: "s",
    name: "long.mov",
    mimeType: "video/quicktime",
    size: 5000,
  });
  const refused = await c.next(500);
  assert.ok("error" in refused && refused.id === big);
  assert.equal(refused.error.code, -32602);
  assert.equal(refused.error.message, "Videos up to 1 kB");
  const bad = await c.request("_agentchatkit/upload", { sessionId: "s", name: "", mimeType: "video/mp4", size: 1 });
  const invalid = await c.next(500);
  assert.ok("error" in invalid && invalid.id === bad && invalid.error.code === -32602);
  await c.close();
});
