import XCTest

/// The viewer over a message's attachments, on the phone and the Mac.
@MainActor
final class AttachmentViewerUITests: FixtureUITestCase {
    /// A message's screenshots are one viewer: it opens on the one picked, says which of how many it shows, and goes
    /// to the others by its buttons, and on the phone by a swipe across (Jai, Agent Pager, 2026-11-24: "If I have
    /// multiple image attachments, I can't swipe between them"). Shared with the conversation and on a strip alone.
    func testAViewerPagesThroughAMessagesScreenshots() throws {
        for fixture in ["screenshots", "screenshots-local"] {
            launch(fixture)
            activate(app.buttons["picture-fixture-pictures-1"])
            let position = element("viewer-position")
            XCTAssertTrue(position.waitForExistence(timeout: 5), "the viewer does not say which screenshot it shows")
            wait(position, "label == 'Attachment 2 of 2'")
            try keep("viewer-paged-\(fixture)")
            XCTAssertFalse(app.buttons["viewer-next"].isEnabled, "nothing after the last")
            activate(app.buttons["viewer-previous"])
            wait(position, "label == 'Attachment 1 of 2'")
            XCTAssertFalse(app.buttons["viewer-previous"].isEnabled, "nothing before the first")
            #if os(iOS)
            element("host-viewer").swipeLeft()
            wait(position, "label == 'Attachment 2 of 2'")
            element("host-viewer").swipeRight()
            wait(position, "label == 'Attachment 1 of 2'")
            #else
            activate(app.buttons["viewer-next"])
            wait(position, "label == 'Attachment 2 of 2'")
            #endif
            activate(app.buttons["viewer-close"])
            wait(element("host-viewer"), "exists == false")
        }
    }
}
