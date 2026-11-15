# Live chat protocol, v1

How an app follows one agent chat as it changes: Agent Pager's coding threads, FeedbackKit's feedback chats, and any
other chat drawn with AgentChatKit. It is defined here once. Three parts implement it:

- `server/` (TypeScript, Cloudflare Workers): the room Durable Object, frame encoding, cursors and broadcast. A host
  Worker gives a small adapter ([Host adapter](#host-adapter)).
- `AgentChatLive` (Swift): follows a chat and holds its state for the AgentChatKit views.
- `protocol/fixtures/*.json`: every frame and edge case. The server's conformance suite and the Swift tests both read
  them. When this document and a fixture disagree, fix one of them in the same commit.

Status: draft for review, 2026-11-15. Nothing implements it yet.

## Summary

1. The app opens a stream: `GET <chat>/live?v=1&after=<cursor>`, Server-Sent Events, with the host's bearer.
2. With no cursor, or a cursor the server can no longer resume from, the first frame after `hello` is a `snapshot`.
3. After that, the server sends one frame per change: a new or changed message, a reply's status, the chat's state.
   Each carries the chat's new `cursor` and `seq`.
4. While the stream is down, the app reads `GET <chat>/live/read?v=1&after=<cursor>` every 2 s. The read answers the
   same frames, so the app applies them the same way.
5. The app keeps one cursor, takes each item once by its id and `seq`, and reconnects with back-off.
6. The app writes with four requests: send, force a queued reply, remove a queued reply, answer the agent's question.
   Each change it makes reaches every open stream as frames.

## Why Server-Sent Events

- DurableNetworking, the one network stack for the apps, has `StreamingTransport` (lines of a long response). It has
  no WebSocket. SSE needs nothing new in it.
- Agent Pager's hub and Worker already stream threads as SSE, through a Cloudflare Tunnel.
- The app sends nothing on the stream. It writes with plain requests ([Writes](#writes)), through its outbox.

The cost: a Durable Object that holds an open SSE response stays awake, where a hibernating WebSocket sleeps. A
stream is open only while a chat is on screen and the app is in front, and it ends after 10 minutes
([close codes](#close)). FeedbackKit's WebSocket room (`GET /v2/feedback/{id}/live`) goes when it adopts the package.

## Terms

- **Chat**: one conversation. The host names it with an id it chooses (`chat` below).
- **Item**: one thing in a chat that has an id: a message, a reply, or the chat's state (one per chat).
- **seq**: an integer. It increases with every change in a chat. Each item carries the `seq` of its latest change. Each
  frame that changes something carries the chat's `seq` after the change.
- **cursor**: an opaque string. It names a place in the chat's history. The client only stores it and sends it back.
  A host can put more than a number in it (a file's identity, an epoch), so it can tell a cursor it can no longer
  resume from.

`seq` orders. `cursor` resumes. They always travel together.

## Requests

The host chooses where a chat lives (`<chat>`), for example `/v2/feedback/{id}` or
`/threads/{host}/{thread_id}/conversation`. Under it, two routes:

| Route | Answer |
|---|---|
| `GET <chat>/live?v=1&after=<cursor>` | `200 text/event-stream`: frames, until a `close` frame or the connection drops |
| `GET <chat>/live/read?v=1&after=<cursor>&limit=<n>` | `200 application/json`: `{"v": 1, "frames": [Frame]}` |
| `GET <chat>/live/read?v=1&before=<message id>&limit=<n>` | `200 application/json`: `{"v": 1, "frames": [Earlier]}` |
| `POST`, `DELETE` `<chat>/live/…` | the writes: [Writes](#writes) |

- `v` is required and is `1`. Another value: `400 unsupported_version`.
- `after` is optional. Without it, the server starts with a `snapshot`. On the stream, a `Last-Event-ID` header is
  taken as `after` when `after` is absent (a browser's `EventSource` sends it on reconnect).
- `limit` is 1–200, default 100: how many messages a `snapshot` or an `earlier` frame holds at most (the newest
  ones). `after` and `before` together: `400 bad_request`.
- **Auth is the host's.** Every request carries `Authorization: Bearer <token>`. The host's adapter checks it and
  says whose chat this is. The package never reads the token.

### Refusals

Before the stream starts, a refusal is a plain HTTP answer with `{"error": <code>, "message": <words>}`:

| Status | `error` | When | The client |
|---|---|---|---|
| 400 | `bad_request`, `unsupported_version` | bad query, a cursor that is not one, `v` not 1 | stops; a bug |
| 401 | `unauthorized` | no bearer, or it does not verify or has expired | gets a new bearer from its host, tries once more |
| 403 | `forbidden` | not this person's chat | stops |
| 404 | `not_found` | no such chat | stops |
| 429 | `busy` | too many streams open on this chat (the host sets the limit) | reads every 2 s; tries the stream again after `Retry-After` seconds |
| 5xx | `internal` | the server failed | reads; reconnects with back-off |

A cursor the server can no longer resume from is not a refusal: the stream (or read) starts with a `snapshot`.

A host may serve live for some chats only (FeedbackKit's public-issue chats have no change source). Those answer
`404` to both routes, and the app keeps the host's own read.

## Frames

On the stream, each frame is one SSE event. `event` is the frame's `type`, `data` is the frame as one line of JSON,
and `id` is the frame's `cursor` when it has one:

```
event: message
id: c:42
data: {"type":"message","cursor":"c:42","seq":42,"message":{"id":"m7","seq":42,"role":"assistant","text":"Done."}}

```

In a read, the same frames are the `frames` array. `type` is always in the JSON, so a frame stands alone in a fixture.

| `type` | Fields | When |
|---|---|---|
| `hello` | `v`, `chat`, `cursor`, `seq`, `resumed` | first on every stream |
| `snapshot` | `cursor`, `seq`, `messages`, `replies`, `state`, `more_before` | no cursor, or one that can't be resumed |
| `message` | `cursor`, `seq`, `message` | a message was added or changed |
| `reply` | `cursor`, `seq`, `reply` | one of the person's replies changed status |
| `state` | `cursor`, `seq`, `state` | the chat's state changed |
| `ping` | | every 15 s |
| `close` | `code`, `reason`, `retry_after_ms` | last, when the server ends the stream |
| `earlier` | `messages`, `more_before` | a read with `before`, only |

### hello

`{"type": "hello", "v": 1, "chat": "<id>", "cursor": "...", "seq": 41, "resumed": true}`

- `resumed: true`: the server can resume from `after`. Frames after `after` follow (possibly none).
- `resumed: false`: a `snapshot` follows at once.
- `cursor` and `seq` are the chat's place now. A resumed client does not take them from `hello`: it waits for the
  frames, so nothing between its cursor and now is skipped.

### snapshot

`{"type": "snapshot", "cursor", "seq", "messages": [Message], "replies": [Reply], "state": State, "more_before": bool}`

- The chat as it stands: the newest `limit` messages, oldest first; the replies not yet `delivered` or ended within
  the last hour; the state.
- The client **replaces** everything it holds with it, cursor and `seq` too, even when `seq` is lower than the one
  it holds (the host reset its history).
- `more_before`: older messages exist; a read with `before` fetches them.

### message

`{"type": "message", "cursor", "seq", "message": Message}`

A new message, or a new version of one: same `id`, higher `seq`. The client replaces a held message by `id`.
Where it shows: [Display order](#display-order).

### reply

`{"type": "reply", "cursor", "seq", "reply": Reply}`

One of the person's replies (messages they sent) moved on: queued, delivering, delivered, failed. When a reply
becomes a message in the chat, the message carries `reply_id` and the reply carries `message_id`.

A host whose person's messages are in the chat from the start (FeedbackKit) sends each as both: a `user` Message
with `reply_id` set to its own id, and a Reply with the same id, `message_id` set at once, carrying its status. The
bubble draws the Message; its ticks come from the Reply. Message and Reply ids are separate spaces.

### state

`{"type": "state", "cursor", "seq", "state": State}`

The whole state, replacing the held one.

### ping

`{"type": "ping"}` every 15 s while the stream is open. No cursor. It proves the connection is alive: the client drops
a stream that is silent for 40 s and reconnects. SSE runs one way, so there is no pong; the client's liveness is its
open connection.

### close

`{"type": "close", "code": 4000, "reason": "rotate", "retry_after_ms": 0}`

The server's last frame when it ends a stream itself. A stream that ends without one dropped: reconnect with
back-off.

| `code` | `reason` | Means | The client |
|---|---|---|---|
| 4000 | `rotate` | the stream reached 10 minutes | reconnects at once with its cursor |
| 4001 | `unauthorized` | the bearer was revoked while open (optional: a host may keep a stream whose bearer only expired) | new bearer, then reconnects |
| 4003 | `forbidden` | no longer this person's chat | stops |
| 4004 | `gone` | the chat was closed or deleted | stops following; one read shows the end |
| 4029 | `busy` | the host is shedding streams | reads every 2 s; reconnects after `retry_after_ms` |
| 4500 | `internal` | the server failed | reads; reconnects with back-off |
| 4503 | `restarting` | a deploy is moving the room | reconnects after `retry_after_ms` (≤ 5 s), no back-off |

The numbers follow WebSocket's private range (4000–4999), so a WebSocket binding of this protocol could keep them.

### earlier

`{"type": "earlier", "messages": [Message], "more_before": bool}`: the `limit` messages just before `before`, oldest
first. It has no cursor and changes neither the client's cursor nor its `seq`: the client puts them in front of
what it holds, each once by `id`.

## Items

Every item may carry `extra`: a JSON object the host defines (FeedbackKit's `builderOnline`, Agent Pager's `notes`).
The package passes it through untouched; the Swift client hands it to the host as JSON.

### Message

```json
{"id": "m6", "seq": 40, "role": "user", "text": "Merge it.", "at": "2026-11-15T05:01:02.000Z",
 "tool": null, "partial": false, "reply_id": "rpl_1", "sender": {"login": "jai", "name": "Jai"},
 "images": [{"id": "img1", "url": "images/img1?sig=abc", "media_type": "image/jpeg", "width": 1179, "height": 2556}],
 "extra": {}}
```

| Field | Type | |
|---|---|---|
| `id` | string | stable for the life of the chat |
| `seq` | integer | the `seq` of this version |
| `role` | `user`, `assistant`, `tool` | the person's words, the agent's words, a tool call |
| `text` | string | Markdown for `assistant`; as typed for `user`; a one-line summary for `tool` |
| `at` | ISO 8601 UTC or `null` | when it was written |
| `tool` | string or `null` | a `tool` message: the tool's name |
| `partial` | bool, default `false` | the text so far of a message still being written; a later version replaces it |
| `reply_id` | string or `null` | a `user` message that is one of the person's replies: that reply's `id` |
| `sender` | Sender or `null` | a `user` message: who wrote it. A chat can have several people (FeedbackKit's owner and builder) |
| `images` | [Image], default `[]` | the screenshots it carried |
| `extra` | object, optional | the host's |

FeedbackKit's `you` and `agent` are `user` and `assistant`.

**Sender**: `{"login": string, "name": string or null}`. `login` is the host's stable id for the person (FeedbackKit:
the GitHub login); `name` is how the app names them.

**Image**: `{"id", "url", "media_type", "width", "height"}`.
- `url` is where the app fetches the bytes. The host makes it and authorizes it: an absolute signed URL, or a path
  relative to `<chat>/live/` that the app fetches with the same bearer. The package never serves image bytes.
- `width` and `height` are pixels, so the strip lays out before the bytes arrive. `null` when the host does not know.

### Reply

```json
{"id": "rpl_01", "seq": 40, "client_ref": "B3F1", "status": "delivered", "text": "Merge it.",
 "at": "2026-11-15T05:00:00.000Z", "detail": null, "message_id": "m6", "extra": {}}
```

| Field | Type | |
|---|---|---|
| `id` | string | the host's id for the reply |
| `seq` | integer | the `seq` of this version |
| `client_ref` | string or `null` | the app's own id for it, as it sent it: how the app finds its bubble before the server's id is known |
| `status` | `pending`, `queued`, `delivering`, `delivered`, `failed`, `removed` | |
| `text` | string | as sent |
| `at` | ISO 8601 UTC | when the host took it |
| `detail` | string or `null` | `failed`: why, in words for the person |
| `message_id` | string or `null` | the chat message it became, once it did |
| `sender` | Sender or `null` | who sent it |
| `images` | [Image], default `[]` | the screenshots it carries |
| `extra` | object, optional | the host's |

Statuses, and the ticks `DeliveryTicks` draws:

| `status` | Means | Ticks |
|---|---|---|
| `pending` | the host has it | one |
| `queued` | it waits for the agent's turn to end | one |
| `delivering` | it is being passed to the agent | one |
| `delivered` | the agent has it | two |
| `failed` | it was not passed on; `detail` says why | none |
| `removed` | the person took it back before it went | the bubble goes |

### State

```json
{"seq": 43, "working": false, "activity": null, "problem": null, "model": "claude-opus-5-5", "effort": "high",
 "waiting": {"id": "q1", "question": "Merge now or wait for review?",
             "options": [{"id": "merge", "label": "Merge now"}, {"id": "wait", "label": "Wait for review"}],
             "multiple": false, "free_text": true},
 "extra": {}}
```

| Field | Type | |
|---|---|---|
| `seq` | integer | the `seq` of this version |
| `working` | bool | the agent is on a turn |
| `activity` | string or `null` | what it is doing now, in a few words |
| `problem` | string or `null` | why it stopped short of an answer |
| `model`, `effort` | string or `null` | the chat's model and reasoning, as `ModelReasoningChip` shows them |
| `waiting` | Question or `null` | the agent waits on the person: its open question (Orca's question card) |
| `extra` | object, optional | the host's |

**Question**: `{"id", "question", "options": [{"id", "label"}], "multiple": bool, "free_text": bool}`. `options` may be
empty (an open question). `multiple`: more than one option may be chosen. `free_text`: words may be sent instead of,
or with, options. When the person answers, `waiting` becomes `null` in the next `state`.

## Writes

The app's four writes. Each carries the bearer and `v=1` in the query. Each answers the Reply it made or changed. The
change also reaches every open stream on the chat as frames, the writer's own included; the app takes the frames
like any other, by `seq`, so the answer and the frame never show a reply twice.

| Request | Body | Answer | Frames |
|---|---|---|---|
| `POST <chat>/live/messages` | `{"text", "client_ref", "force": bool, "images": [{"media_type", "data"}]}` | `201` Reply; `200` the same Reply for a repeat `client_ref` | `reply` (a repeat: none) |
| `POST <chat>/live/replies/{id}/force` | none | `200` Reply | `reply` |
| `DELETE <chat>/live/replies/{id}` | none | `200` Reply, `status: removed` | `reply` |
| `POST <chat>/live/answer` | `{"question_id", "option_ids": [string], "text": string or null, "client_ref"}` | `201` Reply | `reply`, then `state` with `waiting: null` |

- **send**: `client_ref` is the app's id for the message and its idempotency key: a repeat lands once. `images` are
  up to four JPEG or PNG, base64 (`MessageImage`). `force: false` lets the host queue it behind the agent's turn;
  `force: true` asks it to go now. Neither text nor images: `400 bad_request`.
- **force**: a queued reply goes now. Not queued: `409 conflict`.
- **remove**: a reply not yet passed on is taken back. Already `delivering` or `delivered`: `409 conflict`.
- **answer**: answers `waiting`. The answer is a reply like any other: it becomes a `user` message when delivered.
  A question that is not open (answered, or another id): `409 conflict`.
- **Force by default while the chat waits on the person.** When the held `state.waiting` is not null, the client
  sends with `force: true`: the agent's turn will not end until it is answered, so a queued reply would wait for
  good. The person can still choose to queue.
- Refusals are the same as the reads' (`400`, `401`, `403`, `404`), plus `409 conflict`, each
  `{"error", "message"}`.

## Display order

`seq` decides which version of an item wins. It does not decide where a message shows:

- Messages show in order of `at`, oldest first. An agent's message often arrives after a later one of the person's
  (a transcript is read late); its earlier `at` puts it before.
- A message without `at` sorts at the `at` of the message before it when it was first taken: it stays where it
  arrived.
- Equal `at` keeps the order taken. A snapshot's and an earlier frame's order is the server's.

Fixture: `display-order.json`.

## The client's rules

One cursor, one `seq`, from whichever source last moved them.

1. **Take a frame** (from the stream or a read):
   - `snapshot`: replace everything, cursor and `seq` included.
   - `message`, `reply`, `state`: apply the item only if its `seq` is higher than the `seq` of the held item with
     the same id (none held: apply). Then, if the frame's `seq` is higher than the held `seq`, take its `cursor` and
     `seq`.
   - `hello`, `ping`: change nothing. `hello` with `resumed: false` means a snapshot is next.
   - A write's answer is a Reply: apply it as a `reply` frame's item, by its `seq`.
   - `earlier`: put its messages in front, each once by id.
2. **So a duplicate does nothing** (same `seq`), **and an out-of-order frame does nothing** (lower `seq`): a read
   that answers after the stream has moved on cannot take the chat back.
3. **Reconnect** after a drop with the held cursor. Back-off: 0.5 s, 1 s, 2 s, 4 s, 8 s, then 15 s, each ±20 %.
   It starts again from 0.5 s once a stream has stayed open 10 s. A `close` frame says when instead (above).
4. **While the stream is down**, read every 2 s with the held cursor. Stop reading when a stream is open again.
5. **Follow only while seen**: a chat on screen and the app in front. Leaving closes the stream; coming back
   resumes from the held cursor.
6. A client keeps the cursor with what it shows (the host decides where), so an open shows the last chat at once and
   resumes from there.

## The server's rules

1. `seq` never goes down for a chat, except across a `snapshot`.
2. Frames on one stream are sent in `seq` order. Every item change is in exactly one frame on each open stream.
3. A stream starts with `hello`. If it resumes, it then sends every change after the cursor, oldest first, before any
   change made later. The read with `after` answers the same frames.
4. A change made while a stream is starting is not lost: the room reads after the stream's cursor once it is
   listening.
5. `ping` every 15 s. `close` with `rotate` at 10 minutes.
6. A frame's `data` is one line of JSON (no newline inside), at most 256 KB. A message whose text is longer is cut by
   the host with `…`.

## Host adapter

What a host Worker writes. The package does the rest: routes, frames, cursors, the room Durable Object, broadcast,
ping and rotate.

```ts
interface LiveAdapter<Who> {
  /** Checks the bearer and the chat. Answers who is asking, or a refusal (401, 403, 404). */
  authorize(request: Request, chat: string): Promise<Who | LiveRefusal>;
  /**
   * The chat's changes after `cursor`, oldest first, and the cursor after them.
   * `cursor` null, or one it cannot resume from: `{reset: true}` with the whole chat.
   */
  read(who: Who, chat: string, cursor: string | null, limit: number): Promise<LiveRead>;
  /** The `limit` messages just before one, for `earlier`. */
  earlier(who: Who, chat: string, before: string, limit: number): Promise<{messages: Message[], moreBefore: boolean}>;
  /** The writes. Each answers the Reply, or a refusal (400, 404, 409). Optional: a host without one answers 404. */
  send?(who: Who, chat: string, body: SendBody): Promise<{reply: Reply, repeat: boolean} | LiveRefusal>;
  force?(who: Who, chat: string, reply: string): Promise<Reply | LiveRefusal>;
  remove?(who: Who, chat: string, reply: string): Promise<Reply | LiveRefusal>;
  answer?(who: Who, chat: string, body: AnswerBody): Promise<Reply | LiveRefusal>;
}
```

After a write that changed something, the package notifies the chat's room itself. When a chat changes any other
way, the host calls `notifyChat(namespace, chat)`. The room reads after the cursor it last sent and
broadcasts what is new. A failed notify is logged, never answered: the next read catches up.

- **FeedbackKit**: `notifyChat` where it calls `chatChanged` today. Its `seq` and cursor come from a change counter
  on the chat.
- **Agent Pager**: the hub follows the transcript (`follow`); while a room has streams, the room holds one hub stream
  and notifies itself on each message. The transcript offset is `seq`; the cursor keeps the hub's own cursor.

## Pushes

A host's push about a chat may carry the chat's `cursor` after the change. A tap, or the notification service, then
does one `live/read?v=1&after=<the cursor it holds>` instead of fetching the whole chat. The push's cursor only says
the chat moved; the client still takes the cursor from the frames it reads.

## Conformance

`server/` exports a suite that runs every fixture against a host's adapter in a fake room. Each backend runs it in
its own CI and writes tests only for its adapter. The Swift client runs the same fixtures through its reducer and
against a fake server.

Fixtures (`protocol/fixtures/`):

| File | Covers |
|---|---|
| `frames.json` | one of each frame type, as JSON and as SSE text |
| `connect-fresh.json` | no cursor: `hello`, `snapshot` |
| `reconnect-resume.json` | reconnect with a cursor: `hello resumed`, the missed frames, nothing twice |
| `cursor-expired.json` | a cursor the host can't resume: `hello`, `snapshot` |
| `duplicate.json` | the same frame twice, from the stream and a read |
| `out-of-order.json` | a read's older version after the stream's newer one |
| `snapshot-reset.json` | a snapshot with a lower `seq` replaces all |
| `message-update.json` | a partial message, then its final version |
| `reply-lifecycle.json` | a reply pending, queued, delivered, and the message it became |
| `refusals.json` | each HTTP refusal and each `close` code, and what the client does |
| `earlier.json` | "Load earlier": messages in front, cursor unchanged |
| `display-order.json` | messages by `at`, not arrival; no `at`; ties |
| `writes.json` | send, a repeat send, force, remove, answer: answers, frames, refusals; force while waiting |

The fixtures are written by `protocol/generate.py`: change it, run it, commit both.

## Versioning

Clients ignore frame types and fields they do not know. This is `v1`. A change that an existing client or server can ignore (a new optional field, a new `extra` key) stays
`v1`. Anything else (a new frame type a client must act on, a changed meaning) is `v2`, served beside `v1` until the
apps have moved. The package and the Swift module are released together with this repo's tags.
