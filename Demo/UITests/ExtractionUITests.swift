import XCTest

/// Shared controls exercised through host fixtures. No network, accounts or app-specific delivery services.
@MainActor
final class ExtractionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() { continueAfterFailure = false }

    private func launch(_ flow: String) {
        app = XCUIApplication()
        app.launchArguments = ["-DemoChat", "extraction", "-DemoTheme", "paper"]
        app.launch()
        let link = app.buttons[flow].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.navigationBars[flow].waitForExistence(timeout: 5))
        picture(flow.replacingOccurrences(of: " ", with: "-"))
    }

    private func picture(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["CHATDEMO_SCREENSHOTS"] else { return }
        do {
            try XCUIScreen.main.screenshot().pngRepresentation.write(
                to: URL(fileURLWithPath: folder).appending(path: "\(name).png")
            )
        } catch {
            XCTFail("Could not keep the rendered shared component: \(error)")
        }
    }

    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func notice(_ text: String) {
        let showing = app.staticTexts.matching(NSPredicate(
            format: "identifier == 'fixture-notice' AND label == %@", text)).firstMatch
        XCTAssertTrue(showing.waitForExistence(timeout: 5), "fixture-notice never showed \(text)")
    }

    private func thread(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["fixture-thread-\(id)"].firstMatch
    }

    private func queue(_ words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "queued-reply")
            .containing(.staticText, identifier: words).firstMatch
    }

    func testArchiveAndDeleteInvokeHostOnlyAfterConfirmationAndCancelDoesNothing() {
        launch("Thread list")
        let archive = thread("archive")
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.press(forDuration: 1)
        app.buttons["Archive"].tap()
        notice("Archive calls: 1, Delete calls: 0")
        wait(archive, "exists == false")

        let delete = thread("delete")
        delete.press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.cancelConfirmation()
        notice("Archive calls: 1, Delete calls: 0")
        XCTAssertTrue(delete.exists)

        delete.press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.sheets.buttons["Delete"].firstMatch.tap() // iOS 26 lists a dialog's buttons twice
        notice("Archive calls: 1, Delete calls: 1")
        wait(delete, "exists == false")
        // No Archive/Delete hook means no corresponding action control.
        thread("read-only").press(forDuration: 1)
        XCTAssertFalse(app.buttons["Archive"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        // With no hooks there is no menu, so the press opens the host destination as a tap does.
        XCTAssertTrue(app.staticTexts["Opened Read-only fixture"].waitForExistence(timeout: 3))
    }

    func testThreadActionFailureKeepsRowAndShowsHostError() {
        launch("Thread list")
        app.flipSwitch("Fail next action")
        thread("archive").press(forDuration: 1)
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts["Fixture archive failed"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].firstMatch.tap()
        XCTAssertTrue(thread("archive").exists)
        thread("archive").press(forDuration: 1)
        app.buttons["Archive"].tap()
        notice("Archive calls: 2, Delete calls: 0")
        wait(thread("archive"), "exists == false")
        app.flipSwitch("Fail next action")
        thread("delete").press(forDuration: 1)
        app.buttons["Delete"].tap()
        app.sheets.buttons["Delete"].firstMatch.tap() // iOS 26 lists a dialog's buttons twice
        XCTAssertTrue(app.staticTexts["Fixture delete failed"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].firstMatch.tap()
        XCTAssertTrue(thread("delete").exists)
        notice("Archive calls: 2, Delete calls: 1")
    }

    func testQueueOrderEditFailureSuccessRemoveAndSendNow() {
        launch("Reply queue")
        let edit = queue("Queue edit")
        let remove = queue("Queue remove")
        let now = queue("Queue now")
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertLessThan(edit.frame.minY, remove.frame.minY)
        XCTAssertLessThan(remove.frame.minY, now.frame.minY)

        app.flipSwitch("Fail next action")
        edit.buttons["Edit"].tap()
        XCTAssertFalse(edit.buttons["Edit"].isEnabled)
        XCTAssertFalse(edit.buttons["Remove"].isEnabled)
        XCTAssertFalse(edit.buttons["Send now · stops its turn"].isEnabled)
        XCTAssertTrue(app.staticTexts["The thread took it before that reached it."].waitForExistence(timeout: 5))
        let draft = app.textViews["fixture-queue-draft"]
        XCTAssertEqual(draft.value as? String, "Existing draft")
        edit.buttons["Edit"].tap()
        wait(edit, "exists == false")
        XCTAssertEqual(draft.value as? String, "Queue edit\n\nExisting draft")

        remove.buttons["Remove"].tap()
        wait(remove, "exists == false")
        now.buttons["Send now · stops its turn"].tap()
        wait(now, "exists == false")
        notice("Remove calls: 3, Send now calls: 1")
    }

    func testComposerIntentSendsNowOnceAcrossRepeatedQueueSnapshots() {
        launch("Reply queue")
        app.buttons["Queue with Send now intent"].tap()
        notice("Remove calls: 0, Send now calls: 1")
        wait(queue("Queue once"), "exists == false")
        app.buttons["Refresh queued snapshot"].tap()
        XCTAssertTrue(queue("Queue once").waitForExistence(timeout: 3))
        app.buttons["Refresh queued snapshot"].tap()
        notice("Remove calls: 0, Send now calls: 1")
    }

    func testDeliveryTicksRetryDisablesAndCancelCallsTheHost() {
        launch("Delivery status")
        XCTAssertTrue(app.descendants(matching: .any)["reply-ticks-1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["reply-ticks-2"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["reply-status"].exists)
        app.buttons["Retry"].tap()
        XCTAssertFalse(app.buttons["Retry"].isEnabled)
        XCTAssertFalse(app.buttons["Cancel"].isEnabled)
        notice("Retry calls: 1, Cancel calls: 0")
        wait(app.buttons["Retry"], "exists == false")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "reply-ticks-2").count, 2)
        app.buttons["Reset delivery"].tap()
        app.buttons["Cancel"].tap()
        notice("Retry calls: 1, Cancel calls: 1")
        XCTAssertTrue(app.staticTexts["Cancelled"].exists)
        XCTAssertFalse(app.buttons["Retry"].exists)
    }

    func testQuestionEqualAnswersAndAllCallbacksRespectSending() {
        launch("Question")
        let phone = app.buttons["Phone"]
        let mac = app.buttons["Mac"]
        XCTAssertTrue(phone.waitForExistence(timeout: 3))
        XCTAssertEqual(phone.frame.width, mac.frame.width, accuracy: 1)
        app.switches["Hold sending"].tap()
        for button in [phone, mac, app.buttons["Reply"], app.buttons["wait-what"]] {
            XCTAssertFalse(button.isEnabled)
        }
        app.switches["Hold sending"].tap()
        phone.tap()
        notice("Answer: phone")
        wait(mac, "enabled == true")
        mac.tap()
        notice("Answer: mac")
        wait(app.buttons["Reply"], "enabled == true")
        app.buttons["Reply"].tap()
        notice("Reply opened")
        wait(app.buttons["wait-what"], "enabled == true")
        app.buttons["wait-what"].tap()
        wait(app.staticTexts["fixture-notice"], "label BEGINSWITH 'Wait, what? Rewrite your last reply'")
    }

    func testLongAnswersStackAtEqualWidth() {
        launch("Question")
        app.switches["Long answers"].tap()
        let phone = app.buttons["Run the complete phone fixture and review every screenshot"]
        let mac = app.buttons["Run the complete Mac fixture and review every screenshot"]
        XCTAssertTrue(phone.waitForExistence(timeout: 3))
        XCTAssertEqual(phone.frame.width, mac.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(mac.frame.minY, phone.frame.maxY)
    }

    func testSentScreenshotOrderViewerCloseAndSwipeDown() {
        launch("Sent screenshots")
        let pictures = app.buttons.matching(identifier: "sent-screenshot")
        XCTAssertTrue(pictures.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(pictures.count, 2)
        XCTAssertEqual(pictures.element(boundBy: 0).label, "Screenshot 1 of 2")
        XCTAssertEqual(pictures.element(boundBy: 1).label, "Screenshot 2 of 2")
        pictures.element(boundBy: 1).tap()
        let viewer = app.images["sent-screenshot-viewer"]
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))
        picture("sent-screenshot-viewer")
        app.buttons["sent-screenshot-viewer-close"].tap()
        wait(viewer, "exists == false")
        pictures.firstMatch.tap()
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))
        viewer.swipeDown()
        wait(viewer, "exists == false")
    }
}
