import XCTest

/// Both iPhone and Mac: adapters consume a live ACP stream and operate the loopback host through real requests.
@MainActor
final class LiveControlsUITests: FixtureUITestCase {
    func testQueueEditRemoveSendNowAndStreamedDelivery() {
        launch("live-queue")
        let edit = app.buttons["live-edit-edit"]
        let remove = app.buttons["live-remove-edit"]
        let now = app.buttons["live-now-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        XCTAssertTrue(edit.label.contains("Edit"))
        XCTAssertTrue(remove.label.contains("Remove"))
        XCTAssertTrue(now.label.contains("Send now"))
        #if os(iOS)
        let minimum: CGFloat = 44
        #else
        let minimum: CGFloat = 28
        #endif
        for button in [edit, remove, now] { XCTAssertGreaterThanOrEqual(button.frame.height, minimum) }
        XCTAssertLessThan(element("live-queue-edit").frame.minY, element("live-queue-remove").frame.minY)
        wait(element("live-conversation"), "label == 'Conversation: '")
        activate(edit)
        wait(element("live-queue-edit"), "exists == false")
        XCTAssertEqual(app.textViews["live-draft"].value as? String, "Edit these words\n\nExisting draft")
        activate(app.buttons["live-remove-remove"])
        wait(element("live-queue-remove"), "exists == false")
        activate(app.buttons["live-now-now"])
        wait(element("live-queue-now"), "exists == false")
        XCTAssertTrue(element("live-sent-now").waitForExistence(timeout: 5))
        wait(element("live-conversation"), "label == 'Conversation: now'")
        wait(element("fixture-notice"), "label CONTAINS 'now=pending'")
        activate(app.buttons["live-deliver"])
        XCTAssertTrue(element("live-delivered-now").waitForExistence(timeout: 5))
        wait(element("live-sent-now"), "exists == false")
        wait(app.buttons["live-cancel-now"], "exists == false")
    }

    func testPendingCancelAndFailedHostRetry() {
        launch("live-status")
        XCTAssertTrue(element("live-sent-pending").waitForExistence(timeout: 10))
        XCTAssertTrue(element("live-delivered-delivered").exists)
        XCTAssertFalse(element("live-sent-failed").exists)
        XCTAssertFalse(app.buttons["live-cancel-failed"].exists)
        XCTAssertFalse(app.buttons["live-cancel-delivered"].exists)
        activate(app.buttons["live-cancel-pending"])
        wait(element("live-sent-pending"), "exists == false")
        wait(element("fixture-notice"), "label CONTAINS 'pending=removed'")
        activate(app.buttons["live-retry-failed"])
        XCTAssertTrue(element("live-delivered-failed").waitForExistence(timeout: 5))
        wait(app.buttons["live-retry-failed"], "exists == false")
        wait(element("fixture-notice"), "label CONTAINS 'Retry calls: 1'")
    }

    func testSingleChoiceMultipleChoiceWithTextFreeTextAndDecline() {
        launch("live-question-single")
        activate(app.buttons["live-answer-phone"])
        wait(element("live-answer-received"), "label == 'iPhone'")
        wait(app.buttons["live-answer-mac"], "exists == false")
        wait(element("live-working"), "label == 'Working'")

        launch("live-question-multiple")
        activate(app.buttons["live-answer-mac"])
        XCTAssertTrue(app.buttons["live-answer-mac"].isSelected)
        activate(app.buttons["live-answer-phone"])
        let field = element("live-answer-text")
        activate(field)
        field.typeText("Both devices")
        activate(app.buttons["live-submit"])
        wait(element("live-answer-received"), "label == 'iPhone, Mac: Both devices'")
        wait(app.buttons["live-submit"], "exists == false")

        launch("live-question")
        activate(app.buttons["live-answer-phone"])
        XCTAssertTrue(app.buttons["live-answer-phone"].isSelected)
        let singleText = element("live-answer-text")
        activate(singleText)
        singleText.typeText("Start here")
        activate(app.buttons["live-submit"])
        wait(element("live-answer-received"), "label == 'iPhone: Start here'")

        launch("live-question-text")
        XCTAssertTrue(app.buttons["live-submit"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["live-submit"].isEnabled)
        let text = element("live-answer-text")
        activate(text)
        text.typeText("Use the existing draft")
        activate(app.buttons["live-submit"])
        wait(element("live-answer-received"), "label == 'Use the existing draft'")

        launch("live-question-single")
        activate(app.buttons["live-decline"])
        wait(element("live-question"), "exists == false")
        XCTAssertFalse(element("live-answer-received").exists)
        wait(element("live-working"), "label == 'Working'")
    }

    func testNewStreamedQuestionResetsSelectionAndText() {
        launch("live-question-multiple")
        activate(app.buttons["live-answer-mac"])
        let field = element("live-answer-text")
        activate(field)
        field.typeText("Old answer")
        activate(app.buttons["live-replace-question"])
        wait(element("live-question"), "label == 'Choose again'")
        XCTAssertFalse(app.buttons["live-answer-mac"].isSelected)
        XCTAssertFalse(app.buttons["live-submit"].isEnabled)
        XCTAssertNotEqual(field.value as? String, "Old answer")
        activate(app.buttons["live-answer-phone"])
        activate(app.buttons["live-submit"])
        wait(element("live-answer-received"), "label == 'iPhone'")
    }

    func testLiveAttachmentsKeepOriginalIndexesAndSharedOrLocalViewerIDs() {
        for fixture in ["live-screenshots", "live-screenshots-local"] {
            launch(fixture)
            let picture = app.buttons["picture-pictures-2"]
            XCTAssertTrue(picture.waitForExistence(timeout: 10))
            XCTAssertEqual(picture.label, "Screenshot 3 of 4")
            XCTAssertTrue(app.buttons["picture-pictures-3"].exists)
            XCTAssertFalse(app.buttons["picture-pictures-0"].exists, "Unsupported text retains its index")
            XCTAssertFalse(app.buttons["picture-pictures-1"].exists, "Broken image retains its index")
            wait(element("fixture-notice"), "label CONTAINS 'Attachment loads: 3'")
            activate(picture)
            XCTAssertTrue(element("host-viewer").waitForExistence(timeout: 5))
            activate(app.buttons["viewer-close"])
            wait(element("host-viewer"), "exists == false")
            activate(app.buttons["live-replace-pictures"])
            XCTAssertTrue(app.buttons["picture-pictures-0"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["picture-pictures-0"].label, "Screenshot 1 of 1")
            wait(picture, "exists == false")
            wait(element("fixture-notice"), "label CONTAINS 'Attachment loads: 4'")
            activate(app.buttons["picture-pictures-0"])
            XCTAssertTrue(element("host-viewer").waitForExistence(timeout: 5))
            activate(app.buttons["viewer-close"])
        }
    }

    func testLiveLightRenderedPieces() throws { try capture("light") }
    func testLiveDarkRenderedPieces() throws { try capture("dark") }
    func testLiveLargeRenderedPieces() throws { try capture("large") }

    private func capture(_ appearance: String) throws {
        for (fixture, ready) in [("live-queue", "live-edit-edit"), ("live-status", "live-retry-failed"),
                                 ("live-question-single", "live-answer-phone"),
                                 ("live-question-multiple", "live-answer-phone"),
                                 ("live-question-text", "live-answer-text"),
                                 ("live-screenshots", "picture-pictures-2")] {
            launch(fixture, appearance: appearance)
            XCTAssertTrue(element(ready).waitForExistence(timeout: 10))
            if fixture == "live-question-multiple" { activate(app.buttons["live-answer-phone"]) }
            try keep("\(fixture)-\(appearance)")
            if fixture == "live-screenshots" {
                activate(app.buttons[ready])
                XCTAssertTrue(element("host-viewer").waitForExistence(timeout: 5))
                try keep("live-viewer-\(appearance)")
                activate(app.buttons["viewer-close"])
            }
            #if os(iOS)
            if fixture == "live-queue", appearance == "large" {
                app.swipeUp()
                try keep("live-queue-large-lower")
            }
            #endif
        }
    }
}
