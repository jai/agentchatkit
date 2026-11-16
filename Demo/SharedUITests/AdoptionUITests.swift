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

    func testHostMenuItemsRemainBesideArchiveAndDelete() {
        launch("host-threads")
        let row = element("sessionRow-alpha")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        #if os(macOS)
        row.rightClick()
        #else
        row.press(forDuration: 1)
        #endif
        XCTAssertTrue(element("archive-alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(element("delete-alpha").exists)
        activate(element("host-open-alpha"))
        wait(element("host-open"), "label == 'Opened: alpha, Open calls: 1'")
        XCTAssertTrue(row.exists)
        notice("Archive calls: 0, Delete calls: 0")
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
        #if os(iOS)
        let minimumHeight: CGFloat = 44
        #else
        let minimumHeight: CGFloat = 28
        #endif
        XCTAssertGreaterThanOrEqual(edit.frame.height, minimumHeight)
        XCTAssertGreaterThanOrEqual(remove.frame.height, minimumHeight)
        XCTAssertGreaterThanOrEqual(send.frame.height, minimumHeight)
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

    /// Portrait screenshots that load as the conversation scrolls to its end: each thumbnail is found where it is
    /// drawn, at its drawn size, as soon as it shows, and one click opens the viewer (jai/agentchatkit#6).
    func testConversationScreenshotFramesAreWhereTheyAreDrawn() {
        launch("screenshots-conversation")
        let picture = app.buttons["picture-conversation-1"]
        XCTAssertTrue(picture.waitForExistence(timeout: 5))
        let frame = picture.frame
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(frame.width, 64, accuracy: 1, "\(frame)")
        XCTAssertEqual(frame.height, 64, accuracy: 1, "\(frame)")
        XCTAssertTrue(window.contains(frame), "thumbnail \(frame) outside window \(window)")
        // The strip keeps its row while it loads, so the page does not grow past its end: the thumbnail is clear of
        // the reply bar (#7).
        #if os(macOS)
        let field = app.textFields["sessionReplyField"]
        #else
        let field = app.textViews["sessionReplyField"]
        #endif
        XCTAssertLessThanOrEqual(frame.maxY, field.frame.minY, "\(frame)")
        activate(picture)
        XCTAssertTrue(element("host-viewer").waitForExistence(timeout: 5))
        activate(app.buttons["viewer-close"])
        wait(element("host-viewer"), "exists == false")
    }

    /// The host draws the answers it claims inside the kit's bubbles (a link card, a meal card) and its own state
    /// shows in them; the rest stay the kit's Markdown (jai/agentchatkit#11). Each message is found by its identifier
    /// (#12).
    func testHostDrawsClaimedMessagesInsideTheBubble() {
        launch("message-content")
        XCTAssertTrue(app.buttons["card-link-pr12"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("card-meal-figures").exists)
        func words(_ text: String) -> Int {
            let shown = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
            return app.staticTexts.matching(shown).count + app.textViews.matching(shown).count
        }
        XCTAssertEqual(words("RAW"), 0, "A claimed message's words are not drawn")
        XCTAssertGreaterThan(words("Markdown"), 0, "An unclaimed answer is still the kit's Markdown")
        // Every message is one element, found by its side and id (#12).
        XCTAssertTrue(element("chat-message-you-ask").exists)
        XCTAssertTrue(element("chat-message-agent-plain").exists)
        XCTAssertTrue(element("chat-message-agent-links").buttons["card-link-pr12"].exists)
        let agents = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'chat-message-agent-'"))
        XCTAssertEqual(agents.count, 3)
        // The agent at work, the kit's line under the messages (#13).
        wait(element("chat-working"), "label CONTAINS 'Searching threads…'")
        XCTAssertFalse(element("chat-working").label.contains("……"), "A second ellipsis (#20)")
        // A card gives its own words to VoiceOver; the link card keeps its own long press, no bubble menu (#20).
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(
            format: "label == 'Lunch, 640 kilocalories'")).firstMatch.exists)
        activate(app.buttons["card-link-pr12"])
        wait(element("fixture-notice"), "label CONTAINS 'Opened: PR #12;'")
        #if os(iOS)
        // With the bubble's menu left out, a long press is the card's own: no Copy menu, and the card acts.
        app.buttons["card-link-pr12"].press(forDuration: 1)
        XCTAssertFalse(app.buttons["Copy"].waitForExistence(timeout: 2), "The bubble's menu wrapped the link card")
        wait(element("fixture-notice"), "label CONTAINS 'Opened: PR #12, PR #12;'")
        #endif
        activate(app.buttons["card-log"])
        wait(element("fixture-notice"), "label CONTAINS 'Logged: 1'")
        wait(app.buttons["card-log"], "label == 'Logged'")
    }

    /// Tap and hold (a right click on a Mac) a long agent reply: Summarize writes a short summary under it, which
    /// closes with its button (jai/agentchatkit#2).
    func testSummarizeALongReply() {
        launch("reply-summary")
        openMenu(words("CI on main"))
        activate(summarizeItem)
        wait(element("bubble-summary"), "exists == true")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Short version' OR value BEGINSWITH 'Short version'")).firstMatch
            .waitForExistence(timeout: 5))
        activate(app.buttons["bubble-summary-dismiss"])
        wait(element("bubble-summary"), "exists == false")
    }

    /// No Summarize on a short reply, nor in a host that turned summaries off.
    func testNoSummarizeOnAShortReplyOrWhenOff() {
        for (fixture, message) in [("reply-summary", "Done."), ("reply-summary-off", "CI on main")] {
            launch(fixture)
            openMenu(words(message))
            XCTAssertTrue(copyItem.waitForExistence(timeout: 5), "The menu did not open")
            XCTAssertFalse(summarizeItem.exists, "Summarize offered on \(message) in \(fixture)")
        }
    }

    private func openMenu(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        #if os(macOS)
        // The words select on a Mac, and a right click on them is the text's own menu: click the bubble's margin.
        element.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -6, dy: 6)).rightClick()
        #else
        element.press(forDuration: 1)
        #endif
    }

    /// A message's words, where a press opens its bubble's menu (a short bubble is narrower than its row).
    private func words(_ start: String) -> XCUIElement {
        let shown = NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", start, start)
        let text = app.staticTexts.matching(shown).firstMatch
        return text.waitForExistence(timeout: 5) ? text : app.textViews.matching(shown).firstMatch
    }

    private var summarizeItem: XCUIElement { menuItem("Summarize") }
    private var copyItem: XCUIElement { menuItem("Copy") }

    private func menuItem(_ title: String) -> XCUIElement {
        #if os(macOS)
        app.menuItems[title]
        #else
        app.buttons[title]
        #endif
    }

    /// A host limits the question's lines and styles its context; the answers keep all their lines, and the whole
    /// question is one element a test finds by name (jai/agentchatkit#15).
    func testQuestionLineLimitContextStyleAndContainer() {
        launch("question-styled")
        let limited = element("q-limited"), full = element("q-full")
        XCTAssertTrue(limited.waitForExistence(timeout: 5))
        XCTAssertTrue(full.exists)
        XCTAssertTrue(limited.descendants(matching: .any)["q-limited-answer-yes"].exists, "The answers are inside")
        let shortQuestion = element("q-limited-text").frame.height, longQuestion = element("q-full-text").frame.height
        XCTAssertLessThan(shortQuestion, longQuestion * 0.6, "The question was not limited")
        XCTAssertLessThan(element("q-limited-context").frame.height, element("q-full-context").frame.height)
        XCTAssertEqual(element("q-limited-answer-yes").frame.height, element("q-full-answer-yes").frame.height,
                       accuracy: 1, "The answers were limited too")
    }

    /// A thread's reply modes change while it is open: Send now goes and comes back with them (#16).
    func testSendNowFollowsWhetherTheHostOffersIt() {
        launch("queue")
        let send = app.buttons["send-edit"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        toggle("Offer Send now")
        wait(send, "exists == false")
        XCTAssertTrue(app.buttons["edit-edit"].exists, "Edit stays")
        toggle("Offer Send now")
        wait(send, "exists == true")
    }

    /// A host's theme sets the action buttons' style and the Reply button's words; they still act (#18).
    func testHostThemeSetsActionButtonsAndReplyLabel() {
        launch("question-host-controls")
        let reply = app.buttons["host-reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(reply.label.contains("Reply…"), reply.label)
        activate(reply)
        notice("Reply opened")
        launch("queue-host-controls")
        let edit = app.buttons["edit-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        activate(edit)
        wait(element("queue-edit"), "exists == false")
        XCTAssertTrue(app.buttons["send-now"].exists)
    }

    /// A phone's compact queue: each reply on one line with icon buttons that keep their names and touch targets, and a
    /// strip that stays within its height limit and still acts (#19).
    func testCompactQueueRowsAndHeightLimit() {
        launch("queue")
        XCTAssertTrue(element("queue-edit").waitForExistence(timeout: 5))
        let fullRow = element("queue-edit").frame.height
        launch("queue-compact")
        let edit = app.buttons["edit-edit"], send = app.buttons["send-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        #if os(iOS)
        let target: CGFloat = 44
        #else
        let target: CGFloat = 28
        #endif
        for button in [edit, app.buttons["remove-edit"], send] {
            XCTAssertGreaterThanOrEqual(button.frame.height, target, button.identifier)
            XCTAssertGreaterThanOrEqual(button.frame.width, target, button.identifier)
        }
        XCTAssertTrue(edit.label.contains("Edit"), "An icon keeps its name: \(edit.label)")
        XCTAssertTrue(send.label.contains("Send now"), send.label)
        let compactRow = element("queue-edit").frame.height
        XCTAssertLessThan(compactRow, fullRow * 0.6, "The row is not compact: \(compactRow) of \(fullRow)")
        XCTAssertLessThanOrEqual(element("queue-strip").frame.height, 161, "The strip grew past its limit")
        activate(edit)
        wait(element("queue-edit"), "exists == false")
        XCTAssertEqual(app.textViews["fixture-queue-draft"].value as? String, "Queue edit\n\nExisting draft")
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
        app.cancelConfirmation("cancel-alpha")
        notice("Archive calls: 0, Delete calls: 0")
        alpha.press(forDuration: 1)
        activate(app.buttons["delete-alpha"])
        activate(app.sheets.buttons["confirm-alpha"].firstMatch) // iOS 26 lists a dialog's buttons twice
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
