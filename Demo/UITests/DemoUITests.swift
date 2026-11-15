import XCTest

/// AgentChatKit's main flows, driven through the demo app on a phone: a reply that streams after tool calls, delivery
/// ticks, "Wait, what?", the model chip, a screenshot sent with a message, a theme change, the long chat's end, and the
/// Live chat reconnecting.
final class DemoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(chat: String, theme: String = "prHub", pace: String = "fast") {
        app = XCUIApplication()
        app.launchArguments = ["-DemoChat", chat, "-DemoTheme", theme, "-DemoPace", pace]
        app.launch()
    }

    private var field: XCUIElement { app.textViews["sessionReplyField"] }

    private func element(containing words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    private func send(_ words: String) {
        field.tap()
        field.typeText(words)
        app.buttons["sessionReplySend"].tap()
    }

    private func waitFor(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 15) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "No \(what)")
    }

    /// The reply finished: "Wait, what?" is back under the agent's newest words.
    private func waitForAnswer() {
        waitFor(app.buttons["wait-what"], "Wait, what? after the answer", timeout: 30)
    }

    func testMainFlows() {
        launch(chat: "tour")
        waitFor(element(containing: "scripted agent"), "greeting")

        // A question: delivered, tool calls as quiet rows, then a streamed Markdown answer.
        send("How does ChatView work?")
        waitFor(app.descendants(matching: .any)["reply-ticks-2"], "delivered ticks")
        waitFor(element(containing: "ChatView.swift"), "tool call row")
        waitFor(element(containing: "whole chat screen"), "streamed answer")
        waitForAnswer()

        // "Wait, what?": his bubble says it, and the agent says the same thing plainly.
        app.buttons["wait-what"].tap()
        waitFor(app.staticTexts["Wait, what?"], "Wait, what? bubble")
        waitFor(element(containing: "The short version"), "plain rewrite")
        waitForAnswer()

        // The model chip: a pick shows once the host holds it, and the next answer names the model.
        let chip = app.buttons["modelReasoningChip"]
        XCTAssertTrue(chip.label.contains("Opus 5.5 · high"), chip.label)
        chip.tap()
        app.buttons["Claude Haiku 5.5"].tap()
        waitFor(app.buttons.matching(NSPredicate(format: "label == %@", "Model and reasoning: Haiku 5.5")).firstMatch,
                "chip on Haiku without a reasoning level")
        send("Which model are you?")
        waitFor(element(containing: "answering as Claude Haiku 5.5"), "model in the answer")
        waitForAnswer()

        // A screenshot from the toolbar, sent with words: the bubble says it went, and the agent looks at it.
        app.buttons["demo-sample-screenshot"].tap()
        send("Here is the failing build")
        waitFor(element(containing: "Screenshot attached"), "screenshot line in his bubble")
        waitFor(element(containing: "Got the screenshot"), "answer about the screenshot")
        waitForAnswer()

        // Another look: the chat redraws in the Terminal theme and still works.
        app.buttons["demo-theme"].tap()
        app.buttons["Terminal"].tap()
        send("How do themes work?")
        waitFor(element(containing: "fonts, colours and icons"), "answer in the Terminal theme")
        waitForAnswer()
    }

    func testLongChatFollowsTheEnd() {
        launch(chat: "long")
        // It opens at its end.
        let newest = element(containing: "Checked Wait, what?")
        waitFor(newest, "the newest message")
        XCTAssertTrue(newest.isHittable, "The long chat did not open at its end")

        // A long answer streams in, and the page follows it to its last part.
        send("Write something long about scrolling")
        waitForAnswer()
        let lastPart = element(containing: "Part 14.")
        waitFor(lastPart, "the long answer's last part")
        XCTAssertTrue(lastPart.isHittable, "The chat stopped following the answer")
    }

    /// The Live chat (AgentChatLive over ACP, on the in-memory host): an answer arrives as it is written; a dropped
    /// stream resumes from its cursor; offline, the agent keeps writing and the chat catches up once back, nothing
    /// twice; the agent's question is answered with a tap.
    func testLiveChatReconnects() {
        launch(chat: "live")
        waitFor(element(containing: "This chat is"), "live greeting")
        let status = app.descendants(matching: .any)["demo-live-status"]
        waitFor(status, "stream status")
        let streaming = { (count: Int) in
            self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'demo-live-status' AND label CONTAINS %@", "stream \(count)"))
                .firstMatch
        }
        waitFor(streaming(1), "the first stream")

        send("How does ChatView work?")
        waitFor(app.descendants(matching: .any)["reply-ticks-2"], "delivered ticks")
        app.buttons["demo-live-drop"].tap()
        waitFor(streaming(2), "a new stream after the drop")
        waitFor(element(containing: "whole chat screen"), "the answer, finished after the drop", timeout: 30)

        send("How do themes work?")
        app.buttons["demo-live-network"].tap()
        waitFor(element(containing: "Offline"), "offline status")
        waitFor(app.buttons["demo-live-network"], "network switch")
        sleep(3)
        app.buttons["demo-live-network"].tap()
        waitFor(element(containing: "fonts, colours and icons"), "the answer written while offline", timeout: 30)
        waitFor(streaming(3), "a new stream once back online")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "How do themes work?")).count, 1,
                       "A message showed twice after reconnecting")

        // The agent asks before it merges (elicitation/create); a tap answers, and the answer shows as his message.
        send("Merge it")
        waitFor(app.descendants(matching: .any)["demo-live-question"], "the agent's question")
        app.buttons["demo-live-option-merge"].tap()
        waitFor(app.staticTexts["Merge now"], "the answer as his message")
        waitFor(element(containing: "Merged, and tagged"), "the agent going on after the answer")
    }

    /// The README's pictures, with the agent slowed down to catch it at work. Kept as attachments on the result.
    func testReadmeScreenshots() {
        launch(chat: "tour", pace: "slow")
        send("How does ChatView work?")
        dismissKeyboard()
        waitForAnswer()
        app.buttons["demo-sample-screenshot"].tap()
        send("Here is the failing build")
        dismissKeyboard()
        waitFor(element(containing: "screenshot-1.jpg"), "tool call row", timeout: 30)
        waitFor(element(containing: "Got the screenshot"), "the answer starting")
        XCTAssertTrue(app.descendants(matching: .any)["demo-activity"].exists, "The working line went before the shot")
        keep("working")
        waitForAnswer()

        app.buttons["demo-theme"].tap()
        app.buttons["Terminal"].tap()
        send("Show me the Markdown")
        dismissKeyboard()
        waitForAnswer()
        keep("terminal-markdown")

        app.buttons["demo-theme"].tap()
        app.buttons["Paper"].tap()
        app.buttons["wait-what"].tap()
        waitForAnswer()
        keep("paper-wait-what")
    }

    /// A tap in the chat puts the keyboard away, as on the phone.
    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        }
    }

    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
