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
        XCTAssertFalse(app.buttons["chat-scroll-to-end"].exists, "Scroll to the newest shown at the end")

        // Scrolled up it, one tap goes back to the newest words, and the button goes.
        let chat = app.scrollViews.firstMatch
        for _ in 0 ..< 3 {
            chat.swipeDown()
        }
        let toEnd = app.buttons["chat-scroll-to-end"]
        waitFor(toEnd, "Scroll to the newest, scrolled up")
        XCTAssertFalse(newest.isHittable, "The chat did not scroll up")
        toEnd.tap()
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: newest)
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 5), .completed, "Scroll to the newest did not reach the end")
        XCTAssertTrue(toEnd.waitForNonExistence(timeout: 5), "Scroll to the newest stayed at the end")

        // A long answer streams in, and the page follows it to its last part.
        send("Write something long about scrolling")
        waitForAnswer()
        let lastPart = element(containing: "Part 14.")
        waitFor(lastPart, "the long answer's last part")
        XCTAssertTrue(lastPart.isHittable, "The chat stopped following the answer")
    }

    /// The Live chat on the server package's real host (`node server/dev/host.ts --port 8788`, which CI starts):
    /// an answer arrives as it is written; a dropped stream resumes from its cursor; a restarted host is initialized
    /// again; offline, the agent keeps writing and the chat catches up once back, nothing twice; the agent's question
    /// is answered with a tap. Each reconnect's time is kept on the result.
    func testLiveChatReconnects() {
        app = XCUIApplication()
        app.launchArguments = ["-DemoChat", "live", "-DemoSession", "live-\(UUID().uuidString.prefix(8))",
                               "-DemoServer", ProcessInfo.processInfo.environment["DEMO_SERVER"] ?? "http://127.0.0.1:8788"]
        app.launch()
        waitFor(element(containing: "real ACP host"), "the host's greeting")
        let streaming = { (count: Int) in
            self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'demo-live-status' AND label CONTAINS %@", "stream \(count) ·"))
                .firstMatch
        }
        let status = app.descendants(matching: .any)["demo-live-status"]
        waitFor(streaming(1), "the first stream")
        keepText("connect", status.label)

        send("How does ChatView work?")
        waitFor(app.descendants(matching: .any)["reply-ticks-2"], "delivered ticks")
        waitFor(element(containing: "came over ACP"), "the answer, streamed from the host")

        app.buttons["demo-live-drop"].tap()
        waitFor(streaming(2), "a new stream after the drop")
        keepText("after a dropped stream", status.label)

        app.buttons["demo-live-restart"].tap()
        waitFor(streaming(3), "a new connection after the host restarted")
        keepText("after the host restarted", status.label)

        send("Tell me again")
        waitFor(app.staticTexts["Tell me again"], "the message, taken by the host before the network goes")
        app.buttons["demo-live-network"].tap()
        waitFor(element(containing: "Offline"), "offline status")
        sleep(3)
        app.buttons["demo-live-network"].tap()
        waitFor(streaming(4), "a new stream once back online", timeout: 30)
        for words in ["How does ChatView work?", "Tell me again"] {
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", words)).count, 1,
                           "\(words) showed twice after reconnecting")
        }

        send("Merge it")
        waitFor(app.descendants(matching: .any)["demo-live-question"], "the host's question")
        app.buttons["demo-live-option-merge"].tap()
        waitFor(element(containing: "Merged, and tagged"), "the agent going on after the answer")
        keep("real-host")
    }

    private func keepText(_ name: String, _ text: String) {
        let note = XCTAttachment(string: text)
        note.name = name
        note.lifetime = .keepAlways
        add(note)
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
