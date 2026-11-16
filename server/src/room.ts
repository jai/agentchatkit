/**
 * The room: one Durable Object per session, holding each connection's session stream.
 *
 * A connection follows once it has resumed: the room replays the read after its cursor, the current state, any
 * open question, then answers. After that, each notify reads after the connection's own cursor and sends what is
 * new, so a change made while a connection resumes is read once it follows, and never sent twice. Connections at the
 * same cursor share one read. Nothing is stored: the host's storage is the session, and a room that restarts loses
 * only its streams, which resume with their cursors.
 */
import {
  type CancelRequestParams,
  type ElicitationCreateParams,
  ERRORS,
  failure,
  type Incoming,
  type JsonRpcMessage,
  type JsonRpcRequest,
  notification,
  readEditParams,
  readElicitationResult,
  readIncoming,
  readPromptParams,
  readRemoveParams,
  readResume,
  sessionUpdate,
  success,
} from "./acp.ts";
import { isRefusal, type LiveAdapter, type LiveRead, type LiveRefusal, type OpenQuestion } from "./adapter.ts";
import { encodeEvent, KEEP_ALIVE, KEEP_ALIVE_MS } from "./sse.ts";

/** The timers a room runs on: the platform's, or a test's fake clock. */
export interface RoomTimers {
  setInterval(run: () => void, ms: number): unknown;
  clearInterval(handle: unknown): void;
}

export const platformTimers: RoomTimers = {
  setInterval: (run, ms) => setInterval(run, ms),
  clearInterval: (handle) => clearInterval(handle as ReturnType<typeof setInterval>),
};

export interface LiveRoomOptions {
  /** A `: keep-alive` comment every this many ms. 15 s. */
  keepAliveMs?: number;
  /** Also read after each connection's cursor this often while the room has streams, for changes no write makes. Off. */
  refreshEvery?: number;
  timers?: RoomTimers;
  /** Where a failure is told. `console.error`. */
  log?: (message: string, error?: unknown) => void;
}

/** The Worker's binding for the rooms: a Durable Object namespace, as much of it as this needs. */
export interface LiveRooms {
  idFromName(name: string): unknown;
  get(id: never): { fetch(request: Request): Promise<Response> };
}

const ROOM_ORIGIN = "https://agentchat-live.room";
const WHO_HEADER = "X-AgentChat-Who";
/** Messages kept for a connection whose stream is not open, until it opens. */
const PENDING_LIMIT = 500;
/** Messages that could not go are dropped with the connection after this many keep-alive ticks without a stream. */
const IDLE_TICKS = 8;

function roomURL(path: string, sessionId: string, connection?: string): URL {
  const url = new URL(path, ROOM_ORIGIN);
  url.searchParams.set("session", sessionId);
  if (connection !== undefined) {
    url.searchParams.set("connection", connection);
  }
  return url;
}

function whoHeader(who: unknown): Record<string, string> {
  return { [WHO_HEADER]: encodeURIComponent(JSON.stringify(who)) };
}

function roomOf(rooms: LiveRooms, sessionId: string) {
  return rooms.get(rooms.idFromName(sessionId) as never);
}

/** Opens a connection's session stream in the session's room. */
export function openStream(rooms: LiveRooms, sessionId: string, connection: string, who: unknown): Promise<Response> {
  return roomOf(rooms, sessionId).fetch(
    new Request(roomURL("/stream", sessionId, connection), { headers: whoHeader(who) }),
  );
}

/** Hands one JSON-RPC message from a connection to the session's room; its answer goes on the stream. */
export function postToRoom(
  rooms: LiveRooms,
  sessionId: string,
  connection: string,
  who: unknown,
  message: unknown,
): Promise<Response> {
  return roomOf(rooms, sessionId).fetch(
    new Request(roomURL("/rpc", sessionId, connection), {
      method: "POST",
      headers: { ...whoHeader(who), "Content-Type": "application/json" },
      body: JSON.stringify(message),
    }),
  );
}

/** Ends a connection in the session's room. */
export function closeConnection(rooms: LiveRooms, sessionId: string, connection: string): Promise<Response> {
  return roomOf(rooms, sessionId).fetch(new Request(roomURL("/close", sessionId, connection), { method: "POST" }));
}

/**
 * Tells the session's room it changed: each following connection reads after its cursor and gets what is new. A
 * failure is logged, never thrown: the client's next resume catches up.
 */
export async function notifyChat(rooms: LiveRooms, sessionId: string): Promise<void> {
  try {
    const response = await roomOf(rooms, sessionId).fetch(
      new Request(roomURL("/notify", sessionId), { method: "POST" }),
    );
    await response.body?.cancel();
  } catch (error) {
    console.error("agentchat-live: room not told", error);
  }
}

/**
 * The agent asks: the host stores the question so `read` answers it (and the state `requires_action`), then calls
 * this. Every connection gets `elicitation/create`; a connection that resumes while it is open gets it again.
 */
export const notifyQuestion = notifyChat;

const encoder = new TextEncoder();

interface Connection {
  id: string;
  who: unknown;
  writer: WritableStreamDefaultWriter<Uint8Array> | null;
  /** What waits for the stream to open. */
  pending: string[];
  /** Its place once it follows; null until it has resumed. */
  cursor: string | null;
  /** A resume or a read is running for it. */
  busy: boolean;
  /** The room was notified while it read: read again after. */
  dirty: boolean;
  /** The read loop under way, if one is. */
  pumping: Promise<void> | null;
  /** The question it has been sent and not had cancelled. */
  question: string | null;
  /** Its requests, one at a time, in the order they came. */
  queue: Promise<void>;
  idleTicks: number;
}

/** A session's room. `LiveRoom.fetch` serves the Worker's calls; `createLiveRoom` wraps it as a Durable Object. */
export class LiveRoom<Who> {
  private readonly adapter: LiveAdapter<Who>;
  private readonly keepAliveMs: number;
  private readonly refreshEvery: number | null;
  private readonly timers: RoomTimers;
  private readonly log: (message: string, error?: unknown) => void;
  private readonly connections = new Map<string, Connection>();
  private readonly reads = new Map<string, Promise<LiveRead>>();
  /** Questions answered here: the first answer wins. */
  private readonly answered = new Set<string>();
  private keepAlive: unknown = null;
  private refresh: unknown = null;
  private sessionId = "";

  constructor(adapter: LiveAdapter<Who>, options: LiveRoomOptions = {}) {
    this.adapter = adapter;
    this.keepAliveMs = options.keepAliveMs ?? KEEP_ALIVE_MS;
    this.refreshEvery = options.refreshEvery ?? null;
    this.timers = options.timers ?? platformTimers;
    this.log = options.log ?? ((message, error) => console.error(`agentchat-live: ${message}`, error ?? ""));
  }

  /** Open session streams. */
  get streams(): number {
    let count = 0;
    for (const connection of this.connections.values()) {
      if (connection.writer) {
        count += 1;
      }
    }
    return count;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const sessionId = url.searchParams.get("session");
    if (!sessionId) {
      return new Response("which session?\n", { status: 400 });
    }
    this.sessionId = sessionId;
    const id = url.searchParams.get("connection");
    const header = request.headers.get(WHO_HEADER);
    const who = header === null ? null : (JSON.parse(decodeURIComponent(header)) as Who);
    switch (url.pathname) {
      case "/notify":
        return Response.json({ connections: this.notify() });
      case "/stream":
        return id && who !== null ? this.open(id, who) : new Response("who?\n", { status: 400 });
      case "/rpc":
        if (!id || who === null) {
          return new Response("who?\n", { status: 400 });
        }
        this.receive(id, who, await request.json().catch(() => null));
        return new Response(null, { status: 202 });
      case "/close":
        if (id) {
          this.close(id);
        }
        return new Response(null, { status: 202 });
      default:
        return new Response("not found\n", { status: 404 });
    }
  }

  /** A connection's session stream. A second one for the same connection replaces the first. */
  open(id: string, who: Who): Response {
    const connection = this.connection(id, who);
    if (connection.writer) {
      this.endStream(connection);
    }
    const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
    const writer = writable.getWriter();
    connection.writer = writer;
    connection.idleTicks = 0;
    writer.closed.catch(() => {
      if (connection.writer === writer) {
        connection.writer = null;
        this.tidy();
      }
    });
    // A first byte at once: URLSession holds a response back until it has bytes to sniff, and the next may be a
    // keep-alive 15 s away (found in the end-to-end walkthrough, docs/end-to-end-walkthrough.md).
    const waiting = connection.pending.splice(0);
    this.write(connection, ": open\n\n" + waiting.join(""));
    this.startTimers();
    return new Response(readable, {
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Accel-Buffering": "no",
        "X-Content-Type-Options": "nosniff",
      },
    });
  }

  /** One message from a connection, handled after its earlier ones. */
  receive(id: string, who: Who, body: unknown): void {
    const connection = this.connection(id, who);
    const incoming = readIncoming(body);
    connection.queue = connection.queue
      .then(() => this.handle(connection, who, incoming))
      .catch((error) => {
        this.log("a request failed", error);
        if (incoming.kind === "request") {
          this.send(connection, failure(incoming.message.id, ERRORS.internal, "the server failed"));
        }
      });
  }

  /** The session changed: every following connection reads after its cursor. Answers how many follow. */
  notify(): number {
    let following = 0;
    for (const connection of this.connections.values()) {
      // One that resumes right now reads again once it follows: its resume's read may predate this change.
      if (connection.cursor === null && !connection.busy) {
        continue;
      }
      following += 1;
      connection.dirty = true;
      if (!connection.busy) {
        this.pump(connection);
      }
    }
    return following;
  }

  /** Notifies, then waits until every connection has read and sent what is new. */
  async settle(): Promise<void> {
    this.notify();
    await Promise.all([...this.connections.values()].map((connection) => connection.pumping));
  }

  /** Ends a connection: its stream closes, and what waited for it is dropped. */
  close(id: string): void {
    const connection = this.connections.get(id);
    if (!connection) {
      return;
    }
    this.endStream(connection);
    this.connections.delete(id);
    this.tidy();
  }

  /** Ends every stream: a deploy moving the room. Clients reconnect and resume. */
  closeAll(): void {
    for (const id of [...this.connections.keys()]) {
      this.close(id);
    }
  }

  // --- Requests

  private async handle(connection: Connection, who: Who, incoming: Incoming): Promise<void> {
    switch (incoming.kind) {
      case "invalid":
        this.send(connection, incoming.error);
        return;
      case "notification":
        // `$/cancel_request` for one of ours: requests here answer at once, so there is nothing to stop.
        return;
      case "response":
        await this.answer(connection, who, incoming.message);
        return;
      case "request":
        await this.request(connection, who, incoming.message);
    }
  }

  private async request(connection: Connection, who: Who, request: JsonRpcRequest): Promise<void> {
    const { id, method, params } = request;
    const invalid = (message: string) => this.send(connection, failure(id, ERRORS.invalidParams, message));
    switch (method) {
      case "session/resume": {
        const resume = readResume(params, this.sessionId);
        if (typeof resume === "string") {
          return invalid(resume);
        }
        const cursor = resume.replayFrom?.type === "_cursor" ? resume.replayFrom.cursor : null;
        return this.resume(connection, who, id, cursor);
      }
      case "session/prompt": {
        if (!this.adapter.prompt) {
          return this.notFound(connection, id, method);
        }
        const prompt = readPromptParams(params, this.sessionId);
        if (typeof prompt === "string") {
          return invalid(prompt);
        }
        const ours = prompt._meta?.agentchatkit ?? {};
        const result = await this.adapter.prompt(who, this.sessionId, {
          prompt: prompt.prompt,
          clientRef: ours.clientRef ?? null,
          force: ours.force ?? false,
        });
        if (isRefusal(result)) {
          return this.refused(connection, id, result);
        }
        if (!result.repeat) {
          await this.settle();
        }
        return this.send(connection, success(id, { messageId: result.messageId }));
      }
      case "_agentchatkit/edit": {
        if (!this.adapter.edit) {
          return this.notFound(connection, id, method);
        }
        const edit = readEditParams(params, this.sessionId);
        if (typeof edit === "string") {
          return invalid(edit);
        }
        const body: { prompt?: typeof edit.prompt; force?: boolean } = {};
        if (edit.prompt !== undefined) {
          body.prompt = edit.prompt;
        }
        if (edit.force !== undefined) {
          body.force = edit.force;
        }
        return this.written(connection, id, await this.adapter.edit(who, this.sessionId, edit.messageId, body));
      }
      case "_agentchatkit/remove": {
        if (!this.adapter.remove) {
          return this.notFound(connection, id, method);
        }
        const remove = readRemoveParams(params, this.sessionId);
        if (typeof remove === "string") {
          return invalid(remove);
        }
        return this.written(connection, id, await this.adapter.remove(who, this.sessionId, remove.messageId));
      }
      default:
        return this.notFound(connection, id, method);
    }
  }

  private async written(connection: Connection, id: JsonRpcRequest["id"], result: string | LiveRefusal) {
    if (isRefusal(result)) {
      return this.refused(connection, id, result);
    }
    await this.settle();
    this.send(connection, success(id, { messageId: result }));
  }

  private refused(connection: Connection, id: JsonRpcRequest["id"], refusal: LiveRefusal): void {
    const { status, message } = refusal.refusal;
    const code =
      status === 409 ? ERRORS.conflict : status === 400 || status === 404 ? ERRORS.invalidParams : ERRORS.internal;
    this.send(connection, failure(id, code, message));
  }

  private notFound(connection: Connection, id: JsonRpcRequest["id"], method: string): void {
    this.send(connection, failure(id, ERRORS.methodNotFound, `${method} is not served here`));
  }

  /** Replays after `cursor` (null: from start), the current state, any open question, then answers. */
  private async resume(connection: Connection, who: Who, id: JsonRpcRequest["id"], cursor: string | null) {
    connection.who = who;
    connection.cursor = null;
    connection.busy = true;
    connection.dirty = false;
    try {
      const read = await this.adapter.read(who, this.sessionId, cursor);
      if (read.expired) {
        this.send(connection, failure(id, ERRORS.invalidParams, "cursor expired: resume from start"));
        return;
      }
      for (const { cursor: at, update } of read.updates) {
        if (update.sessionUpdate !== "state_update") {
          this.send(connection, sessionUpdate(this.sessionId, update, at));
        }
      }
      this.send(connection, sessionUpdate(this.sessionId, read.state, read.cursor));
      connection.question = null;
      if (read.question && !this.answered.has(read.question.id)) {
        this.ask(connection, read.question);
      }
      connection.cursor = read.cursor;
      this.send(connection, success(id, {}));
    } finally {
      connection.busy = false;
    }
    if (connection.dirty) {
      this.pump(connection);
    }
  }

  /** A response from a client: an answer to our `elicitation/create`. The first one wins. */
  private async answer(connection: Connection, who: Who, response: JsonRpcMessage): Promise<void> {
    if (!("id" in response) || response.id === null || !("result" in response)) {
      return; // An error response: the client could not show it. Others may still answer.
    }
    const question = String(response.id);
    if (connection.question !== question || this.answered.has(question)) {
      return;
    }
    const answer = readElicitationResult(response.result);
    if (typeof answer === "string") {
      this.log(`an answer to ${question} was not one: ${answer}`);
      return;
    }
    if (!this.adapter.answer) {
      this.log(`an answer to ${question} came, and this host takes none`);
      return;
    }
    this.answered.add(question);
    const result = await this.adapter.answer(who, this.sessionId, question, answer);
    if (isRefusal(result)) {
      this.answered.delete(question);
      this.log(`the answer to ${question} was refused: ${result.refusal.message}`);
      return;
    }
    connection.question = null;
    for (const other of this.connections.values()) {
      if (other !== connection && other.question === question) {
        this.cancel(other, question);
      }
    }
    await this.settle();
  }

  // --- Following

  private pump(connection: Connection): Promise<void> {
    connection.busy = true;
    connection.pumping = this.readLoop(connection).finally(() => {
      connection.busy = false;
      connection.pumping = null;
    });
    return connection.pumping;
  }

  private async readLoop(connection: Connection): Promise<void> {
    try {
      while (connection.dirty && connection.cursor !== null && this.connections.has(connection.id)) {
        connection.dirty = false;
        const cursor = connection.cursor;
        const read = await this.sharedRead(connection, cursor);
        if (connection.cursor !== cursor) {
          continue; // It resumed meanwhile.
        }
        if (read.expired) {
          // The host's history moved under it: end the stream, so the client resumes, is refused, and starts over.
          this.endStream(connection);
          connection.cursor = null;
          return;
        }
        if (read.question && connection.question !== read.question.id && !this.answered.has(read.question.id)) {
          this.ask(connection, read.question);
        }
        for (const { cursor: at, update } of read.updates) {
          this.send(connection, sessionUpdate(this.sessionId, update, at));
        }
        if (!read.question && connection.question !== null) {
          this.cancel(connection, connection.question);
        }
        connection.cursor = read.cursor;
      }
    } catch (error) {
      this.log("a read failed", error);
    }
  }

  /** Connections at the same cursor share a read that is under way. */
  private sharedRead(connection: Connection, cursor: string): Promise<LiveRead> {
    let read = this.reads.get(cursor);
    if (!read) {
      read = this.adapter.read(connection.who as Who, this.sessionId, cursor);
      this.reads.set(cursor, read);
      const forget = () => this.reads.delete(cursor);
      read.then(forget, forget);
    }
    return read;
  }

  private ask(connection: Connection, question: OpenQuestion): void {
    connection.question = question.id;
    this.send(connection, {
      jsonrpc: "2.0",
      id: question.id,
      method: "elicitation/create",
      params: { ...question.params, sessionId: this.sessionId } satisfies ElicitationCreateParams,
    });
  }

  private cancel(connection: Connection, question: string): void {
    connection.question = null;
    this.send(connection, notification<CancelRequestParams>("$/cancel_request", { requestId: question }));
  }

  // --- Streams

  private connection(id: string, who: unknown): Connection {
    let connection = this.connections.get(id);
    if (!connection) {
      connection = {
        id,
        who,
        writer: null,
        pending: [],
        cursor: null,
        busy: false,
        dirty: false,
        pumping: null,
        question: null,
        queue: Promise.resolve(),
        idleTicks: 0,
      };
      this.connections.set(id, connection);
    }
    connection.who = who;
    return connection;
  }

  private send(connection: Connection, message: JsonRpcMessage): void {
    const text = encodeEvent(message);
    if (connection.writer) {
      this.write(connection, text);
    } else if (connection.pending.length < PENDING_LIMIT) {
      connection.pending.push(text);
    }
  }

  private write(connection: Connection, text: string): void {
    const writer = connection.writer;
    // Not awaited: writes queue in order, and a client that has gone rejects them, which ends the stream.
    writer?.write(encoder.encode(text)).catch(() => {
      if (connection.writer === writer) {
        connection.writer = null;
        this.tidy();
      }
    });
  }

  private endStream(connection: Connection): void {
    const writer = connection.writer;
    connection.writer = null;
    writer?.close().catch(() => {});
  }

  private startTimers(): void {
    if (this.keepAlive === null) {
      this.keepAlive = this.timers.setInterval(() => this.tick(), this.keepAliveMs);
    }
    if (this.refreshEvery !== null && this.refresh === null) {
      this.refresh = this.timers.setInterval(() => this.notify(), this.refreshEvery);
    }
  }

  private tick(): void {
    for (const connection of [...this.connections.values()]) {
      if (connection.writer) {
        this.write(connection, KEEP_ALIVE);
      } else {
        connection.idleTicks += 1;
        if (connection.idleTicks >= IDLE_TICKS) {
          this.connections.delete(connection.id);
        }
      }
    }
    this.tidy();
  }

  /** No stream left: the timers stop, so a room with nobody watching costs nothing. */
  private tidy(): void {
    if (this.streams > 0) {
      return;
    }
    if (this.keepAlive !== null) {
      this.timers.clearInterval(this.keepAlive);
      this.keepAlive = null;
    }
    if (this.refresh !== null) {
      this.timers.clearInterval(this.refresh);
      this.refresh = null;
    }
  }
}

/**
 * The room as a Durable Object class, for the host Worker to export and bind:
 *
 * ```ts
 * export const LiveRoomObject = createLiveRoom((env: Env) => feedbackAdapter(env), { refreshEvery: 15_000 });
 * ```
 */
export function createLiveRoom<Env, Who>(makeAdapter: (env: Env) => LiveAdapter<Who>, options: LiveRoomOptions = {}) {
  return class LiveRoomObject {
    readonly room: LiveRoom<Who>;

    constructor(_state: unknown, env: Env) {
      this.room = new LiveRoom(makeAdapter(env), options);
    }

    fetch(request: Request): Promise<Response> {
      return this.room.fetch(request);
    }
  };
}
