# Live chats: our ACP v2 profile

How an app follows one agent chat as it changes, and writes to it: Agent Pager's coding threads, FeedbackKit's
feedback chats, any chat drawn with AgentChatKit. The wire is the [Agent Client Protocol](https://agentclientprotocol.com)
**v2** (draft, pinned below) over its [Streamable HTTP transport](https://agentclientprotocol.com/rfds/streamable-http-websocket-transport).
This page holds only what we choose, restrict or add; the spec holds the rest. Why ACP: [acp-fit.md](acp-fit.md).

Implemented by `server/` (TypeScript, Cloudflare Workers: the host is the ACP agent side) and `AgentChatLive` (Swift:
the client side), and checked by `protocol/fixtures/*.json`, which both test against.

Pinned: ACP v2 draft of 2026-07-20 ([schema](https://agentclientprotocol.com/protocol/v2/schema)) and
[`elicitation/create`](https://agentclientprotocol.com/protocol/v1/elicitation) (stable 2026-07-24). A spec change
we take is a new pin, in one commit with the fixtures.

## Roles

- **The host Worker is the ACP agent.** It relays: the agent behind it (Claude Code, Codex, a FeedbackKit runner) does
  not speak ACP to the app. The host turns its chat into `session/update`s and takes the app's writes.
- **A chat is a session.** `sessionId` is the host's chat id. Apps never call `session/new`; they `session/resume`.
  A host creates and lists chats outside ACP, with its own routes (FeedbackKit `POST` and `GET /v2/feedback`).
- **Several clients on one session** (the phone, the Mac, a coordinator) is normal: each has its own connection and
  stream; every `session/update` goes to all of them.

## Transport

- One endpoint the host mounts, `<base>/acp` (FeedbackKit `/v2/acp`, Agent Pager `/threads/acp`). HTTP/2.
- `Authorization: Bearer <token>` on every request, the host's own; its adapter checks it. A refused bearer: `401`;
  the client gets a new one from its host and tries once more.
- Follow a chat: `initialize` → open the session stream (`GET` with `Acp-Connection-Id`, `Acp-Session-Id`) →
  `session/resume`. Requests are `POST`, answered `202`; answers come on the stream.
- A `: keep-alive` SSE comment every 15 s. A client that hears nothing for 40 s, or whose stream ends, reconnects:
  1 s, 2 s, 4 s, 8 s, 15 s (±20 %), from 1 s again once a stream has stayed open 10 s. A connection id the server no
  longer knows: `404`, start again from `initialize`.
- The client follows only while the chat is on screen and the app is in front.

## Resume: snapshot or catch-up

Every `session/update` notification the host sends carries `params._meta.agentchatkit.cursor` (on the notification,
not the update, so it is never stored on a message), an opaque string. The client keeps the last one with what it
shows.

- **Catch-up:** `session/resume` with `replayFrom: {"type": "_cursor", "cursor": "<last>"}`. The host replays every
  update after it (exclusive), then the current `state_update`, then answers.
- **Snapshot:** no cursor held, or the host answers `-32602` to the cursor (too old, or another history): resume with
  `replayFrom: {"type": "start"}`. The host replays what it retains: at most the newest 200 messages, oldest first.
  The client **replaces** everything it holds with the replay.

## Messages

Each message is `user_message`, `agent_message` or a tool call (`tool_call_update`, first seen creates), upserted by
`messageId` / `toolCallId` with ACP's patch rules. `agent_message_chunk` may stream an answer's text. Our fields ride in
the update's `_meta.agentchatkit`:

| Key | On | |
|---|---|---|
| `at` | messages, tool calls | ISO 8601 UTC when written, or `null`; sets [display order](#display-order) |
| `sender` | `user_message` | `{login, name}`: a chat can have several people |
| `status` | `user_message` sent through a host | `pending`, `queued`, `delivering`, `delivered`, `failed`, `removed` (ticks: one, one, one, two, none, gone) |
| `clientRef` | `user_message` | the app's id for a message it sent; the idempotency key |
| `detail` | `user_message` | `failed`: why, in words for the person |
| `extra` | anything | the host's own fields (FeedbackKit `builderOnline`, Agent Pager `notes`), passed through |

A message typed elsewhere (in the agent's own terminal) has no `status` and no ticks. A host sets only the statuses it
has: FeedbackKit never queues (`pending`, `delivering`, `delivered`, `failed`, `removed`).

**Attachments** are content blocks. From the host: `resource_link` (`uri`, `mimeType`, `size`), with
`_meta.agentchatkit` `{width, height, durationMs}`; `uri` is absolute and signed, or relative to `<base>/acp` and
fetched with the same bearer. From the app: `image` with base64 `data` (up to four, `MessageImage`), or for anything
larger (video) a `resource_link` to a URL the host minted for the upload. A client skips a `mimeType` it can't draw.

### Display order

By `at`, not arrival: an agent's message often arrives after a later one of the person's. A message without `at`
sorts at the `at` of the message before it when first taken; equal `at` keeps the order taken; a replay from start
is in the host's order.

## State

`state_update` (`running`, `idle`, `requires_action`; `idle` with its `stopReason`). Ours in `_meta.agentchatkit`:
`activity` (what it is doing now, in a few words) and `problem` (why it stopped short). Model and reasoning are
session config options (`config_option_update`), as `ModelReasoningChip` shows them.

## Writes

| Method | Params | Answer |
|---|---|---|
| `session/prompt` | `prompt` (text and attachment blocks); `_meta.agentchatkit`: `clientRef`, `force` | `messageId`, at once |
| `_agentchatkit/edit` | `sessionId`, `messageId`, any of `prompt`, `force` | the `messageId` |
| `_agentchatkit/remove` | `sessionId`, `messageId` | the `messageId` |

- **The host inserts every prompt at once** (ACP allows it): the `user_message` comes on the stream with `status`
  `pending` or `queued`, and `session/prompt` answers its `messageId`. Passing it to the agent is the host's business,
  reported by `status`. A repeat `clientRef` answers the first `messageId` and sends nothing new.
- `force: true` asks for it to go now instead of after the agent's turn. The default is the person's choice, `false`.
  A host that never queues ignores it.
- **Send now** a queued message: `_agentchatkit/edit` with `force: true` alone. It turns `queued` into `pending` and
  goes to the agent at once (Jai uses this daily).
- **Edit or force, or remove,** a message still `pending` or `queued`; otherwise error `-32009` (`conflict`).
  Each change comes on the stream as a `user_message` update; a removed one has `status: removed`.

## Questions

The agent asks with [`elicitation/create`](https://agentclientprotocol.com/protocol/v1/elicitation), form mode,
session scope. Clients advertise `elicitation: {form: {}}`.

- `requestedSchema`: `choice` (string `enum`, its labels in `enumNames`) or `choices` (array of that enum, for
  several), and `text` (string) when free text is allowed. The person answers `accept` with `content`, or `decline`.
- While it is open, `state_update` is `requires_action`. An answer always goes now: it never queues.
- **Several clients:** the host sends the request to every connection, and again after a resume while it is open.
  The first answer wins; the host sends `$/cancel_request` for it to the others.
- The host shows the answer as a `user_message` like any other.

## Host adapter

What a host Worker writes; the package does `/acp`, JSON-RPC, connections, the room Durable Object, replay,
broadcast and keep-alive.

```ts
interface LiveAdapter<Who> {
  /** Checks the bearer and the session: who asks, or a refusal (401, 403, 404). */
  authorize(request: Request, sessionId: string): Promise<Who | LiveRefusal>;
  /** Updates after `cursor`, oldest first, each with its cursor; `cursor` null: the retained history.
   *  A cursor it cannot resume from: `{expired: true}`. Includes the current state and any open question. */
  read(who: Who, sessionId: string, cursor: string | null): Promise<LiveRead>;
  prompt?(who: Who, sessionId: string, prompt: PromptBody): Promise<{messageId: string, repeat: boolean} | LiveRefusal>;
  edit?(who: Who, sessionId: string, messageId: string, body: EditBody): Promise<string | LiveRefusal>;
  remove?(who: Who, sessionId: string, messageId: string): Promise<string | LiveRefusal>;
  answer?(who: Who, sessionId: string, question: string, answer: ElicitationAnswer): Promise<void | LiveRefusal>;
}
```

- A chat that changes other than through these: the host calls `notifyChat(namespace, sessionId)`; the room reads
  after the last cursor it sent and broadcasts. A write notifies the room itself.
- `refreshEvery` (ms, off by default): the room also reads on that tick while it has streams, for changes no write
  makes (FeedbackKit's stuck-delivery `problem`, its `builderOnline`).
- **FeedbackKit**: cursor = the chat's change counter; state changes counted by a conditional update in `read`.
- **Agent Pager**: while a room has streams, it holds one hub stream and notifies itself; cursor = the hub's.

## To measure

Reconnect costs four requests (`initialize`, the stream, `session/resume`, its replay) where a plain SSE stream costs
one. AgentChatLive logs each step's time; Agent Pager reports them from phones. If it is slow, we add one extension
method that initializes and resumes together.

## Fixtures

`protocol/generate.py` writes them; change it, run it, commit both. The server's conformance suite and the Swift
tests read the same files.

| Fixture | Covers |
|---|---|
| `messages.json` | each update and request we use, as JSON-RPC, with our `_meta` |
| `resume-start.json` | no cursor: replay from start, then live updates |
| `resume-cursor.json` | a cursor: only what came after it |
| `resume-expired.json` | `-32602`, then replay from start replaces everything |
| `display-order.json` | by `at`, not arrival; no `at`; ties |
| `prompt-lifecycle.json` | queued, edited, sent now (force), delivered; removed; a repeat `clientRef` |
| `question.json` | `elicitation/create` to two clients, one answers, the other is cancelled |
| `transport.json` | statuses, back-off, keep-alive, what the client does |
