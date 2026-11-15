import XCTest

/// Runs on both platforms. Existing ExtractionUITests and the main iPhone demo suite remain separate.
@MainActor
final class AdoptionUITests: FixtureUITestCase {
    func testLightRenderedPieces() throws { try capturePieces("light") }
    func testDarkRenderedPieces() throws { try capturePieces("dark") }
    func testLargeTextRenderedPieces() throws { try capturePieces("large") }

    private func capturePieces(_ appearance: String) throws {
        let fixtures = [("row", "title-context"), ("threads", "sessionRow-archive"),
                        ("host-threads", "sessionRow-alpha"), ("queue", "edit-edit"),
                        ("delivery", "finder-message-retry"), ("question", "answer-phone"),
                        ("screenshots", "picture-fixture-pictures-0")]
        for (fixture, ready) in fixtures {
            launch(fixture, appearance: appearance)
            XCTAssertTrue(element(ready).waitForExistence(timeout: 10))
            try keep("\(fixture)-\(appearance)")
            if fixture == "screenshots" {
                activate(app.buttons[ready])
                XCTAssertTrue(element("host-viewer").waitForExistence(timeout: 5))
                try keep("viewer-\(appearance)")
                activate(app.buttons["viewer-close"])
                wait(element("host-viewer"), "exists == false")
            }
            #if os(iOS)
            // Keep the remaining queue rows and controls at accessibility text sizes too.
            if ["queue", "row"].contains(fixture), appearance == "large" {
                app.swipeUp()
                try keep("\(fixture)-large-lower")
            }
            #endif
        }
    }

    func testContextStatusTitleMarkAndSlotIDsUseHostTypography() {
        launch("row")
        let context = element("context-context")
        let status = element("slot-status-context")
        let title = element("title-context")
        let mark = element("mark-context")
        let about = element("about-context")
        let chip = element("slot-chip-context")
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertTrue(element("thread-line").exists)
        XCTAssertTrue(status.exists, "Nil slot ID configuration must preserve the host status ID")
        XCTAssertTrue(chip.exists, "Nil slot ID configuration must preserve the host chip ID")
        // Both meta texts share a font, so equal top edges are the first-baseline layout's observable geometry.
        XCTAssertEqual(status.frame.minY, context.frame.minY, accuracy: 3)
        XCTAssertGreaterThan(status.frame.minX, context.frame.minX)
        XCTAssertGreaterThanOrEqual(title.frame.minY, context.frame.maxY)
        XCTAssertLessThan(mark.frame.midX, title.frame.minX)
        XCTAssertGreaterThanOrEqual(about.frame.minY, title.frame.maxY)
        XCTAssertGreaterThanOrEqual(chip.frame.minY, about.frame.maxY)
        let fallbackTitle = element("title-fallback")
        let fallbackStatus = element("configured-status-fallback")
        XCTAssertTrue(fallbackTitle.exists)
        XCTAssertTrue(element("configured-chip-fallback").exists)
        XCTAssertGreaterThanOrEqual(fallbackStatus.frame.minY, fallbackTitle.frame.minY)
        XCTAssertLessThan(fallbackStatus.frame.minY, fallbackTitle.frame.maxY)
        let hostBodyHeight = about.frame.height
        let hostTitleHeight = title.frame.height
        launch("row", legacyTypography: true)
        XCTAssertTrue(element("about-context").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(hostBodyHeight, element("about-context").frame.height,
                             "Host body line spacing/leading must reach the shared About text")
        XCTAssertGreaterThan(hostTitleHeight, element("title-context").frame.height)
    }

    func testCustomDeliveryAndQuestionControlIDs() {
        launch("delivery")
        XCTAssertTrue(element("host-sent").waitForExistence(timeout: 5))
        XCTAssertTrue(element("host-delivered").exists)
        XCTAssertTrue(element("host-reply-status").exists)
        activate(app.buttons["finder-message-retry"])
        notice("Retry calls: 1, Cancel calls: 0")
        wait(app.buttons["finder-message-retry"], "exists == false")
        activate(app.buttons["Reset delivery"])
        activate(app.buttons["finder-message-cancel"])
        notice("Retry calls: 1, Cancel calls: 1")

        launch("question")
        XCTAssertTrue(element("host-question").waitForExistence(timeout: 5))
        XCTAssertTrue(element("host-question-context").exists)
        toggle("Hold sending")
        for id in ["answer-phone", "answer-mac", "host-reply", "host-wait-what"] {
            XCTAssertFalse(app.buttons[id].isEnabled)
        }
        toggle("Hold sending")
        activate(app.buttons["answer-phone"])
        notice("Answer: phone")
        wait(app.buttons["answer-mac"], "enabled == true")
        activate(app.buttons["answer-mac"])
        notice("Answer: mac")
        wait(app.buttons["host-reply"], "enabled == true")
        activate(app.buttons["host-reply"])
        notice("Reply opened")
        wait(app.buttons["host-wait-what"], "enabled == true")
        activate(app.buttons["host-wait-what"])
        wait(element("fixture-notice"), "label BEGINSWITH 'Wait, what? Rewrite your last reply'")
    }

    func testQueueCustomIDsFullLabelsAndHostActions() {
        launch("queue")
        let edit = app.buttons["edit-edit"]
        let remove = app.buttons["remove-edit"]
        let send = app.buttons["send-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.label.contains("Edit"))
        XCTAssertTrue(remove.label.contains("Remove"))
        XCTAssertTrue(send.label.contains("Send now"))
        XCTAssertGreaterThanOrEqual(edit.frame.height, 28)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 28)
        XCTAssertGreaterThanOrEqual(send.frame.height, 28)
        XCTAssertLessThan(edit.frame.minX, remove.frame.minX)
        XCTAssertGreaterThanOrEqual(send.frame.maxX, remove.frame.maxX)
        XCTAssertTrue(element("queue-text-edit").exists)
        XCTAssertTrue(element("queue-status-edit").exists)
        activate(edit)
        wait(element("queue-edit"), "exists == false")
        XCTAssertEqual(app.textViews["fixture-queue-draft"].value as? String, "Queue edit\n\nExisting draft")
        activate(app.buttons["remove-remove"])
        wait(element("queue-remove"), "exists == false")
        activate(app.buttons["send-now"])
        wait(element("queue-now"), "exists == false")
        notice("Remove calls: 2, Send now calls: 1")
    }

    func testScreenshotCustomIDsReachSharedAndLocalPresentations() {
        for fixture in ["screenshots", "screenshots-local"] {
            launch(fixture)
            activate(app.buttons["picture-fixture-pictures-1"])
            XCTAssertTrue(element("host-viewer").waitForExistence(timeout: 5))
            activate(app.buttons["viewer-close"])
            wait(element("host-viewer"), "exists == false")
        }
    }

    func testHostStringRoutesAndHeaderFooterRemainOwnedByHost() {
        launch("host-routes")
        XCTAssertTrue(element("host-new").waitForExistence(timeout: 5))
        XCTAssertTrue(element("host-footer").exists)
        activate(element("sessionRow-alpha"))
        wait(element("host-route"), "label == 'Host route: host:alpha'")
    }

    #if os(iOS)
    func testPhoneSwipeAndLongPressUseSameHostHooksAndCustomConfirmIDs() {
        launch("host-threads")
        let alpha = element("sessionRow-alpha")
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        alpha.swipeLeft()
        activate(app.buttons["delete-alpha"])
        activate(app.buttons["cancel-alpha"])
        notice("Archive calls: 0, Delete calls: 0")
        alpha.press(forDuration: 1)
        activate(app.buttons["delete-alpha"])
        activate(app.buttons["confirm-alpha"])
        wait(alpha, "exists == false")
        notice("Archive calls: 0, Delete calls: 1")
        element("sessionRow-beta").swipeLeft()
        activate(app.buttons["archive-beta"])
        wait(element("sessionRow-beta"), "exists == false")
        notice("Archive calls: 1, Delete calls: 1")
        element("sessionRow-read-only").swipeLeft()
        XCTAssertFalse(app.buttons["archive-read-only"].exists)
        XCTAssertFalse(app.buttons["delete-read-only"].exists)
    }
    #endif
}
