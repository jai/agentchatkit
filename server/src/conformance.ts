/**
 * The conformance suite: the profile's fixtures, run against a host's adapter through this package's own handler
 * and room. Each backend runs it in its own CI and writes tests only for its adapter.
 *
 * Runner-agnostic: `conformanceCases(harness)` answers cases whose `run` throws on a failure.
 *
 * ```ts
 * for (const c of conformanceCases(harness)) {
 *   test(c.name, { skip: c.skip }, c.run); // node:test; vitest: (c.skip ? it.skip : it)(c.name, c.run)
 * }
 * ```
 */
import {
  ERRORS,
  type ElicitationCreateParams,
  isObject,
  type JsonRpcMessage,
  readEditParams,
  readElicitationResult,
  readIncoming,
  readPromptParams,
  readRemoveParams,
  readResume,
  type SessionUpdate,
} from "./acp.ts";
import { isRefusal, type LiveAdapter } from "./adapter.ts";
import { fixtures } from "./fixtures.generated.ts";
import { CONNECTION_HEADER, handleAcp, SESSION_HEADER } from "./handler.ts";
import { LiveRoom, type LiveRooms, notifyChat, type RoomTimers } from "./room.ts";
import { SSEParser, type StreamItem } from "./sse.ts";

export type Auth = "owner" | "none" | "stranger";

/** What the host does. A step it can't do is skipped; a write it lacks must answer method-not-found. */
export interface HostCapabilities {
  /** Prompts sent while the agent runs wait as `queued` (FeedbackKit: false). */
  queues: boolean;
  /** `_agentchatkit/edit`. */
  edit: boolean;
  /** `_agentchatkit/remove`. */
  remove: boolean;
  /** Questions: `elicitation/create` and its answer (FeedbackKit: false). Needs `ask`. */
  answer: boolean;
  /**
   * The `sessionUpdate` kinds the host's sessions hold. Fixture updates of other kinds are left out of what the
   * suite applies and expects (FeedbackKit: `["user_message", "agent_message", "state_update"]`, no tool calls).
   * Every kind when left out.
   */
  updates?: string[];
}

export interface ConformanceHarness<Who> {
  adapter: LiveAdapter<Who>;
  capabilities: HostCapabilities;
  /** A new, empty session that `request`'s owner may follow. Each case starts with its own. Answers its id. */
  reset(): Promise<string>;
  /** Puts one update into the session as the host would, in its own storage. The host assigns the cursor. */
  apply(sessionId: string, update: SessionUpdate): Promise<void>;
  /** Opens a question, as the agent asking: `read` then answers it, and the state is `requires_action`. */
  ask?(sessionId: string, params: Omit<ElicitationCreateParams, "sessionId">): Promise<void>;
  /** Makes every cursor handed out for the session so far one the host can't resume. Without it, that case skips. */
  expire?(sessionId: string): Promise<void>;
  /**
   * Instead of `expire`, for a host whose cursors never go stale by themselves: a cursor of this session it can't
   * resume (another history's, or past its end). Without either, that case skips.
   */
  staleCursor?(sessionId: string, current: string): Promise<string>;
  /** A request to `url` with the session owner's bearer, no bearer, or someone else's. */
  request(url: string, init?: RequestInit, auth?: Auth): Request;
  /** What a stranger gets: 403 by default; some hosts answer 404 so as not to say the session exists. */
  strangerStatus?: 403 | 404;
  /** How long to wait for a message, in ms. 2000. */
  timeoutMs?: number;
}

export interface ConformanceCase {
  name: string;
  /** Why it does not apply to this host, when it does not. */
  skip?: string;
  run(): Promise<void>;
}

// --- A clock and rooms in this process

/** Timers that run only when told: `advance(ms)`. */
export class ManualTimers implements RoomTimers {
  private now = 0;
  private next = 1;
  private readonly intervals = new Map<number, { run: () => void; every: number; due: number }>();

  setInterval(run: () => void, ms: number): unknown {
    const id = this.next++;
    this.intervals.set(id, { run, every: ms, due: this.now + ms });
    return id;
  }

  clearInterval(handle: unknown): void {
    this.intervals.delete(handle as number);
  }

  /** Moves the clock on, running each interval as it falls due. */
  advance(ms: number): void {
    const end = this.now + ms;
    for (;;) {
      const due = [...this.intervals.entries()].sort((a, b) => a[1].due - b[1].due)[0];
      if (!due || due[1].due > end) {
        break;
      }
      this.now = due[1].due;
      due[1].due += due[1].every;
      due[1].run();
    }
    this.now = end;
  }

  /** Intervals still set: none once every stream has gone. */
  get pending(): number {
    return this.intervals.size;
  }
}

/** Rooms in this process, one per session: the Durable Object namespace, for tests. */
export function localRooms<Who>(adapter: LiveAdapter<Who>, timers: RoomTimers = new ManualTimers()) {
  const rooms = new Map<string, LiveRoom<Who>>();
  const room = (sessionId: string) => {
    let found = rooms.get(sessionId);
    if (!found) {
      found = new LiveRoom(adapter, { timers });
      rooms.set(sessionId, found);
    }
    return found;
  };
  const namespace: LiveRooms & { room(sessionId: string): LiveRoom<Who>; closeAll(): void } = {
    idFromName: (name: string) => name,
    get: (id: never) => ({ fetch: (request: Request) => room(id as string).fetch(request) }),
    room,
    closeAll: () => {
      for (const found of rooms.values()) {
        found.closeAll();
      }
    },
  };
  return namespace;
}

// --- A client, for tests

/** One ACP client on one session: initialize, open the stream, post, and take what comes. */
export class AcpTestClient {
  connection: string | null = null;
  private reader: ReadableStreamDefaultReader<Uint8Array> | null = null;
  private readonly parser = new SSEParser();
  private readonly decoder = new TextDecoder();
  private readonly items: StreamItem[] = [];
  private pending: Promise<ReadableStreamReadResult<Uint8Array>> | null = null;
  private ended = false;
  private ids = 100;

  private readonly send: (request: Request) => Promise<Response>;
  private readonly sessionId: string;
  private readonly url: string;
  private readonly makeRequest: (url: string, init?: RequestInit, auth?: Auth) => Request;

  constructor(
    send: (request: Request) => Promise<Response>,
    sessionId: string,
    url = "https://host.example/acp",
    makeRequest: (url: string, init?: RequestInit, auth?: Auth) => Request = (u, i) => new Request(u, i),
  ) {
    this.send = send;
    this.sessionId = sessionId;
    this.url = url;
    this.makeRequest = makeRequest;
  }

  nextId(): number {
    this.ids += 1;
    return this.ids;
  }

  async initialize(): Promise<Response> {
    const response = await this.send(
      this.makeRequest(this.url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: { protocolVersion: 2, clientCapabilities: { elicitation: { form: {} } } },
        }),
      }),
    );
    this.connection = response.headers.get(CONNECTION_HEADER);
    return response;
  }

  async open(): Promise<Response> {
    const response = await this.send(
      this.makeRequest(this.url, {
        headers: {
          Accept: "text/event-stream",
          [CONNECTION_HEADER]: this.connection ?? "",
          [SESSION_HEADER]: this.sessionId,
        },
      }),
    );
    if (response.status === 200 && response.body) {
      this.reader = response.body.getReader();
    }
    return response;
  }

  post(message: unknown): Promise<Response> {
    return this.send(
      this.makeRequest(this.url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          [CONNECTION_HEADER]: this.connection ?? "",
          [SESSION_HEADER]: this.sessionId,
        },
        body: JSON.stringify(message),
      }),
    );
  }

  /** Sends a request; answers its id. */
  async request(method: string, params: unknown): Promise<number> {
    const id = this.nextId();
    const response = await this.post({ jsonrpc: "2.0", id, method, params });
    check(response.status === 202, `${method}: expected 202, got ${response.status}`);
    return id;
  }

  /** The next message on the stream (comments skipped); fails after `ms`. */
  async next(ms: number): Promise<JsonRpcMessage> {
    for (;;) {
      const item = await this.take(ms);
      if (!item) {
        throw new Error(this.ended ? "the stream ended" : `no message within ${ms} ms`);
      }
      if ("message" in item) {
        return item.message;
      }
    }
  }

  /** The next comment on the stream; fails after `ms`. */
  async comment(ms: number): Promise<string> {
    for (;;) {
      const item = await this.take(ms);
      if (!item) {
        throw new Error(`no comment within ${ms} ms`);
      }
      if ("comment" in item) {
        return item.comment;
      }
    }
  }

  /** Fails if a message comes within `ms`. */
  async none(ms: number): Promise<void> {
    for (;;) {
      const item = await this.take(ms);
      if (!item) {
        return;
      }
      if ("message" in item) {
        throw new Error(`expected nothing, got ${JSON.stringify(item.message)}`);
      }
    }
  }

  async close(): Promise<void> {
    await this.reader?.cancel().catch(() => {});
    this.reader = null;
  }

  private async take(ms: number): Promise<StreamItem | null> {
    const deadline = Date.now() + ms;
    for (;;) {
      const item = this.items.shift();
      if (item) {
        return item;
      }
      if (this.ended || !this.reader) {
        return null;
      }
      const left = deadline - Date.now();
      if (left <= 0) {
        return null;
      }
      this.pending ??= this.reader.read();
      let timer: ReturnType<typeof setTimeout> | undefined;
      const result = await Promise.race([
        this.pending,
        new Promise<null>((resolve) => {
          timer = setTimeout(() => resolve(null), left);
        }),
      ]);
      clearTimeout(timer);
      if (result === null) {
        return null;
      }
      this.pending = null;
      if (result.done) {
        this.ended = true;
      } else {
        this.items.push(...this.parser.push(this.decoder.decode(result.value, { stream: true })));
      }
    }
  }
}

// --- Matching

function check(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function isDefault(value: unknown): boolean {
  return (
    value === null ||
    value === false ||
    (Array.isArray(value) && value.length === 0) ||
    (isObject(value) && Object.keys(value).length === 0)
  );
}

/** `actual` has every field of `expected`, equal; it may have more. A field left out equals its default. */
export function expectSubset(expected: unknown, actual: unknown, path = "$"): void {
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual) || actual.length !== expected.length) {
      throw new Error(`${path}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    }
    expected.forEach((item, index) => expectSubset(item, actual[index], `${path}[${index}]`));
    return;
  }
  if (isObject(expected)) {
    if (!isObject(actual)) {
      throw new Error(`${path}: expected an object, got ${JSON.stringify(actual)}`);
    }
    for (const [key, value] of Object.entries(expected)) {
      if (!(key in actual) && isDefault(value)) {
        continue;
      }
      expectSubset(value, actual[key], `${path}.${key}`);
    }
    return;
  }
  if (expected !== actual) {
    throw new Error(`${path}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

/** A `session/update`'s update, after checking the cursor rides on the notification and not on the update. */
function updateOf(message: JsonRpcMessage, what: string): SessionUpdate {
  check(
    "method" in message && message.method === "session/update",
    `${what}: expected session/update, got ${JSON.stringify(message)}`,
  );
  const params = message.params as { update?: SessionUpdate; _meta?: { agentchatkit?: { cursor?: unknown } } };
  check(typeof params._meta?.agentchatkit?.cursor === "string", `${what}: the notification carries a cursor`);
  check(params.update, `${what}: no update`);
  check(params.update._meta?.agentchatkit?.cursor === undefined, `${what}: the cursor is on the update`);
  return params.update;
}

/** Leaves out what the host decides for itself on what a write makes: when, and how it names the sender. */
function hostless(update: unknown): unknown {
  const copy = structuredClone(update) as { _meta?: { agentchatkit?: Record<string, unknown> } };
  delete copy._meta?.agentchatkit?.at;
  delete copy._meta?.agentchatkit?.sender;
  return copy;
}

// --- Fixtures, as the suite reads them

interface Fixture {
  server?: {
    before: SessionUpdate[];
    resume?: string;
    during?: SessionUpdate[];
    stream?: SessionUpdate[];
    error?: number;
    writes?: {
      request: { method: string; params: Record<string, unknown> };
      /** A change of the host's own instead of a request: applied, then expected on the stream. */
      host?: SessionUpdate;
      /** An edit with force on a failed message: a retry, which a host that never queues still runs. */
      retry?: boolean;
      result?: unknown;
      error?: number;
      stream: SessionUpdate[];
    }[];
    clients?: number;
    ask?: ElicitationCreateParams;
    answer?: unknown;
    then?: SessionUpdate[];
  };
}

function fixture(name: string): Fixture {
  const found = fixtures[name];
  check(found, `no fixture ${name}`);
  return found as Fixture;
}

// --- The cases

export function conformanceCases<Who>(harness: ConformanceHarness<Who>): ConformanceCase[] {
  const { adapter, capabilities } = harness;
  /** Whether the host's sessions hold this kind of update (`capabilities.updates`). */
  const holds = (update: SessionUpdate) =>
    capabilities.updates === undefined || capabilities.updates.includes(update.sessionUpdate);
  const wait = harness.timeoutMs ?? 2_000;
  const timers = new ManualTimers();
  const rooms = localRooms(adapter, timers);
  const secret = "conformance-secret";
  const url = "https://host.example/acp";
  const call = (request: Request) => handleAcp(request, { adapter, rooms, secret });
  const client = (sessionId: string) => new AcpTestClient(call, sessionId, url, harness.request);

  const owner = async (sessionId: string): Promise<Who> => {
    const who = await adapter.authorize(harness.request(url), sessionId);
    check(!isRefusal(who), `the owner may not read ${sessionId}`);
    return who;
  };
  const cursorNow = async (sessionId: string, who: Who): Promise<string> => {
    const read = await adapter.read(who, sessionId, null);
    check(!read.expired, "a read from start never expires");
    return read.cursor;
  };
  const apply = async (sessionId: string, update: SessionUpdate) => {
    await harness.apply(sessionId, update);
    await notifyChat(rooms, sessionId);
  };
  /** A followed session: initialized, stream open, resumed. Answers what the resume carried before its answer. */
  const follow = async (sessionId: string, cursor: string | null) => {
    const c = client(sessionId);
    const initialized = await c.initialize();
    check(
      initialized.status === 200 && c.connection,
      `initialize: expected 200 and a connection, got ${initialized.status}`,
    );
    const opened = await c.open();
    check(opened.status === 200, `the stream: expected 200, got ${opened.status}`);
    check(opened.headers.get("Content-Type")?.startsWith("text/event-stream"), "the stream is text/event-stream");
    const id = await c.request("session/resume", {
      sessionId,
      cwd: "/",
      replayFrom: cursor === null ? { type: "start" } : { type: "_cursor", cursor },
    });
    const replay: JsonRpcMessage[] = [];
    for (;;) {
      const message = await c.next(wait);
      if ("id" in message && message.id === id && !("method" in message)) {
        return { client: c, replay, answer: message };
      }
      replay.push(message);
    }
  };
  const closeAll = async (clients: AcpTestClient[]) => {
    await Promise.all(clients.map((c) => c.close()));
  };

  const cases: ConformanceCase[] = [];

  cases.push({
    name: "messages.json: every message a client sends reads as the profile's",
    run: async () => {
      const { client_to_host: sent, host_to_client: received } = fixtures.messages as {
        client_to_host: { name: string; message: Record<string, unknown> }[];
        host_to_client: { name: string; message: Record<string, unknown> }[];
      };
      for (const { name, message } of sent) {
        const incoming = readIncoming(message);
        check(incoming.kind !== "invalid", `${name}: not a JSON-RPC message`);
        const params = (message.params ?? {}) as { sessionId?: string };
        const sessionId = params.sessionId ?? "chat-1";
        const read =
          message.method === "session/resume"
            ? readResume(params, sessionId)
            : message.method === "session/prompt"
              ? readPromptParams(params, sessionId)
              : message.method === "_agentchatkit/edit"
                ? readEditParams(params, sessionId)
                : message.method === "_agentchatkit/remove"
                  ? readRemoveParams(params, sessionId)
                  : "result" in message
                    ? readElicitationResult(message.result)
                    : null;
        check(typeof read !== "string", `${name}: ${read}`);
      }
      for (const { name, message } of received) {
        check(readIncoming(message).kind !== "invalid", `${name}: not a JSON-RPC message`);
        if (message.method === "session/update") {
          updateOf(message as unknown as JsonRpcMessage, name);
        }
      }
    },
  });

  cases.push({
    name: "transport.json: initialize, the session stream, keep-alive, and every refusal",
    run: async () => {
      const sessionId = await harness.reset();
      const c = client(sessionId);
      const initialized = await c.initialize();
      check(initialized.status === 200, `initialize: expected 200, got ${initialized.status}`);
      check(c.connection, `initialize answers ${CONNECTION_HEADER}`);
      const expected = (
        fixtures.messages as { host_to_client: { name: string; message: { result: Record<string, unknown> } }[] }
      ).host_to_client.find((entry) => entry.name === "initialized");
      check(expected, "messages.json has initialized");
      const { agentInfo: _info, ...result } = expected.message.result;
      expectSubset({ jsonrpc: "2.0", id: 1, result }, await initialized.json(), "initialize");

      const status = async (response: Promise<Response>, want: number, what: string) => {
        const got = await response;
        await got.body?.cancel();
        check(got.status === want, `${what}: expected ${want}, got ${got.status}`);
      };
      const headers = (extra: Record<string, string> = {}) => ({
        "Content-Type": "application/json",
        [CONNECTION_HEADER]: c.connection ?? "",
        [SESSION_HEADER]: sessionId,
        ...extra,
      });
      const body = JSON.stringify({ jsonrpc: "2.0", id: 9, method: "session/resume", params: { sessionId } });
      await status(
        call(harness.request(url, { method: "POST", headers: { "Content-Type": "application/json" }, body })),
        400,
        "a request before initialize",
      );
      await status(
        call(
          harness.request(url, { method: "POST", headers: headers({ [CONNECTION_HEADER]: "forged.zz.sig" }), body }),
        ),
        404,
        "an unknown connection's request",
      );
      await status(
        call(
          harness.request(url, {
            headers: { Accept: "text/event-stream", [CONNECTION_HEADER]: "forged.zz.sig", [SESSION_HEADER]: sessionId },
          }),
        ),
        404,
        "an unknown connection's stream",
      );
      await status(
        call(harness.request(url, { headers: { [CONNECTION_HEADER]: c.connection, [SESSION_HEADER]: sessionId } })),
        406,
        "a stream without Accept: text/event-stream",
      );
      await status(
        call(harness.request(url, { method: "POST", headers: headers({ "Content-Type": "text/plain" }), body })),
        415,
        "a POST that is not JSON",
      );
      await status(
        call(harness.request(url, { method: "POST", headers: headers(), body: `[${body}]` })),
        400,
        "a batch",
      );
      const { [SESSION_HEADER]: _session, ...noSession } = headers();
      await status(
        call(harness.request(url, { method: "POST", headers: noSession, body })),
        400,
        `a POST without ${SESSION_HEADER}`,
      );
      const streamHeaders = {
        Accept: "text/event-stream",
        [CONNECTION_HEADER]: c.connection,
        [SESSION_HEADER]: sessionId,
      };
      await status(call(harness.request(url, { headers: streamHeaders }, "none")), 401, "a stream with no bearer");
      await status(
        call(harness.request(url, { method: "POST", headers: headers(), body }, "none")),
        401,
        "a request with no bearer",
      );
      await status(
        call(harness.request(url, { headers: streamHeaders }, "stranger")),
        harness.strangerStatus ?? 403,
        "someone else's stream",
      );
      await status(
        call(harness.request(url, { headers: { ...streamHeaders, [SESSION_HEADER]: `no-such-session-${sessionId}` } })),
        404,
        "a stream of no session",
      );

      const opened = await c.open();
      check(opened.status === 200, `the stream: expected 200, got ${opened.status}`);
      check(
        opened.headers.get("X-Content-Type-Options") === "nosniff",
        "the stream says nosniff: URLSession waits to sniff otherwise",
      );
      try {
        const first = await c.comment(wait);
        check(first === "open", `expected the stream to start with an open comment at once, got ${first}`);
        timers.advance(15_000);
        const comment = await c.comment(wait);
        check(comment === "keep-alive", `expected the keep-alive comment, got ${comment}`);
        const unknown = await c.request("session/nothing", { sessionId });
        const answer = await c.next(wait);
        check(
          "error" in answer && answer.id === unknown,
          `an unknown method answers an error, got ${JSON.stringify(answer)}`,
        );
        check(
          answer.error.code === ERRORS.methodNotFound,
          `an unknown method: expected -32601, got ${answer.error.code}`,
        );
        const missing: [boolean, string, unknown][] = [
          [capabilities.edit, "_agentchatkit/edit", { sessionId, messageId: "x", force: true }],
          [capabilities.remove, "_agentchatkit/remove", { sessionId, messageId: "x" }],
        ];
        for (const [can, method, params] of missing) {
          const has = method === "_agentchatkit/edit" ? adapter.edit : adapter.remove;
          if (!can && !has) {
            const id = await c.request(method, params);
            const reply = await c.next(wait);
            check(
              "error" in reply && reply.id === id && reply.error.code === ERRORS.methodNotFound,
              `${method} without it: -32601`,
            );
          }
        }
      } finally {
        await c.close();
      }
    },
  });

  for (const name of ["resume-start", "resume-cursor", "resume-expired"]) {
    const server = fixture(name).server;
    check(server, `${name} has a server half`);
    const skip =
      server.resume === "expired" && !harness.expire && !harness.staleCursor
        ? "the harness can neither expire cursors nor name a stale one"
        : undefined;
    cases.push({
      name: `${name}.json: the resume and what follows it`,
      ...(skip ? { skip } : {}),
      run: async () => {
        const sessionId = await harness.reset();
        const who = await owner(sessionId);
        const places: string[] = [];
        for (const update of server.before) {
          // A kind the host has none of is not applied; its place is the one before it, so "@n" still counts it.
          if (holds(update)) {
            await harness.apply(sessionId, update);
          }
          places.push(await cursorNow(sessionId, who));
        }
        const clients: AcpTestClient[] = [];
        try {
          if (server.resume === "expired") {
            let old = places.at(-1) ?? null;
            if (harness.expire) {
              await harness.expire(sessionId);
            } else if (harness.staleCursor && old !== null) {
              old = await harness.staleCursor(sessionId, old);
            }
            const { client: c, replay, answer } = await follow(sessionId, old);
            clients.push(c);
            check(replay.length === 0, `an expired cursor replays nothing, got ${replay.length}`);
            check(
              "error" in answer && answer.error.code === server.error,
              `an expired cursor: expected ${server.error}, got ${JSON.stringify(answer)}`,
            );
            const again = await follow(sessionId, null);
            clients.push(again.client);
            check("result" in again.answer, "a resume from start after it answers");
            check(again.replay.length > 0, "a resume from start replays the session");
            return;
          }
          const cursor = server.resume === "start" ? null : (places[Number(server.resume?.slice(1)) - 1] ?? null);
          check(server.resume === "start" || cursor !== null, `${name}: no place ${server.resume}`);
          const { client: c, replay, answer } = await follow(sessionId, cursor);
          clients.push(c);
          check("result" in answer, `the resume answers, got ${JSON.stringify(answer)}`);
          const stream = (server.stream ?? []).filter(holds);
          const during = (server.during ?? []).filter(holds);
          const atResume = stream.length - during.length;
          check(replay.length === atResume, `the resume carried ${replay.length} updates, expected ${atResume}`);
          replay.forEach((message, index) =>
            expectSubset(stream[index], updateOf(message, `replay ${index}`), `${name} replay ${index}`),
          );
          for (const [index, update] of during.entries()) {
            await apply(sessionId, update);
            expectSubset(
              stream[atResume + index],
              updateOf(await c.next(wait), `live ${index}`),
              `${name} live ${index}`,
            );
          }
          await c.none(50);
        } finally {
          await closeAll(clients);
        }
      },
    });
  }

  const lifecycle = fixture("prompt-lifecycle").server;
  check(lifecycle?.writes, "prompt-lifecycle has writes");
  cases.push({
    name: "prompt-lifecycle.json: prompt, a repeat, edit, send now, remove, conflict",
    ...(adapter.prompt ? {} : { skip: "the adapter takes no prompts" }),
    run: async () => {
      const sessionId = await harness.reset();
      const who = await owner(sessionId);
      for (const update of lifecycle.before) {
        await harness.apply(sessionId, update);
      }
      const { client: c } = await follow(sessionId, await cursorNow(sessionId, who));
      const bound = new Map<string, string>();
      const bind = (value: unknown): unknown =>
        typeof value === "string" && value.startsWith("@") ? (bound.get(value) ?? value) : value;
      const resolve = (value: unknown): unknown =>
        Array.isArray(value)
          ? value.map(resolve)
          : isObject(value)
            ? Object.fromEntries(Object.entries(value).map(([k, v]) => [k, resolve(v)]))
            : bind(value);
      try {
        for (const [index, write] of (lifecycle.writes ?? []).entries()) {
          if (write.host) {
            // The host's own change (a delivery that failed), applied as the host would, then seen on the stream.
            await apply(sessionId, resolve(write.host) as SessionUpdate);
            const what = `host step ${index}`;
            for (const [at, expected] of (write.stream ?? []).entries()) {
              const want = resolve({ ...expected, messageId: `@${(expected as { messageId: string }).messageId}` });
              expectSubset(
                hostless(want as Record<string, unknown>),
                updateOf(await c.next(wait), what),
                `${what} update ${at}`,
              );
            }
            await c.none(30);
            continue;
          }
          const { method, params } = write.request;
          const sendNow =
            method === "_agentchatkit/edit" && params.force === true && params.prompt === undefined && !write.retry;
          if (
            (method === "_agentchatkit/edit" && !capabilities.edit) ||
            (method === "_agentchatkit/remove" && !capabilities.remove) ||
            (sendNow && !capabilities.queues)
          ) {
            continue;
          }
          const what = `write ${index} (${method})`;
          const id = await c.request(method, { ...(resolve(params) as object), sessionId });
          const updates: SessionUpdate[] = [];
          let answer: JsonRpcMessage | null = null;
          while (answer === null || (updates.length < write.stream.length && !("error" in answer))) {
            const message = await c.next(wait);
            if ("id" in message && message.id === id && !("method" in message)) {
              answer = message;
            } else {
              updates.push(updateOf(message, what));
            }
          }
          if (write.error !== undefined) {
            check(
              "error" in answer && answer.error.code === write.error,
              `${what}: expected error ${write.error}, got ${JSON.stringify(answer)}`,
            );
          } else {
            check("result" in answer, `${what}: expected a result, got ${JSON.stringify(answer)}`);
            const got = (answer.result as { messageId?: unknown }).messageId;
            const want = (write.result as { messageId: string }).messageId;
            check(typeof got === "string", `${what}: answers a messageId`);
            if (!bound.has(want)) {
              bound.set(want, got);
            }
            check(
              bound.get(want) === got,
              `${what}: answered ${got}, expected the ${want} of before (${bound.get(want)})`,
            );
          }
          write.stream.forEach((expected, at) => {
            const want = resolve({
              ...expected,
              messageId: `@${(expected as { messageId: string }).messageId}`,
            }) as Record<string, unknown>;
            const meta = (want._meta as { agentchatkit?: { status?: string } } | undefined)?.agentchatkit;
            if (meta?.status === "queued" && !capabilities.queues) {
              meta.status = "pending";
            }
            expectSubset(hostless(want), updates[at], `${what} update ${at}`);
          });
          await c.none(30);
        }
      } finally {
        await c.close();
      }
    },
  });

  const question = fixture("question").server;
  check(question?.ask && question.then, "question has ask and then");
  cases.push({
    name: "question.json: every client is asked, the first answer wins, the others are cancelled",
    ...(capabilities.answer && harness.ask && adapter.answer
      ? {}
      : { skip: "the host takes no questions (capabilities.answer, ask, adapter.answer)" }),
    run: async () => {
      const sessionId = await harness.reset();
      for (const update of question.before) {
        await harness.apply(sessionId, update);
      }
      const a = await follow(sessionId, null);
      const b = await follow(sessionId, null);
      const clients = [a.client, b.client];
      try {
        const { sessionId: _s, ...ask } = question.ask as ElicitationCreateParams;
        await harness.ask?.(sessionId, ask);
        await notifyChat(rooms, sessionId);
        let requestId: string | number | null = null;
        for (const [index, c] of clients.entries()) {
          const asked = await c.next(wait);
          check(
            "method" in asked && asked.method === "elicitation/create" && "id" in asked,
            `client ${index}: expected elicitation/create, got ${JSON.stringify(asked)}`,
          );
          expectSubset({ ...ask, sessionId }, asked.params, `client ${index} question`);
          requestId ??= asked.id;
          check(asked.id === requestId, "every client is asked the same request");
          expectSubset(
            { sessionUpdate: "state_update", state: "requires_action" },
            updateOf(await c.next(wait), `client ${index} state`),
          );
        }
        const late = await follow(sessionId, null);
        clients.push(late.client);
        const reasked = late.replay.find((message) => "method" in message && message.method === "elicitation/create");
        check(reasked, "a client that resumes while the question is open is asked again");

        await a.client.post({ jsonrpc: "2.0", id: requestId, result: question.answer });
        for (const [index, c] of clients.entries()) {
          const seen: JsonRpcMessage[] = [];
          while (
            !seen.some(
              (m) => "method" in m && m.method === "session/update" && updateOf(m, "").sessionUpdate === "user_message",
            )
          ) {
            seen.push(await c.next(wait));
          }
          const cancelled = seen.some(
            (m) =>
              "method" in m &&
              m.method === "$/cancel_request" &&
              (m.params as { requestId?: unknown }).requestId === requestId,
          );
          check(
            cancelled === (index !== 0),
            index === 0 ? "the client that answered is not cancelled" : `client ${index} is cancelled`,
          );
        }
        await b.client.post({ jsonrpc: "2.0", id: requestId, result: question.answer });
        const then = question.then?.at(-1);
        check(then, "question has a last update");
        await apply(sessionId, then);
        for (const [index, c] of clients.entries()) {
          // The host may say more on its own first (its own state after the answer): skip to the update applied.
          for (;;) {
            const update = updateOf(await c.next(wait), `client ${index} then`);
            check(update.sessionUpdate !== "user_message", `client ${index}: a second answer is shown`);
            try {
              expectSubset(then, update);
              break;
            } catch {
              continue;
            }
          }
        }
      } finally {
        await closeAll(clients);
      }
    },
  });

  cases.push({
    name: "the rooms stop their timers once every stream has gone",
    run: async () => {
      rooms.closeAll();
      await new Promise((resolve) => setTimeout(resolve, 0));
      check(timers.pending === 0, `${timers.pending} timers still set`);
    },
  });

  return cases;
}
