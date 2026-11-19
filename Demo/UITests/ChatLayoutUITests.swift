import XCTest

/// Where ChatView keeps the conversation on a phone: a short chat hangs from the reply box, the keyboard lifts the end
/// above the field, a reader scrolled up stays where they are when the keyboard opens, and a picture pasted into the
/// field is attached. These moved here from Agent Pager's UI tests: the behaviour is the kit's.
final class ChatLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(chat: String, pace: String = "fast") {
        app = XCUIApplication()
        app.launchArguments = ["-DemoChat", chat, "-DemoTheme", "prHub", "-DemoPace", pace]
        app.launch()
    }

    private var field: XCUIElement { app.textViews["sessionReplyField"] }

    private func element(containing words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    /// Waits for `condition`, polled by XCTest, rather than for a fixed time.
    private func waitUntil(_ what: String, timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: timeout), .completed, what)
    }

    /// Waits until the element has not moved for a quarter of a second: the list has settled.
    private func waitUntilStill(_ element: XCUIElement) {
        var last = element.frame
        var since = Date()
        waitUntil("\(element) settled") {
            let now = element.frame
            if now != last {
                last = now
                since = Date()
            }
            return Date().timeIntervalSince(since) > 0.25
        }
    }

    func testAShortChatHangsFromTheReplyBox() {
        launch(chat: "tour")
        let last = element(containing: "under anything I say")
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        waitUntilStill(last)
        XCTAssertFalse(app.buttons["chat-scroll-to-end"].exists, "the short chat is at its end")
        // Under the agent's newest words sits its "Wait, what?" row, and under that the composer: nothing in between.
        let waitWhat = app.buttons["wait-what"]
        XCTAssertTrue(waitWhat.exists)
        XCTAssertGreaterThanOrEqual(waitWhat.frame.minY, last.frame.maxY - 1, "Wait, what? is under the words")
        XCTAssertLessThanOrEqual(field.frame.minY - waitWhat.frame.maxY, 80, "and the chat hangs just over the composer")
    }

    func testTheKeyboardLiftsTheEndOfTheChatAboveTheField() {
        launch(chat: "long")
        let newest = element(containing: "Checked Wait, what?")
        XCTAssertTrue(newest.waitForExistence(timeout: 10))
        field.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        waitUntil("the end of the chat is above the field") {
            newest.isHittable && newest.frame.maxY <= self.field.frame.minY
        }
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY, "the field is above the keyboard")
    }

    func testTheKeyboardLeavesAReaderWhereTheyAre() {
        launch(chat: "long")
        XCTAssertTrue(element(containing: "Checked Wait, what?").waitForExistence(timeout: 10))
        let chat = app.scrollViews.firstMatch
        for _ in 0 ..< 3 {
            chat.swipeDown()
        }
        let toEnd = app.buttons["chat-scroll-to-end"]
        XCTAssertTrue(toEnd.waitForExistence(timeout: 5), "scrolled up, away from the end")
        let read = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Can you check'"))
            .allElementsBoundByIndex.first { $0.isHittable }
        let reading = try? XCTUnwrap(read, "a message on screen")
        guard let reading else { return }
        waitUntilStill(reading)
        let before = reading.frame.minY
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        waitUntilStill(reading)
        XCTAssertTrue(toEnd.exists, "the keyboard did not take the reader to the end")
        XCTAssertEqual(reading.frame.minY, before, accuracy: 2, "what he reads stays where it is")
    }

    func testAPicturePastedIntoTheFieldIsAttachedAndWordsPasteAsWords() {
        app = XCUIApplication()
        app.launchArguments = ["-DemoFixture", "composer-paste", "-DemoTheme", "paper"]
        app.launch()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        UIPasteboard.general.image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        field.tap()
        field.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "the field's menu offers Paste for a picture")
        paste.tap()
        XCTAssertTrue(app.descendants(matching: .any)["composerAttachment"].waitForExistence(timeout: 5),
                      "the picture is on the message")

        UIPasteboard.general.string = "Merge it."
        field.press(forDuration: 1.2)
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        waitUntil("words paste as words") { (self.field.value as? String) == "Merge it." }
    }
}
