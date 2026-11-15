# Fit check: ACP instead of our live protocol?

Question (Jai, 2026-11-15): should apps follow agent chats with the [Agent Client Protocol](https://agentclientprotocol.com)
(ACP) v2 over its remote transport, instead of [our live protocol v1](live-protocol.md)? Checked against the ACP v2
draft, its prompt and session-resume RFDs, and the Streamable HTTP / WebSocket transport RFD, on 2026-11-15.

**Recommendation: keep our protocol, shaped like ACP v2, so a later switch is a mapping, not a rewrite.** Use ACP on
the other side, where it fits today: between the hub and agents that speak it (`codex-acp`, `claude-agent-acp`).

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

## What breaks

- **Draft.** v2 was published 2026-07-20 as a draft that "can, and will, change", not to ship by default. The remote
  transport RFD is Active, aimed at v1, with no replay: "in-flight messages are not replayed"; Last-Event-ID resume
  is deferred to v2. Building on both today means tracking two moving drafts.
- **A handshake before any data.** `initialize` (POST) → connection id → a connection stream → `session/resume` →
  a session stream. Ours is one GET. Five round trips is the slow phone-in-a-lift case DurableNetworking exists for.
- **HTTP/2 is a MUST.** Cloudflare's edge and URLSession both speak it, so it is not a blocker, but it is a constraint
  we don't need: our writes are separate requests already.
- **We relay; ACP assumes we are the agent.** Agent Pager reads transcripts of Claude Code and Codex sessions it did
  not start; FeedbackKit is a store between a person and a runner. Neither can answer `session/prompt` as the agent
  does, and both carry delivery states (queued, failed) that ACP does not have.
- **Several clients on one chat** (the phone, the Mac app, a coordinator) is the normal case for us and unspecified
  in ACP.
- **JSON-RPC overhead** is small per message, but every frame gains an envelope and every write a request id the
  server must answer on a different stream.

## SDKs

- **TypeScript:** `@agentclientprotocol/sdk` (official; agent and client sides, JSON-RPC, ndjson streams). The remote
  transport is planned for it, not shipped. A Worker would still write the Durable Object, replay and broadcast.
- **Swift:** community only (`aptove/swift-sdk`, `wiedymi/swift-acp`, `rebornix/acp-swift-sdk`, others). None has
  the SSE transport (aptove: WebSocket only), and none runs on DurableNetworking. We would write the transport anyway.

## What "shaped like ACP" means in v1

Already true: messages upserted by stable id; the write answers the message id and the stream echoes it; one
snapshot then changes; `extra` for host fields; unknown fields and events ignored. Worth adopting now, at no cost:

- state names that map 1:1: `working` true = `running`; `elicitation` set = `requires_action`; else `idle`.
- `_`-prefixed names for anything ACP lacks, when we add fields later.

Revisit when ACP v2 is final, its remote transport has Last-Event-ID replay, and it specifies several observers.

Sources: [v2 draft announcement](https://agentclientprotocol.com/announcements/acp-v2-draft),
[prompt RFD](https://agentclientprotocol.com/rfds/v2/prompt),
[session resume replay RFD](https://agentclientprotocol.com/rfds/v2/session-resume-replay),
[v2 session setup](https://agentclientprotocol.com/protocol/v2/session-setup),
[transport RFD](https://agentclientprotocol.com/rfds/streamable-http-websocket-transport),
[TypeScript SDK](https://github.com/agentclientprotocol/typescript-sdk),
[community libraries](https://agentclientprotocol.com/libraries/community).
