/**
 * Sessions in memory, with a reference adapter: the conformance suite's own host, and a fake server for a host's
 * tests and demos. It keeps every update, so a resume after any cursor replays each one.
 *
 * Its bearer is `Bearer token-<login>`; a session belongs to the login that created it. Its cursor is
 * `<epoch>:<n>`: `expire` moves the epoch on, so every cursor handed out before can no longer be resumed.
 */
import type {
  AgentChatMeta,
  ContentBlock,
  ElicitationCreateParams,
  MessageStatus,
  SessionUpdate,
  StateUpdate,
  UserMessageUpdate,
} from "./acp.ts";
import {
  type CursoredUpdate,
  type ElicitationAnswer,
  type LiveAdapter,
  type LiveRead,
  type OpenQuestion,
  refuse,
} from "./adapter.ts";

export interface MemoryWho {
  login: string;
  name: string | null;
}

export interface MemoryOptions {
  /** Prompts sent while the agent runs wait as `queued`. FeedbackKit's host never queues. True. */
  queues?: boolean;
  /** The newest messages a resume from start replays. 200. */
  retained?: number;
  /** How a login is named. Its login. */
  names?: Record<string, string>;
  now?: () => Date;
  /** The largest file `_agentchatkit/upload` takes, in bytes. 50 MB. */
  maxUpload?: number;
}

/** A file an upload made room for: its bytes once put. */
export interface MemoryFile {
  mimeType: string;
  size: number;
  data: Uint8Array | null;
}

interface Session {
  owner: string;
  epoch: number;
  count: number;
  log: CursoredUpdate[];
  /** Each message as it stands, by id, in the order first seen. */
  messages: Map<string, { cursor: string; update: SessionUpdate }>;
  state: StateUpdate;
  question: OpenQuestion | null;
  refs: Map<string, string>;
  prompts: number;
  questions: number;
}

const idleState: StateUpdate = { sessionUpdate: "state_update", state: "idle", _meta: { agentchatkit: {} } };

function ours(update: { _meta?: { agentchatkit?: AgentChatMeta } }): AgentChatMeta {
  return update._meta?.agentchatkit ?? {};
}

function messageKey(update: SessionUpdate): string | null {
  switch (update.sessionUpdate) {
    case "user_message":
    case "agent_message":
    case "agent_message_chunk":
      return update.messageId;
    case "tool_call_update":
      return `tool:${update.toolCallId}`;
    default:
      return null;
  }
}

/** ACP's patch rules: fields given replace, fields left out are kept; our `_meta` merges key by key. */
function patch(held: SessionUpdate | undefined, update: SessionUpdate): SessionUpdate {
  if (update.sessionUpdate === "agent_message_chunk") {
    const words = update.content.type === "text" ? update.content.text : "";
    if (held?.sessionUpdate === "agent_message") {
      const content = [...held.content];
      const last = content.at(-1);
      if (last?.type === "text") {
        content[content.length - 1] = { ...last, text: last.text + words };
      } else {
        content.push({ type: "text", text: words });
      }
      return { ...held, content };
    }
    return {
      sessionUpdate: "agent_message",
      messageId: update.messageId,
      content: [update.content],
      _meta: update._meta ?? {},
    };
  }
  if (!held) {
    return update;
  }
  const merged = { ...held, ...update } as SessionUpdate;
  const meta = { ...ours(held), ...ours(update) };
  return { ...merged, _meta: { ...held._meta, ...update._meta, agentchatkit: meta } } as SessionUpdate;
}

export class MemorySessions {
  private readonly sessions = new Map<string, Session>();
  private readonly queues: boolean;
  private readonly retained: number;
  private readonly names: Record<string, string>;
  private readonly now: () => Date;
  private readonly maxUpload: number;
  private readonly files = new Map<string, MemoryFile>();

  constructor(options: MemoryOptions = {}) {
    this.queues = options.queues ?? true;
    this.retained = options.retained ?? 200;
    this.maxUpload = options.maxUpload ?? 50_000_000;
    this.names = options.names ?? {};
    this.now = options.now ?? (() => new Date());
  }
  /** Puts a file's bytes where an upload made room for them; false for a uri no upload made, or too many bytes. */
  putFile(uri: string, data: Uint8Array): boolean {
    const file = this.files.get(uri);
    if (!file || data.byteLength > file.size) {
      return false;
    }
    file.data = data;
    return true;
  }

  /** A file put after an upload; null until its bytes are there. */
  file(uri: string): MemoryFile | null {
    const file = this.files.get(uri);
    return file?.data ? file : null;
  }

  /** A new, empty session of `owner`'s. */
  create(id: string, owner: string): void {
    this.sessions.set(id, {
      owner,
      epoch: 1,
      count: 0,
      log: [],
      messages: new Map(),
      state: idleState,
      question: null,
      refs: new Map(),
      prompts: 0,
      questions: 0,
    });
  }

  has(id: string): boolean {
    return this.sessions.has(id);
  }

  /** Puts an update in the session, at the next cursor. Answers the cursor. */
  apply(id: string, update: SessionUpdate): string {
    const session = this.session(id);
    session.count += 1;
    const cursor = `${session.epoch}:${session.count}`;
    session.log.push({ cursor, update });
    const key = messageKey(update);
    if (key !== null) {
      session.messages.set(key, { cursor, update: patch(session.messages.get(key)?.update, update) });
    } else if (update.sessionUpdate === "state_update") {
      session.state = update;
    }
    return cursor;
  }

  /** The agent asks: the question opens, and the state turns `requires_action`. Answers the question's id. */
  ask(id: string, params: Omit<ElicitationCreateParams, "sessionId">): string {
    const session = this.session(id);
    session.questions += 1;
    const question = `q${session.questions}`;
    session.question = { id: question, params };
    this.apply(id, { sessionUpdate: "state_update", state: "requires_action", _meta: { agentchatkit: {} } });
    return question;
  }

  /** Every cursor handed out so far can no longer be resumed. */
  expire(id: string): void {
    this.session(id).epoch += 1;
  }

  /** The session's place now. */
  cursor(id: string): string {
    const session = this.session(id);
    return `${session.epoch}:${session.count}`;
  }

  /** The message as it stands. */
  message(id: string, messageId: string): SessionUpdate | undefined {
    return this.session(id).messages.get(messageId)?.update;
  }

  private session(id: string): Session {
    const session = this.sessions.get(id);
    if (!session) {
      throw new Error(`no session ${id}`);
    }
    return session;
  }

  private user(id: string, messageId: string): UserMessageUpdate | undefined {
    const held = this.message(id, messageId);
    return held?.sessionUpdate === "user_message" ? held : undefined;
  }

  private setUser(id: string, held: UserMessageUpdate, change: { content?: ContentBlock[]; status: MessageStatus }) {
    this.apply(id, {
      ...held,
      ...(change.content ? { content: change.content } : {}),
      _meta: { ...held._meta, agentchatkit: { ...ours(held), status: change.status } },
    });
  }

  /** The reference adapter over these sessions. */
  adapter(): Required<LiveAdapter<MemoryWho>> {
    const insert = (
      id: string,
      who: MemoryWho,
      content: ContentBlock[],
      status: MessageStatus,
      clientRef: string | null,
    ) => {
      const session = this.session(id);
      session.prompts += 1;
      const messageId = `u${session.prompts}`;
      const meta: AgentChatMeta = {
        at: this.now().toISOString(),
        sender: { login: who.login, name: who.name },
        status,
      };
      if (clientRef !== null) {
        meta.clientRef = clientRef;
        session.refs.set(clientRef, messageId);
      }
      this.apply(id, { sessionUpdate: "user_message", messageId, content, _meta: { agentchatkit: meta } });
      return messageId;
    };
    const stillHere = (id: string, messageId: string) => {
      const held = this.user(id, messageId);
      if (!held) {
        return refuse(404, "no such message");
      }
      const status = ours(held).status;
      if (status !== "pending" && status !== "queued" && status !== "failed") {
        return refuse(409, `the message is ${status ?? "not one sent here"}: it has gone`);
      }
      return held;
    };

    return {
      upload: async (_who, _id, file) => {
        if (!file.mimeType.startsWith("video/") && !file.mimeType.startsWith("image/")) {
          return refuse(415, "only pictures and videos");
        }
        if (file.size > this.maxUpload) {
          return refuse(413, `files up to ${Math.floor(this.maxUpload / 1_000_000)} MB`);
        }
        const uri = `files/${this.files.size + 1}-${encodeURIComponent(file.name)}`;
        this.files.set(uri, { mimeType: file.mimeType, size: file.size, data: null });
        return { uploadUrl: uri, uri };
      },

      authorize: async (request, id) => {
        const session = this.sessions.get(id);
        if (!session) {
          return refuse(404, "no such session");
        }
        const bearer = /^Bearer token-(.+)$/.exec(request.headers.get("Authorization") ?? "");
        if (!bearer?.[1]) {
          return refuse(401, "no bearer, or not one of ours");
        }
        if (bearer[1] !== session.owner) {
          return refuse(403, "not your session");
        }
        return { login: bearer[1], name: this.names[bearer[1]] ?? null };
      },

      read: async (_who, id, cursor): Promise<LiveRead> => {
        const session = this.session(id);
        const now = `${session.epoch}:${session.count}`;
        if (cursor === null) {
          const messages = [...session.messages.values()].slice(-this.retained);
          return { cursor: now, updates: messages, state: session.state, question: session.question };
        }
        const match = /^(\d+):(\d+)$/.exec(cursor);
        if (!match || Number(match[1]) !== session.epoch || Number(match[2]) > session.count) {
          return { expired: true };
        }
        return {
          cursor: now,
          updates: session.log.slice(Number(match[2])),
          state: session.state,
          question: session.question,
        };
      },

      prompt: async (who, id, body) => {
        const session = this.session(id);
        const known = body.clientRef === null ? undefined : session.refs.get(body.clientRef);
        if (known !== undefined) {
          return { messageId: known, repeat: true };
        }
        const queued = this.queues && !body.force && session.state.state === "running";
        return {
          messageId: insert(id, who, body.prompt, queued ? "queued" : "pending", body.clientRef),
          repeat: false,
        };
      },

      edit: async (_who, id, messageId, body) => {
        const held = stillHere(id, messageId);
        if ("refusal" in held) {
          return held;
        }
        // Force sends a queued message now, and retries a failed one: both become pending.
        const was = ours(held).status;
        const status = body.force && (was === "queued" || was === "failed") ? "pending" : (was as MessageStatus);
        this.setUser(id, held, { ...(body.prompt ? { content: body.prompt } : {}), status });
        return messageId;
      },

      remove: async (_who, id, messageId) => {
        const held = stillHere(id, messageId);
        if ("refusal" in held) {
          return held;
        }
        this.setUser(id, held, { status: "removed" });
        return messageId;
      },

      answer: async (who, id, question, answer: ElicitationAnswer) => {
        const session = this.session(id);
        const open = session.question;
        if (!open || open.id !== question) {
          return refuse(409, "that question is not open");
        }
        session.question = null;
        const properties = open.params.requestedSchema.properties;
        const schema = (properties.choice ?? (properties.choices as { items?: unknown } | undefined)?.items) as
          | { enum?: string[]; enumNames?: string[] }
          | undefined;
        const picked = answer.content?.choices ?? answer.content?.choice;
        const chosen = (Array.isArray(picked) ? picked : [picked]).filter((id): id is string => typeof id === "string");
        const label =
          chosen.length > 0
            ? chosen.map((id) => schema?.enumNames?.[schema.enum?.indexOf(id) ?? -1] ?? id).join(", ")
            : null;
        const words = typeof answer.content?.text === "string" ? answer.content.text : null;
        const text =
          answer.action === "accept" ? [label, words].filter((part) => part !== null).join(": ") : "(declined)";
        insert(id, who, [{ type: "text", text }], "pending", null);
        this.apply(id, { sessionUpdate: "state_update", state: "running", _meta: { agentchatkit: {} } });
      },
    };
  }
}
