# AgentChatKit

> The chat with a coding agent, as a Swift package: one screen, its bubbles, its field and its attachments, for every
> app that talks to an agent.

PRHub's Ask AI, Agent Pager's threads and chats, and [FeedbackKit](https://github.com/jai/feedbackkit) all draw their
chats with it. It knows nothing of pull requests or of any app's Worker: a host turns its own conversation into
`ChatMessage`s and gives the slots what only it has.

## Products

| Product | What it holds | Imports |
|---|---|---|
| `AgentChatCore` | `MessageImage` (a screenshot as a Worker takes it) and `ScreenshotLine` | Foundation. Safe in an app extension. |
| `AgentChatKit` | `ChatView`, `ChatMessage`, `SessionBubble`, `SessionComposer`, `ComposerAttachments`, `ModelReasoningChip` and `ModelPicker`, `DeliveryTicks`, `ChatQuickReply` and `WaitWhatButton`, `MarkdownText`, `ChatScroll` and `followsChatEnd`, `ReturnKey`, `Pasteboard`, `FoldSet`, `ChatStyle`, `ChatTheme` | SwiftUI, and `AgentChatCore`, re-exported. |
| `AgentChatLive` | `LiveChatModel` follows a chat over [our ACP v2 profile](docs/live-protocol.md): initialize, the session stream, resume from a cursor, reconnect with back-off, the writes (send, edit, send now, remove) and the agent's questions; `LiveChat` and its `chatMessages` | `AgentChatKit`, [DurableNetworking](https://github.com/jai/durable-networking) |
| `AgentChatLiveTesting` | `LiveLoopbackServer`: an ACP host in memory, for tests, previews and demos | `AgentChatLive` |
| `@jai/agentchat-live` (npm, [`server/`](server/README.md)) | The protocol's server for a Cloudflare Worker: `<base>/acp`, the room Durable Object, replay and broadcast; a conformance suite every host runs; an in-memory host | none; installed from each release's tarball |

## Use it

```swift
.package(url: "https://github.com/jai/agentchatkit", from: "0.1.0")
```

```swift
ChatView(messages: messages, sent: sentCount, readsEnd: $readsEnd, focus: $focused) { _ in
    EmptyView()
} header: {
    EmptyView()
} footer: {
    EmptyView()
} composer: {
    SessionComposer(draft: $draft, isSending: isSending, send: send, focused: $focused)
}
```

## Theme

A chat takes its fonts, colours and icons from `ChatTheme`, set once at the host's root:

```swift
RootView().chatTheme(ChatTheme(font: { .app($0) }, toneGood: .green))
```

With none, `ChatTheme.standard` draws the system's: Dynamic Type on the phone, the Mac's sizes times its View menu's
text size (`macTextScale`), the system's grounds, and the host's `ToneGood` and `ToneBad` colour sets. The chat's own
measures (a bubble's insets, its widest share of a wide window) are `ChatStyle`'s.

## Thread rows and navigation

`ChatThreadRow` accepts host-rendered status accessories and chips. Context, title and an optional `About:`
description are shared on phone and Mac. Hosts can wrap a row in their own navigation or use the native list:

```swift
NavigationStack {
    ChatThreadList(items: threads, title: \.title, actions: { thread in
        ChatThreadActions(archive: {
            hideLocally(thread.id)
            return .success(())
        })
    }) { thread in
        ChatThreadRow(title: thread.title, context: thread.context, about: thread.summary) {
            HostStatusAccessory(thread: thread)
        } chips: {
            HostChips(thread: thread)
        }
    } destination: { thread in
        HostConversation(thread: thread)
    }
}
```

`chatThreadActions(title:actions:)` also attaches these actions to a host-owned row. Nil hooks omit their controls.
Archive calls the supplied hook; local hiding is a host policy. Delete presents a confirmation, then invokes the
host's hook. Both hooks return `Result<Void, ChatActionError>`, disable the row while awaiting completion, and show
host errors without removing the row. The kit implements no vendor archive/delete endpoint. `ChatActionError`
lives in `AgentChatCore` and is re-exported by `AgentChatKit`.

## Reply queue

Own one `ReplyQueueController<ID>` per conversation. Map server snapshots into `QueuedReply<ID>` with stable IDs,
client refs, creation dates, delivery states, exact status wording, and `actionPending` for an accepted action still
in progress. Only `.inThreadQueue` appears in the strip, oldest first; local outbox `.queued` stays with the host.

```swift
let queue = ReplyQueueController<String>(remove: { reply in
    await host.removeQueuedReply(reply.id) // Result<QueuedReply<String>?, ChatActionError>
}, sendNow: { reply in
    await host.sendQueuedReplyNow(reply.id)
})

// Above the host's composer; bind its draft to queue.draft.
ThreadQueuedReplies(model: queue, interrupts: host.sendNowInterrupts)

// Record the composer's intent before submission, using the reply's stable client ref:
queue.sendNowWhenQueued(clientRef: clientRef)

// When a host snapshot arrives:
queue.replaceReplies(mappedReplies)
await queue.sendNowWhereQueued()
```

Each hook returns the updated authoritative reply with the same ID, or nil when it leaves the queue. A successful
Remove must mean the host accepted removal and it is safe to put its words back in the draft. If removal is still
pending, return that reply with `actionPending: true`. Edit prepends only after success, preserving words typed during
the request. A failure leaves the draft alone and appears on the row; return a user-facing `ChatActionError`.
Concurrent actions for the same reply are rejected while awaiting a hook or while `actionPending` is true.

Omit the Send now hook to omit its button. `interrupts` comes from host capabilities; the kit never assumes that
sending stops a turn. Composer intents are consumed before the first request, including on failure, and repeated
snapshots cannot automatically send them again. An explicit button tap can retry a failed request. Intent tracking
lasts for the controller's lifetime; hosts own durable outbox/restart behavior and discard controllers with their
conversation. Polling, routing, server refreshes and cancellation of network requests stay in the host.

## Delivery status and questions

Map the host's delivery model to `ReplyDeliveryState`. `.pending(attempts: 0)` and `.delivering` draw one sent tick;
`.delivered` draws two. `.queued`, retrying `.pending(attempts: 1)` (or more), `.inThreadQueue`, `.failed`, `.removed`
and `.other` draw the host's exact status text without ticks. `SentReplyStatus` takes optional Retry/Cancel callbacks
and `isSending`; the host owns those operations, errors and updated state. Existing `DeliveryTicks` APIs are unchanged.

```swift
SentReplyStatus(state: .failed, text: "Connection lost", about: reply.text,
                isSending: retrying, retry: retry, cancel: cancel)

// Option is the host's Identifiable type; its full payload reaches the callback.
ThreadQuestion(question: ask.question, context: ask.context, options: ask.options,
               isSending: answering, label: \.label, answer: sendAnswer,
               reply: openComposer, waitWhat: { send(ChatQuickReply.waitWhat.text) })
```

Question/context and callbacks are optional. Answer buttons share equal emphasis and width, sit side by side when
the longest fits on one line, and stack when it cannot. All answer/Reply/Wait, what? controls respect `isSending`.
Use `showsQuestion`/`showsContext` when another part of the host already says those words.

## Sent screenshots

```swift
SentScreenshotStrip(key: reply.clientRef) { key in
    await host.loadSentJPEGs(key) // Result<[Data], ChatActionError>, ordered as sent
}
```

A strip opens its own viewer on tap. For one viewer shared by a conversation's strips, own a
`SentScreenshotViewing` and add `.presentsSentScreenshots(viewing)` to the conversation. The viewer uses a full-screen
cover on iOS and a sheet on Mac; Close or a downward swipe dismisses it. JPEG loading is asynchronous and decoding
runs off the main actor. Unreadable images are skipped while keeping original indexes and stable key/index IDs;
load failures show the host's error. Changing the key cancels the old image load. Persisting files, mapping
client refs to server reply IDs and refresh policy remain host responsibilities.

The original accessibility identifiers remain `queued-reply`, `reply-status`, `reply-ticks-1`, `reply-ticks-2`,
`wait-what`, `sent-screenshot`, `sent-screenshot-viewer`, and `sent-screenshot-viewer-close`.

## Adoption boundary

These are additive APIs. App originals need not change until their host adopts a released package. Host-specific
ChatLinks, Finder, food, transport models and screenshot persistence stay outside the kit. A later adopter maps
its statuses and callbacks, keeps navigation in the host, and supplies only capabilities it actually supports.

## Demo

`Demo/` is an iPhone and Mac app that shows the chat at work with a scripted agent: replies that stream in
Markdown after quiet tool-call rows, the working line, delivery ticks, "Wait, what?", screenshots sent from the reply
box, the model and reasoning chip, a long chat that keeps to its end, three themes set by the host (PR Hub,
Terminal, Paper), and a Live chat followed with AgentChatLive over ACP, whose toolbar drops the stream or takes the network
away to show it reconnect, and whose agent asks before it merges. Everything runs in the app: no network, no account.

<p>
  <img src="Demo/Screenshots/working.png" width="250" alt="The agent at work after a screenshot, in the PR Hub theme">
  <img src="Demo/Screenshots/terminal-markdown.png" width="250" alt="A Markdown answer in the Terminal theme">
  <img src="Demo/Screenshots/paper-wait-what.png" width="250" alt="Wait, what? answered plainly, in the Paper theme">
</p>

```sh
cd Demo && xcodegen && open AgentChatDemo.xcodeproj
```

Run `AgentChatDemo-iOS` or `AgentChatDemo-macOS`. The package is a local dependency, so a change in `Sources/` shows in
the demo at once. Launch arguments set it up: `-DemoChat tour|long|live`, `-DemoTheme prHub|terminal|paper`, and
`-DemoPace fast|slow` for the agent's speed.

The sidebar's **Shared pieces** (or `-DemoChat extraction`) opens independent fixtures for the shared thread list,
queue, delivery status, question and sent screenshots. They show host callback counts, deliberate failures,
pending/disabled controls and repeated queue snapshots without changing the scripted tour. `ExtractionUITests`
drives Archive/Delete and confirmation cancellation, queue Edit/Remove/Send now, Retry/Cancel, all question callbacks,
adaptive answer stacking and screenshot viewer Close/swipe-down. Package unit tests cover queue failure/success,
ordering and concurrent/send-once behavior, delivery tick mapping, and image decode/order/orientation.

## Develop

`swift test`. Swift 6, iOS 26 and macOS 26.

The demo is this repo's UI-test host: `AgentChatDemo-iOS`'s tests (`Demo/UITests`) walk the main flows on an iPhone, and
`testReadmeScreenshots` takes the pictures above (they are kept on its test result).


When a host already owns route values or a selected detail column, use the list's header/footer initializer. Its row
closure contains the host's own `NavigationLink(value:)` or selection button, so returning to the list and restoring
drafts remain host-owned. Header and footer hold its starting, empty and error states. The list supplies lazy rows,
scrolling, shared row menus and insertion/removal motion; it does not keep a second navigation path.
