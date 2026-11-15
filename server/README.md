# @jai/agentchat-live

The server side of [our ACP v2 profile](../docs/live-protocol.md): how an app follows one agent chat live, and
writes to it. A host Cloudflare Worker gives a small adapter; this package does `<base>/acp` (ACP's Streamable HTTP
transport), JSON-RPC, signed connection ids, the room Durable Object, replay, broadcast, questions and keep-alive.

No runtime dependencies. Workers runtime APIs only (`Request`, `Response`, streams, Web Crypto).

## Install

Each release of this repo carries the package as its `npm pack` tarball. Pin the version by URL:

```json
"dependencies": {
  "@jai/agentchat-live": "https://github.com/jai/agentchatkit/releases/download/vX.Y.Z/jai-agentchat-live-X.Y.Z.tgz"
}
```

Why not npm: no registry account or token to keep, and a release's asset is fixed to its tag. npm, pnpm and bun all
install a tarball URL, and Dependabot ignores it, so a host moves on by changing the URL.

## Use

```ts
import { createLiveRoom, handleAcp, notifyChat, type LiveAdapter } from "@jai/agentchat-live";

// The room: one Durable Object per session. Bind it in wrangler.jsonc as LIVE_ROOMS.
export const LiveRoomObject = createLiveRoom((env: Env) => myAdapter(env), { refreshEvery: 15_000 });

// <base>/acp
app.all("/v2/acp", (c) => handleAcp(c.req.raw, { adapter: myAdapter(c.env), rooms: c.env.LIVE_ROOMS, secret: c.env.ACP_SECRET }));

// When a chat changes other than through a write (the agent wrote, the runner reported):
await notifyChat(env.LIVE_ROOMS, chatId);
```

- `secret` signs connection ids: any long random string. Changing it makes every client `initialize` again.
- `refreshEvery` (ms, off by default): the room also reads on that tick while it has streams, for changes nothing
  notifies (FeedbackKit's stuck-delivery `problem`, its `builderOnline`).
- A write through the package (prompt, edit, remove, an answer) notifies the room itself.
- The agent asks: store the question so `read` answers it (with the state `requires_action`), then
  `notifyQuestion(rooms, sessionId)`. Every connection gets `elicitation/create`; the first answer goes to
  `adapter.answer`, and the others get `$/cancel_request`.

## The adapter

```ts
interface LiveAdapter<Who> {
  authorize(request: Request, sessionId: string): Promise<Who | LiveRefusal>;
  read(who: Who, sessionId: string, cursor: string | null): Promise<LiveRead>;
  prompt?(who: Who, sessionId: string, prompt: PromptBody): Promise<{ messageId: string; repeat: boolean } | LiveRefusal>;
  edit?(who: Who, sessionId: string, messageId: string, body: EditBody): Promise<string | LiveRefusal>;
  remove?(who: Who, sessionId: string, messageId: string): Promise<string | LiveRefusal>;
  answer?(who: Who, sessionId: string, question: string, answer: ElicitationAnswer): Promise<void | LiveRefusal>;
}

type LiveRead =
  | { expired: true }
  | { expired?: false; cursor: string; updates: { cursor: string; update: SessionUpdate }[];
      state: StateUpdate; question: OpenQuestion | null };
```

- `Who` must survive `JSON.stringify`: it travels from the Worker to the room in a header.
- `read(…, null)` is the retained history (at most the newest 200 messages, oldest first); `read(…, cursor)` every
  update after it, each with its own cursor. A cursor the host can't resume from: `{expired: true}` (the client gets
  `-32602` and resumes from start).
- A write the host lacks answers `-32601`. A refusal from a write: 409 answers `-32009` (`conflict`), 400 and 404
  answer `-32602`.

`@jai/agentchat-live/memory` is a complete in-memory host (`MemorySessions`): the reference adapter, and a fake
server for a host's own tests.

## Conformance

Every host runs the suite in its own CI, against its own adapter and storage, and writes tests only for its adapter.
The fixtures ship inside the package. It is runner-agnostic:

```ts
import { conformanceCases } from "@jai/agentchat-live/conformance";

const cases = conformanceCases({
  adapter,
  capabilities: { queues: false, edit: true, remove: true, answer: false }, // FeedbackKit's
  reset: async () => newEmptyChat(),            // a session the owner below may follow
  apply: async (sessionId, update) => store(sessionId, update), // as the host would store it
  expire: async (sessionId) => forgetHistory(sessionId),        // optional
  ask: async (sessionId, params) => openQuestion(sessionId, params), // needed with answer: true
  request: (url, init = {}, auth = "owner") => withBearer(url, init, auth), // owner, none or stranger
});
for (const c of cases) test(c.name, { skip: c.skip }, c.run); // vitest: (c.skip ? it.skip : it)(c.name, c.run)
```

- **Capabilities** say what the host does. A step it can't do is skipped: `queues: false` expects `pending` where
  the fixture says `queued` and skips "send now"; `edit` or `remove` false skips those writes and expects `-32601`
  if the adapter lacks them; `answer` false (or no `ask`) skips the question case.
- Updates are compared without cursors (they are the host's), as subsets: a host may add fields. On what a write
  makes, `at` and `sender` are the host's and not compared.
- `strangerStatus: 404` for a host that answers someone else's session `404`, not `403`.

## Develop

```sh
npm ci
npm test           # node --test, Node 24: the conformance suite on the in-memory host, and unit tests
npm run typecheck
npm run build      # dist/: JS, .d.ts, and the fixtures
npm run fixtures   # after protocol/generate.py: embeds protocol/fixtures in src/fixtures.generated.ts
```
