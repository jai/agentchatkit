import XCTest

/// AgentChatKit's main flows, driven through the demo app on a phone: a reply that streams after tool calls, delivery
/// ticks, "Wait, what?", the model chip, a screenshot sent with a message, a theme change, and the long chat's end.
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
