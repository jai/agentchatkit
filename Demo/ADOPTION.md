# Adoption handoff

Implemented in the existing local checkout, relative to its unpushed extraction HEAD. No commits, pushes, branches,
worktrees, workflow edits or other repository edits were made. FeedbackKit adaptation, Brain/thread work and CI/release
remain with the parent. Agent Pager was read only as the queue/row reference.

## API changes for the adopter

- `ChatTheme.typography` has optional meta/objectTitle/body/control `ChatTextStyle` roles (font, leading, lineSpacing).
  Unset roles resolve via the current legacy `font` closure. Existing ticks and quick-reply controls retain their original caption2 and semibold-footnote fallback; explicit host roles win. Nil leading/lineSpacing preserve the host font’s own
  leading and inherited spacing. `ChatTheme.spacing` holds host spacing/row insets;
  `controlSize` defaults to native `.large`. No new view selects a point size.
- `ChatThreadRow` keeps its two-generic-parameter type and existing accessory/chips initializer. A second initializer
  adds a `titleMark` builder before accessory/chips. Context/status share first baseline, then marked title, About
  body and chips. Nil/empty context moves status to the title baseline. All text can wrap.
- `ChatThreadList` keeps both existing initializers, including `Destination == EmptyView` host row/header/footer.
  Add `selection: $selectedID` and `open: openItem` for Mac selection/Return. The callback receives the full Item;
  the parent owns the route/path/detail selection. Native List owns arrows. The list registers no route values or
  destination types, including Item.ID. The demo verifies host String routes alongside String item IDs.
- The list already attaches actions. Do not attach a second `chatThreadActions` modifier to its host row. Standalone
  rows can still use that modifier. Right-click, phone long-press/trailing swipe, and Mac Delete share one controller
  per row identity and the same confirmation/pending/error states. Missing hooks omit menu/swipe controls and disable
  the Mac Delete command. Pending controllers survive a temporarily absent/reinserted item ID.
- `ChatThreadActions.menuItems { ... }` keeps host Pin/Open menu items beside Archive/Delete, without nested context menus replacing one another. Shared UI coverage invokes a host Open menu item on both platforms.
- Native NavigationLink disclosure indicators belong to List; remove an explicit default-row chevron when adopting
  the convenience destination initializer. No kit-owned navigation destination is registered for the host initializer.
- Identifier types: `ChatThreadRowIdentifiers`, `ChatThreadActionIdentifiers`, `QueuedReplyIdentifiers`,
  `ReplyStatusIdentifiers`, `ThreadQuestionIdentifiers<Option.ID>`, `SentScreenshotIdentifiers`. Queue configuration
  is a per-reply closure; answers use option IDs and screenshots use original JPEG indexes. `DeliveryTicksLine` and
  `WaitWhatButton` accept `identifier:`. Existing default IDs are retained. Nil slot IDs apply no modifier, preserving
  explicit host status/chip IDs. The demo includes sessionRow, thread-line-shaped fields and finder-message-retry.
- Queue controls are native full icon-and-word controls: pencil Edit and destructive bin Remove left, prominent
  Send now right, destructive tint when interrupting. They reflow at narrow/large text sizes. No queue-controller
  logic changed. The three existing intent/revision regressions and all other existing tests are untouched.
- Screenshot identifiers travel from a strip into either its local or shared viewer. A host may override the shared
  viewer explicitly using `.presentsSentScreenshots(viewing, identifiers: ids)`.

## Authored coverage — NOT RUN

- `Tests/AgentChatKitTests/ChatThemeTests.swift`: live legacy fallback and host typography metrics/tokens. Identifier coverage exercises actual controls in the UI suites.
- `Tests/AgentChatKitTests/ChatThreadActionControllerTests.swift`: confirmation/cancel/missing hooks, competing
  keyboard/menu requests during pending/error, identity reuse and pending removal/reinsertion.
- `Demo/SharedUITests/AdoptionUITests.swift`: both platforms; custom IDs, inherited slot IDs, explicit slot overrides,
  typography/leading/line-spacing geometry, context/status baseline, title mark and fallback, queue labels/actions,
  delivery Retry/Cancel, question callbacks/disabled controls, local/shared viewers and host route ownership.
  The iPhone-only method checks swipe and long-press actions/confirmation against the same host hooks.
- `Demo/MacUITests/MacThreadListUITests.swift`: native mouse/arrow selection, Return host callback, Delete
  confirm/cancel, repeat commands while pending/error and right-click host actions.
- Original iOS `ExtractionUITests` and main `DemoUITests` are retained. No test or native build command was run,
  including on Cube03. Only source/diff review was performed; `git diff --check` is clean.

## Rendered pictures — parent CI must produce/review

`testLightRenderedPieces`, `testDarkRenderedPieces` and `testLargeTextRenderedPieces` capture row, convenience thread
list, host thread list, queue, delivery status, question, screenshot strip and screenshot viewer. These use actual
`XCUIScreen` screenshots, never synthetic images. Phone large-text row/queue have extra lower-scroll captures.
Fixtures contain no network/date-dependent content. Both platforms use explicit light/dark appearance; large uses
phone accessibility Dynamic Type or larger semantic host fonts on Mac.

Every image is an xcresult attachment. With `CHATDEMO_SCREENSHOTS` set, it is also written to that directory as:

- `ios-{row,threads,host-threads,queue,delivery,question,screenshots,viewer}-{light,dark,large}.png`
- `macos-{row,threads,host-threads,queue,delivery,question,screenshots,viewer}-{light,dark,large}.png`
- `ios-{row,queue}-large-lower.png`

`Demo/project.yml` includes SharedUITests in the existing iOS target and adds `AgentChatDemoMacUITests` (MacUITests +
SharedUITests) to the macOS scheme. Workflow wiring is deliberately left to the parent. Existing checked-in demo
pictures are retained. No new rendered pictures have been generated locally under the no-build/no-test constraint.

## Review limits

All new Swift and UI tests remain uncompiled and unexecuted in this delegated step. Parent CI must establish SDK
compilation, actual native List focus/keyboard behavior, native dialog identifier exposure and screenshot geometry.
The UI baseline check compares observable text frames; it does not read font-baseline metadata from XCTest. Rendered
picture review remains necessary, especially for large text and native disclosure indicators. FeedbackKit has not
been edited or compiled against this API here.

## Changed files

- `Demo/ADOPTION.md`
- `Demo/MacUITests/MacThreadListUITests.swift`
- `Demo/SharedUITests/AdoptionUITests.swift`
- `Demo/SharedUITests/FixtureUITestCase.swift`
- `Demo/Sources/AgentChatDemoApp.swift`
- `Demo/Sources/DemoAdoptionFixtures.swift`
- `Demo/Sources/DemoAdoptionSettings.swift`
- `Demo/Sources/DemoDeliveryScreen.swift`
- `Demo/Sources/DemoHostThreadList.swift`
- `Demo/Sources/DemoQuestionScreen.swift`
- `Demo/Sources/DemoQueueScreen.swift`
- `Demo/Sources/DemoScreenshotsScreen.swift`
- `Demo/Sources/DemoThreadList.swift`
- `Demo/project.yml`
- `README.md`
- `Sources/AgentChatKit/ChatAccessibility.swift`
- `Sources/AgentChatKit/ChatQuickReply.swift`
- `Sources/AgentChatKit/ChatSpacing.swift`
- `Sources/AgentChatKit/ChatTheme.swift`
- `Sources/AgentChatKit/ChatThreadActionController.swift`
- `Sources/AgentChatKit/ChatThreadActionIdentifiers.swift`
- `Sources/AgentChatKit/ChatThreadActions.swift`
- `Sources/AgentChatKit/ChatThreadList.swift`
- `Sources/AgentChatKit/ChatThreadRow.swift`
- `Sources/AgentChatKit/ChatThreadRowIdentifiers.swift`
- `Sources/AgentChatKit/ChatTypography.swift`
- `Sources/AgentChatKit/DeliveryTicks.swift`
- `Sources/AgentChatKit/QueuedReplyIdentifiers.swift`
- `Sources/AgentChatKit/ReplyDeliveryState.swift`
- `Sources/AgentChatKit/ReplyStatusIdentifiers.swift`
- `Sources/AgentChatKit/SentScreenshotIdentifiers.swift`
- `Sources/AgentChatKit/SentScreenshotStrip.swift`
- `Sources/AgentChatKit/SentScreenshotViewer.swift`
- `Sources/AgentChatKit/ThreadAnswerLayout.swift`
- `Sources/AgentChatKit/ThreadQuestion.swift`
- `Sources/AgentChatKit/ThreadQuestionIdentifiers.swift`
- `Sources/AgentChatKit/ThreadQueuedReplies.swift`
- `Tests/AgentChatKitTests/ChatThemeTests.swift`
- `Tests/AgentChatKitTests/ChatThreadActionControllerTests.swift`

## AgentChatLive adapters — current delegated change

The shared controls now consume the landed live model. No ACP parser, transport, server, protocol or dependency
semantics changed. Generic Archive/Delete row/list hooks, native keyboard/menu composition, upstream navigation,
Extraction fixtures and their tests are preserved. `ReplyQueueController` and all its intent/revision regressions
are untouched. Generic ticks keep caption2 and WaitWhat keeps semibold-footnote unless the host supplies roles.

### Public API signatures

```swift
@MainActor @Observable final class LiveChatControls {
    typealias Retry = @MainActor (LiveMessage) async throws -> Void
    init(live: LiveChatModel)
    let live: LiveChatModel
    private(set) var busy: Set<String>
    var errors: [String: ChatActionError] { get } // Filtered against current live status.
    private(set) var answering: Bool
    func edit(_ id: String, restore: @MainActor (String) -> Void) async -> Bool
    func remove(_ id: String) async -> Bool
    func sendNow(_ id: String) async -> Bool
    func retry(_ id: String, using hook: Retry? = nil) async -> Bool
    func answer(_ question: LiveQuestion, options: [String], text: String? = nil) async -> Bool
    func decline(_ question: LiveQuestion) async -> Bool
    func error(for question: LiveQuestion) -> ChatActionError?
}

LiveChat.conversationMessages: [ChatMessage] // Excludes queued and removed; leaves chatMessages compatible.
LiveChat.queuedReplies: [LiveMessage] // Only user + queued, already in at order.
LiveChatModel.conversationMessages: [ChatMessage]
LiveMessage.deliveryState: ReplyDeliveryState // ACP pending/queued/delivering one tick; delivered two.

LiveQueuedReplies.init(controls: LiveChatControls, draft: Binding<String>, interrupts: Bool = false,
                       identifiers: @escaping (LiveMessage) -> QueuedReplyIdentifiers = { _ in .init() })
LiveReplyStatus.init(controls: LiveChatControls, messageID: String,
                     identifiers: ReplyStatusIdentifiers = .init(), retry: LiveChatControls.Retry? = nil)
LiveQuestionView.init(controls: LiveChatControls, identifiers: LiveQuestionIdentifiers = .init(),
                      choiceBehavior: LiveQuestionView.ChoiceBehavior = .automatic)
// LiveQuestionView.ChoiceBehavior: .automatic, .immediate
LiveQuestionIdentifiers.init(question: ThreadQuestionIdentifiers<String> = .init(), text: String? = nil,
                             submit: String? = nil, decline: String? = nil, error: String? = nil)
LiveScreenshotStrip.init(live: LiveChatModel, messageID: String,
                         identifiers: SentScreenshotIdentifiers = .init(), load: @escaping LiveAttachmentLoader)
typealias LiveAttachmentLoader = @Sendable (LiveAttachment) async -> Result<Data, ChatActionError>

QueuedReplyRow.init(text: String, status: String, error: ChatActionError? = nil,
                    interrupts: Bool = false, identifiers: QueuedReplyIdentifiers = .init(),
                    edit: @escaping () -> Void, remove: @escaping () -> Void, sendNow: (() -> Void)? = nil)
// .disabled(requestIsBusy) is inherited from the host/caller.
```

`QueuedReplyRow` is the small, stateless generic presenter extracted from `ThreadQueuedReplies`: text/status,
an optional `ChatActionError`, interrupt styling, the existing identifiers and Edit/Remove/optional Send now callbacks.
It inherits `.disabled` from its caller; neither an `isBusy` flag nor duplicate error/status flags are required. Both old
and live queue views use it, with full icon-and-word controls, native button styles and reflow. Minimum label heights
are 44pt on iOS and 28pt on Mac; native button padding can add to them. `SentReplyStatus` now renders optional actions
below ticks too, making pending Cancel available without suppressing the required tick. The additive
`ReplyStatusIdentifiers.error` identifies adapter request errors, and `ThreadQuestion.selected` adds the native
selected accessibility trait to live choices without changing existing single-answer hosts.

### FeedbackKit adopter example

Own `model`, `controls = LiveChatControls(live: model)`, the composer `draft` and a `SentScreenshotViewing` in the
host's conversation lifetime. Do not mirror LiveChat messages/queue or drive these adapters from a polling loop.

```swift
// ChatView's conversation input. Its equality shortcut draws extras only when hasExtras is set.
var messages: [ChatMessage] {
    model.conversationMessages.map { original in
        var projected = original
        if let live = model.chat.message(projected.id) {
            projected.hasExtras = live.kind == .user || !live.attachments.isEmpty
            if live.kind == .user, live.status != nil {
                projected.ticks = nil // The status adapter owns ticks, date, IDs and supported actions.
                projected.date = nil
            }
        }
        return projected
    }
}

// ChatView.extras, called for each projected message:
LiveReplyStatus(controls: controls, messageID: message.id, identifiers: statusIDs)
LiveScreenshotStrip(live: model, messageID: message.id, identifiers: screenshotIDs,
                    load: host.loadLiveAttachment)

// ChatView.footer:
LiveQuestionView(controls: controls, identifiers: .init(
    question: .init(question: "feedback-question", answer: { "feedback-answer-\($0)" }),
    text: "feedback-answer-text", submit: "feedback-answer-submit", decline: "feedback-answer-decline"
))
// WorkingLine reads model.chat.state?.working / activity, as DemoLiveScreen does.

// Above the host composer; FeedbackKit never queues, so this is naturally empty there.
LiveQueuedReplies(controls: controls, draft: $draft, identifiers: queueIDs)
// On the enclosing conversation:
// .presentsSentScreenshots(viewing)
// .task { await model.follow() } // Host also owns visibility/foreground cancellation.
```

Loader contract: the host receives the original `LiveAttachment` (URI/name/MIME/dimensions), resolves relative URI
against its ACP URL, applies its current authenticated fetch policy, and returns image Data or a safe
`ChatActionError`. Signed URLs, bearer values and raw paths must stay out of identifiers/logs/errors. The adapter
calls the loader only for `image/*`, retains unsupported/undecodable positions with empty slots, and passes the full
ordered slot array to `SentScreenshotStrip`. The ID key is the message ID and the index is its original attachment
index. Streamed metadata changes cancel/reload image presentation, without replacing message state. Local and shared
viewers preserve all configured thumbnail/viewer/Close IDs. The original Live demo reports an attachment-loader
unavailable message; the new deterministic live screenshot fixtures exercise real decoded bytes and both viewers.

Questions use `live.answer` / `live.decline`. Without free text, a single choice sends immediately; with free text,
select then type (or type alone) and Submit. Multiple selection is local presentation state, emitted in schema order.
The default `choiceBehavior: .automatic` follows the question schema; `.immediate` sends a single choice on tap,
including composed text. Multiple choices still require Submit. The original Live demo uses `.immediate` to retain
its established one-tap option interaction. `controls.answer(question, options:text:)` and `controls.decline(question)`
are separate APIs, sharing a private named response case; refused responses retain the question. Each new request identity resets selection/text; stale question callbacks are rejected. Request errors
are sanitized and scoped to the original question. No wire methods are invented.

### Live actions and request authority

Failed Retry defaults to `live.retry(id)` (force-only edit); the same id/clientRef returns to pending. Passing
`retry: host.retryFailedReply` overrides it. Pending/queued/failed Cancel/Remove use `live.remove`; delivering and
delivered Cancel is hidden. Queued Edit/Send now retain pending/queued guards and cannot accidentally retry a failed
reply. Edit restores only the current explicitly `.removed` message's words, even when the RPC reply was lost. It
reads the current host draft in its restore callback. A missing message in a capped snapshot is never confirmation.

Action completion reads authoritative state before reporting errors: newer delivery/removal suppresses an older
request failure. The error dictionary is a projection of request errors scoped to their unchanged actionable status;
there is no message/queue copy. The coordinator retains only busy/errors and small request metadata. Removed text
comes from LiveChat after the await, not from a cached reply or a pre-request copy.

### Authored coverage — NOT RUN on Cube03

- `Tests/AgentChatLiveTests/LiveControlsTests.swift`: retained projection/ticks/Send now/draft/question coverage;
  default failed Retry records force-only edit with unchanged message ID/clientRef and only one original prompt;
  failed/pending Remove records actual remove requests; failed Edit/Send now and delivered mutations issue no RPC;
  the optional host Retry override replaces the built-in request. Separate Decline tests cover HTTP refusal,
  retained question/error, then explicit resubmission with the original request ID.
- Deterministic request gates hold or lose POST replies while the real ACP stream keeps flowing: pending,
  delivering, delivered and removed updates supersede a lost Retry reply; a lost Remove reply plus explicit
  removed status restores the latest removed words into the current composer; later delivered status prevents
  restoration and stale errors; a request gated before transmission plus a capped 200-message snapshot cannot
  infer removal from absence. Existing failure presentation also disappears on later streamed delivery.
- The live-control test helper now waits for Observation notifications, with explicit request/response gates for
  in-flight assertions. It does not sleep or repeat actions until green. Tests have a suite time limit. The
  production model's reconnect/request timers remain unchanged. Original generic controller regressions are intact.
- `Demo/SharedUITests/LiveControlsUITests.swift`: both iPhone/Mac; default failed Retry -> pending -> delivered with
  unchanged visible ID/clientRef, failed Remove, pending Cancel, hidden delivered Cancel and explicit host override;
  automatic schema choice behavior plus immediate single-choice/text-on-tap. Existing queue sizes/actions,
  questions/selection reset, screenshot indexes, replacement loads and local/shared viewer interactions remain.
- Both-platform `testLiveLightRenderedPieces`, `testLiveDarkRenderedPieces`, `testLiveLargeRenderedPieces` author
  real XCUIScreen attachments for queue/status/single question/multiple question/text-only question/strip/viewer,
  using the existing `FixtureUITestCase.keep` infrastructure. Optional exported names remain
  `{ios,macos}-live-{queue,status,question-single,question-multiple,question-text,screenshots,viewer}-{light,dark,large}.png`,
  plus `ios-live-queue-large-lower.png`. These pictures have NOT been rendered or inspected in this step.
- Existing package tests, upstream Live tests, Extraction UI tests and both-platform Adoption/Mac suites are retained.
  SharedUITests is already included in both demo targets; this follow-up needs no package, project or workflow edits.

### Exact files changed in this follow-up

- `Sources/AgentChatLive/LiveChatControls.swift`
- `Sources/AgentChatLive/LiveQueuedReplies.swift`
- `Sources/AgentChatLive/LiveReplyStatus.swift`
- `Sources/AgentChatLive/LiveQuestionView.swift`
- `Sources/AgentChatKit/ThreadQueuedReplies.swift`
- `Tests/AgentChatLiveTests/LiveControlsTests.swift`
- `Demo/Sources/DemoLiveScreen.swift`
- `Demo/Sources/DemoLiveControlsFixture.swift`
- `Demo/SharedUITests/LiveControlsUITests.swift`
- `README.md`
- `Demo/ADOPTION.md`

### Parent handoff

The protocol Retry/failed Remove and Decline-status gaps are resolved upstream; the adapters use the updated model
APIs. The host screenshot loader contract above is unchanged: FeedbackKit supplies authenticated bytes, while the
kit retains the original attachment indexes and shared/local viewer identifiers.

Parent remote CI must compile/run all checks and inspect real light/dark/large captures on both platforms. This
follow-up ran **no builds, tests, simulators or Apple tools**; only source review and `git diff --check`. No wire,
parser, production transport/server, workflow, git-history, config/signing or other-repo edits were made. No messages
or Brain work were performed. Pre-existing `.claude/` and the separately appearing untracked `tmp/` were left alone.
Parent's output flag saves the final response.
