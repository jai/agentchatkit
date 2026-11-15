# Live chat protocol, v1

How an app follows one agent chat as it changes: Agent Pager's coding threads, FeedbackKit's feedback chats, and any
other chat drawn with AgentChatKit. Defined here once; implemented by `server/` (TypeScript, Cloudflare Workers),
`AgentChatLive` (Swift), and checked by `protocol/fixtures/*.json`, which both sides test against.

Status: v1, 2026-11-15, cut down after adversarial reviews (Codex, Claude) and a check against SSE, AG-UI, Durable
Streams, the Cloudflare Agents SDK, Linear and MCP. None of those fits wholesale; this is plain SSE with three events.

## In short

- One stream per open chat: `GET <chat>/live/v1`, Server-Sent Events, with the host's bearer.
- Every event has an SSE `id:`. On reconnect the client sends it back as `Last-Event-ID`. No `Last-Event-ID`, or one
  the host can no longer resume from: the stream starts with a `snapshot`.
- Then one event per new or changed message, and one per change of the chat's state. The client replaces by id.
- Writes are plain requests: send, edit, remove.
- Reconnect with back-off is the only fallback. There is no second read route and no polling.

## The stream

`GET <chat>/live/v1`, `Accept: text/event-stream`, `Authorization: Bearer <token>`, optional `Last-Event-ID`.

The host chooses `<chat>` (`/v2/feedback/{id}`, `/threads/{host}/{thread_id}/conversation`). Auth is the host's: its
adapter checks the bearer; the package never reads it.

```
retry: 1000
id: c:42
event: message
data: {"message":{"id":"m7","role":"assistant","text":"Done.","at":"2026-11-15T05:01:02.000Z"}}

: keep-alive
```

| `event` | `data` | When |
|---|---|---|
| `snapshot` | `{"messages": [Message], "state": State}` | first, unless the stream resumes |
| `message` | `{"message": Message}` | a message was added or changed |
| `state` | `{"state": State}` | the chat's state changed |

- `id:` on every event: an opaque string the host makes. The client keeps the last one it saw and never parses it.
- `data` is one line of JSON. A line stream drops blank lines, so a client may act on each `data:` line.
- A `: …` comment every 15 s keeps the connection and its proxies awake. A client that hears nothing for 40 s
  reconnects.
- `retry:` (ms) is the server's preferred reconnect delay. The client uses it as its first back-off step.
- The server may end the response at any time (a deploy, a long-lived stream). The client reconnects.
- A client ignores event types and fields it does not know.

### Resuming

- With a `Last-Event-ID` the host can resume from: every change after it, oldest first, then live changes. Nothing
  before it comes again; nothing after it is skipped.
- Without one, or one too old or from another history: `snapshot` first. It holds the newest 200 messages, oldest
  first, and the state; the client **replaces** everything it holds with it.

### Status codes

| Status | Means | The client |
|---|---|---|
| 200 | the stream | follows it |
| 204 | the chat has ended, or offers no live stream | stops |
| 401 | no bearer, or it does not verify | gets a new bearer from its host, tries once more; 401 again: stops |
| 403, 404 | not this person's chat; no such chat | stops |
| 5xx, a network error, the stream ends | | reconnects after `retry` (1 s when none came), then 2 s, 4 s, 8 s, 15 s (±20 %); from the first step again once a stream has stayed open 10 s |

A host may serve live for some chats only (FeedbackKit's public-issue chats): the others answer `404`, and the app
keeps the host's own read.

The client follows only while the chat is on screen and the app is in front, and keeps the last event id with what it
shows, so the next open resumes.

## Items

Any item may carry `extra`: a JSON object the host defines (FeedbackKit's `builderOnline`, Agent Pager's `notes`),
passed through untouched.

### Message

```json
{"id": "m6", "role": "user", "text": "Merge it.", "at": "2026-11-15T05:01:02.000Z",
 "sender": {"login": "jai", "name": "Jai"}, "status": "delivered", "client_ref": "B3F1", "detail": null,
 "attachments": [{"id": "a1", "url": "attachments/a1?sig=abc", "media_type": "image/jpeg", "width": 1179, "height": 2556}],
 "tool": null, "extra": {}}
```

| Field | | |
|---|---|---|
| `id` | string | stable for the life of the chat; a later version replaces it |
| `role` | `user`, `assistant`, `tool` | the person's words, the agent's, a tool call |
| `text` | string | Markdown for `assistant`; as typed for `user`; a one-line summary for `tool` |
| `at` | ISO 8601 UTC or `null` | when it was written |
| `tool` | string or `null` | a `tool` message: the tool's name |
| `sender` | `{login, name}` or `null` | a `user` message: who wrote it. A chat can have several people |
| `status` | see below, or `null` | a `user` message the person sent through a host: how far it got |
| `client_ref` | string or `null` | the app's own id for a message it sent: how it finds its bubble |
| `detail` | string or `null` | `failed`: why, in words for the person |
| `attachments` | [Attachment], default `[]` | |

`status`, and the ticks `DeliveryTicks` draws:

| `status` | Means | Ticks |
|---|---|---|
| `pending` | the host has it | one |
| `queued` | it waits for the agent's turn to end; it can still be edited or removed | one |
| `delivering` | it is being passed to the agent | one |
| `delivered` | the agent has it | two |
| `failed` | not passed on; `detail` says why | none |
| `removed` | taken back before it went | the bubble goes |

A message typed elsewhere (in the agent's own terminal) has `status: null` and no ticks.

**Attachment**: `{"id", "url", "media_type", "width", "height", "duration_ms"}`. The host makes `url`: an absolute
signed URL, or a path relative to `<chat>/live/v1/` fetched with the same bearer; the package never serves bytes.
`width`, `height` (pixels) and `duration_ms` (video, audio) may be `null`. A client skips a `media_type` it cannot draw.

### State

```json
{"working": false, "activity": null, "problem": null, "model": "claude-opus-5-5", "effort": "high",
 "elicitation": {"id": "q1", "message": "Merge now or wait for review?",
                 "options": [{"id": "merge", "label": "Merge now"}, {"id": "wait", "label": "Wait for review"}],
                 "multiple": false, "free_text": true},
 "extra": {}}
```

| Field | | |
|---|---|---|
| `working` | bool | the agent is on a turn |
| `activity` | string or `null` | what it is doing now, in a few words |
| `problem` | string or `null` | why it stopped short of an answer |
| `model`, `effort` | string or `null` | as `ModelReasoningChip` shows them |
| `elicitation` | Elicitation or `null` | the agent waits on the person: its open question. A client may call this `awaitingInput` |

**Elicitation**: `{"id", "message", "options": [{"id", "label"}], "multiple", "free_text"}`. `options` may be empty.

## Display order

Messages show in order of `at`, not of arrival: an agent's message often arrives after a later one of the person's.
A message without `at` sorts at the `at` of the message before it when it was first taken. Equal `at` keeps the
order taken. A snapshot's order is the server's.

## Writes

Each with the bearer. Each answers the Message it made or changed; the same change reaches every open stream as a
`message` event, and the client replaces by id, so it never shows twice.

| Request | Body | Answer |
|---|---|---|
| `POST <chat>/live/v1/messages` | `{"text", "client_ref", "force", "attachments", "elicitation_id", "option_ids"}` | `201` Message; `200` the same Message for a repeat `client_ref` |
| `PATCH <chat>/live/v1/messages/{id}` | any of `{"text", "attachments", "force"}` | `200` Message |
| `DELETE <chat>/live/v1/messages/{id}` | | `200` Message, `status: removed` |

- **Send.** `client_ref` is the idempotency key. Text, attachments, or both; neither: `400`. `force: true` asks for it
  to go now instead of after the agent's turn; the default is the person's choice, `false`.
- **Answer the elicitation** with a send carrying `elicitation_id` (and `option_ids`, `text`, as it allows). It always
  goes now: the agent waits on it. The next `state` has `elicitation: null`. A question no longer open: `409`.
- **Edit or force** a message still `pending` or `queued`: `PATCH`. Otherwise `409`.
- **Remove** a message still `pending` or `queued`: `DELETE`. Otherwise `409`.
- **Attachments in a write**: an image inline as `{"media_type", "data"}`, base64, up to four (`MessageImage`).
  Anything larger (video) is uploaded first to a URL the host mints, then sent as `{"media_type", "url"}`. Never
  video as base64.
- Refusals: `400`, `401`, `403`, `404`, `409`, each `{"error", "message"}`.

## Host adapter

What a host Worker writes; the package does the routes, events, room Durable Object, broadcast and keep-alive.

```ts
interface LiveAdapter<Who> {
  /** Checks the bearer and the chat: who asks, or a refusal (401, 403, 404, 204). */
  authorize(request: Request, chat: string): Promise<Who | LiveRefusal>;
  /** Changes after `cursor`, oldest first, each with its cursor; or `reset` with a snapshot. */
  read(who: Who, chat: string, cursor: string | null): Promise<LiveRead>;
  /** The writes; a host without one answers 404. */
  send?(who: Who, chat: string, body: SendBody): Promise<{message: Message, repeat: boolean} | LiveRefusal>;
  edit?(who: Who, chat: string, id: string, body: EditBody): Promise<Message | LiveRefusal>;
  remove?(who: Who, chat: string, id: string): Promise<Message | LiveRefusal>;
}
```

- When a chat changes other than through these writes, the host calls `notifyChat(namespace, chat)`. The room reads
  after the last cursor it sent and broadcasts. A write notifies the room itself.
- `refreshEvery` (ms, off by default): the room also reads on that tick while it has streams, for changes no write
  makes (FeedbackKit's stuck-delivery `problem`, its `builderOnline`).
- **FeedbackKit**: cursor = the chat's change counter; a state change gets its counter from a conditional update in
  `read`.
- **Agent Pager**: while a room has streams, it holds one hub stream and notifies itself; cursor = the hub's.

## Conformance

`server/` exports a suite that runs the fixtures against a host's adapter. Each backend runs it in its own CI and
tests only its adapter. The Swift client runs the same fixtures. `protocol/generate.py` writes them: change it, run
it, commit both.

| Fixture | Covers |
|---|---|
| `events.json` | each event as SSE text and JSON; a comment, `retry:`, an unknown event and field |
| `connect-fresh.json` | no `Last-Event-ID`: snapshot, then live changes |
| `resume.json` | `Last-Event-ID`: only what came after it |
| `resume-expired.json` | an id the host can't resume from: snapshot |
| `snapshot-reset.json` | a snapshot replaces everything held |
| `display-order.json` | by `at`, not arrival; no `at`; ties |
| `message-lifecycle.json` | queued, edited, forced, delivered; removed |
| `writes.json` | send, repeat, answer, edit, remove: each answer, its events, refusals |
| `statuses.json` | each status code and what the client does; the back-off |

## Versioning

The path carries the version: `live/v1`. A change an old client or server can ignore (a new optional field, a new
`extra` key, a new event type) stays v1. Anything else is `live/v2`, served beside v1 until the apps have moved.
