import XCTest

/// Press and hold the send button: "Send now" comes up with the keyboard still there, and it and the plain tap each
/// send (Agent Pager, Jai 2026-11-24: the keyboard went away as the menu came up).
final class ComposerSendNowUITests: FixtureUITestCase {
    private var field: XCUIElement { app.textViews["sessionReplyField"] }
    private var send: XCUIElement { app.buttons["sessionReplySend"] }

    private func type(_ words: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(words)
    }

    func testHoldingSendKeepsTheKeyboardUpAndSendsNow() throws {
        launch("composer-send-now")
        type("Stop and look")
        let place = field.frame
        send.press(forDuration: 1.2)
        let sendNow = app.buttons["Send now"]
        XCTAssertTrue(sendNow.waitForExistence(timeout: 5), "the menu")
        try keep("send-now-menu")
        // The system folds the keyboard's row of suggestions away while a menu is up, so the field settles that much
        // lower; with the keyboard gone it dropped 300 pt. The keyboard still "exists" as it goes, so its place says.
        XCTAssertEqual(field.frame.minY, place.minY, accuracy: 60, "the field stays over the keyboard")
        sendNow.tap()
        notice("Sent now: Stop and look")
        field.typeText("Next")
        send.tap()
        notice("Sent: Next")
    }

    func testClosingTheMenuKeepsTheKeyboardUpAndSendsNothing() {
        launch("composer-send-now")
        type("Stop and look")
        send.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Send now"].waitForExistence(timeout: 5), "the menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25)).tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Send now"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        notice("Nothing sent")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays after the menu closes")
    }

    func testAnEmptyBoxSendsNothing() {
        launch("composer-send-now")
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertFalse(send.isEnabled)
    }
}
