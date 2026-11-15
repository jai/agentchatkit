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
