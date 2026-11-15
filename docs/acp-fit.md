# Fit check: ACP instead of our live protocol?

Question (Jai, 2026-11-15): should apps follow agent chats with the [Agent Client Protocol](https://agentclientprotocol.com)
(ACP) v2 over its remote transport, instead of [our live protocol v1](live-protocol.md)? Checked against the ACP v2
draft, its prompt and session-resume RFDs, and the Streamable HTTP / WebSocket transport RFD, on 2026-11-15.

**Recommendation: speak ACP v2 over its Streamable HTTP transport, pinned to the spec version we implement, with
`_` extensions for what ACP lacks.** No breaker was found (below); HTTP/2 and draft status are not blockers (Jai).
Our v1 becomes "the ACP profile our hosts and apps speak", and its fixtures become ACP messages.

## Concept by concept

| v1 | ACP v2 | Fit |
|---|---|---|
| snapshot on connect | `session/resume` with `replayFrom: start` replays history as `session/update`s, then a `state_update` | yes, but replays all history; no "newest 200" |
| resume from an event id | `replayFrom` cursor (inclusive) | yes, in v2 (draft) |
| message upsert by id | `session/update` patches messages and tool calls by stable id; omitted fields kept, `null` clears | yes: same model |
| `status` pending / queued / delivering / delivered / failed | none: a prompt's only status is "inserted" (its response returns `messageId`) | extension `_status` |
| queue, force | held prompts are inserted in order; queueing and steering "left to a later RFD" | extension |
| edit or remove a queued message | cancel only (`-32800` before insertion); no edit | extension `_edit` |
| elicitation | `session/request_permission` (title, description, subject); elicitation as such not in v2 | partial: it is a request the agent waits on, not state |
| state (working, activity, problem, model, effort) | `state_update` `running` / `idle` / `requires_action`; config options for model and effort | close; activity and problem as `_` fields |
| attachments | content blocks (image, resource link) | yes |
| sender (several people in one chat) | "sender attribution … out of scope" | extension |
| auth | "orthogonal" to the transport: headers | yes |
| several observers of one chat | named as a goal; not specified | gap |

## The three possible breakers

- **We relay; ACP assumes the server is the agent.** Not a breaker. The host Worker plays the agent side:
  `session/prompt` is acknowledged with the `messageId` once the message is inserted (a queued message's response
  waits, as ACP's held prompts do); the transcript's messages go out as `session/update`s. Delivery states ACP lacks
  ride as `_status` on the user message.
- **Several clients on one chat.** Not a breaker. Each client opens its own connection and `session/resume`s the
  session; the room sends every `session/update` to every connection on it. ACP names this as a goal and forbids
  nothing; we specify it in our profile. Sender attribution is "out of scope" in ACP: `_sender`.
- **No usable SDK.** Not a breaker. TypeScript: `@agentclientprotocol/sdk` gives the types and JSON-RPC; its remote
  transport is planned, not shipped, so the Durable Object, replay and broadcast are ours either way. Swift: community
  SDKs only and none with the SSE transport, so we write Codable types and the transport on DurableNetworking.

What it costs, against v1:

- **Round trips on (re)connect:** `initialize` → connection stream → `session/resume` (with `replayFrom`) → session
  stream, where v1 was one GET. Cached connection ids and HTTP/2 keep it to one connection; measure it on a phone.
- **Two drafts to track:** v2 and the transport RFD (whose own replay is deferred to v2; we use v2's
  `session/resume` `replayFrom` for it). We pin a spec version and its schema in the fixtures.
- **JSON-RPC envelopes** on every message, and write answers that arrive on the session stream, not the POST.

## SDKs

- **TypeScript:** `@agentclientprotocol/sdk` (official; agent and client sides, JSON-RPC, ndjson streams). The remote
  transport is planned for it, not shipped. A Worker would still write the Durable Object, replay and broadcast.
- **Swift:** community only (`aptove/swift-sdk`, `wiedymi/swift-acp`, `rebornix/acp-swift-sdk`, others). None has
  the SSE transport (aptove: WebSocket only), and none runs on DurableNetworking. We would write the transport anyway.

## Extensions we need

`_status` (pending, queued, delivering, delivered, failed, removed), `_clientRef`, `_detail` and `_sender` on user
messages; `_edit` (a queued message's text, attachments, force) and `_force` on prompts; `_activity` and `_problem`
on `state_update`; elicitation as `session/request_permission` with options, answered by its response (or ACP's own
elicitation once it lands); host fields in `_meta`.

## Next

Rewrite live-protocol.md as our ACP v2 profile (the methods we use, the extensions, the room's broadcast and resume),
regenerate the fixtures as ACP messages, then build the server package and AgentChatLive on it.

Sources: [v2 draft announcement](https://agentclientprotocol.com/announcements/acp-v2-draft),
[prompt RFD](https://agentclientprotocol.com/rfds/v2/prompt),
[session resume replay RFD](https://agentclientprotocol.com/rfds/v2/session-resume-replay),
[v2 session setup](https://agentclientprotocol.com/protocol/v2/session-setup),
[transport RFD](https://agentclientprotocol.com/rfds/streamable-http-websocket-transport),
[TypeScript SDK](https://github.com/agentclientprotocol/typescript-sdk),
[community libraries](https://agentclientprotocol.com/libraries/community).
