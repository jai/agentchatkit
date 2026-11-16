/**
 * What a host Worker writes: its adapter (docs/live-protocol.md#host-adapter). The package does `/acp`, JSON-RPC,
 * connections, the room Durable Object, replay, broadcast and keep-alive.
 */
import type { ContentBlock, ElicitationCreateParams, ElicitationResult, SessionUpdate, StateUpdate } from "./acp.ts";

/**
 * A refusal. From `authorize`: the HTTP status (401, 403, 404). From a write: 400 and 404 answer `-32602`, 409
 * answers `-32009` (`conflict`: the message is no longer `pending` or `queued`).
 */
export interface LiveRefusal {
  refusal: { status: 400 | 401 | 403 | 404 | 409; message: string };
}

export function refuse(status: LiveRefusal["refusal"]["status"], message: string): LiveRefusal {
  return { refusal: { status, message } };
}

export function isRefusal(value: unknown): value is LiveRefusal {
  return typeof value === "object" && value !== null && "refusal" in value;
}

/** One update and the cursor that resumes just after it. */
export interface CursoredUpdate {
  cursor: string;
  update: SessionUpdate;
}

/** The agent's open question: the host's id for it, and what `elicitation/create` asks. */
export interface OpenQuestion {
  id: string;
  params: Omit<ElicitationCreateParams, "sessionId">;
}

/**
 * What `read` answers.
 *
 * - `{expired: true}`: a cursor the host cannot resume from (too old, or another history).
 * - Otherwise `updates`: after `cursor`, oldest first, each with its cursor (a host may coalesce several versions
 *   of one message into its latest); with `cursor` null, the retained history (at most the newest 200 messages).
 *   `cursor` is the session's place now. `state` is its current state, `question` its open question, if any.
 */
export type LiveRead =
  | { expired: true }
  | {
      expired?: false;
      cursor: string;
      updates: CursoredUpdate[];
      state: StateUpdate;
      question: OpenQuestion | null;
    };

/** A `session/prompt`, as the host gets it. */
export interface PromptBody {
  prompt: ContentBlock[];
  /** The app's id for it, and the idempotency key: a repeat answers the first `messageId`. */
  clientRef: string | null;
  /** Go now instead of after the agent's turn. A host that never queues ignores it. */
  force: boolean;
}

/** An `_agentchatkit/edit`: new blocks, `force`, or both. */
export interface EditBody {
  prompt?: ContentBlock[];
  force?: boolean;
}

export type ElicitationAnswer = ElicitationResult;

/**
 * A host's adapter. `Who` is whoever `authorize` says asks; it must survive `JSON.stringify`, since it travels
 * from the Worker to the session's room in a header.
 */
export interface LiveAdapter<Who> {
  /** Checks the bearer and the session: who asks, or a refusal (401, 403, 404). */
  authorize(request: Request, sessionId: string): Promise<Who | LiveRefusal>;
  /** The session after `cursor` (null: from start). See `LiveRead`. */
  read(who: Who, sessionId: string, cursor: string | null): Promise<LiveRead>;
  /** Inserts the prompt at once as a `user_message` (`pending` or `queued`). A repeat `clientRef`: `repeat: true`. */
  prompt?(
    who: Who,
    sessionId: string,
    prompt: PromptBody,
  ): Promise<{ messageId: string; repeat: boolean } | LiveRefusal>;
  /** Edits or forces a message still `pending` or `queued`; else refuse 409. Answers the `messageId`. */
  edit?(who: Who, sessionId: string, messageId: string, body: EditBody): Promise<string | LiveRefusal>;
  /** Removes a message still `pending` or `queued` (its status becomes `removed`); else refuse 409. */
  remove?(who: Who, sessionId: string, messageId: string): Promise<string | LiveRefusal>;
  /** The first answer to the open question `question`. The host shows it as a `user_message`. */
  answer?(who: Who, sessionId: string, question: string, answer: ElicitationAnswer): Promise<void | LiveRefusal>;
}
