import XCTest

/// A video kept as a video, on the phone and the Mac (jai/agentchatkit#4): attached, it shows in the composer by its
/// length and plays in the composer's viewer; sent, it shows in the message's strip and plays in the shared viewer.
@MainActor
final class VideoUITests: FixtureUITestCase {
    /// The sample video plays for ten seconds.
    private var playingVideo: XCUIElement {
        #if os(macOS)
        // AVKit exposes playback through its native checkbox; a Mac accessibility group has no value.
        app.checkBoxes.matching(NSPredicate(
            format: "label == 'play/pause' AND (value == 1 OR value == '1')"
        )).firstMatch
        #else
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Video, 0:10' AND value == 'Playing'")).firstMatch
        #endif
    }

    func testAVideoIsAttachedSentOpenedAndPlayed() {
        launch("video")
        activate(app.buttons["demo-sample-video"])

        // In the composer: the video, by its length, not as stills.
        let attached = element("composerAttachment")
        XCTAssertTrue(attached.waitForExistence(timeout: 30), "the sample video was not attached")
        XCTAssertEqual(attached.label, "Video, 0:10")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "composerAttachment").count, 1,
                       "the video was added as stills")
        activate(attached)
        XCTAssertTrue(element("composerAttachmentViewer").waitForExistence(timeout: 5))
        XCTAssertTrue(playingVideo.waitForExistence(timeout: 10), "the composer's viewer did not play the video")
        activate(app.buttons["composerAttachmentViewerClose"])
        wait(element("composerAttachmentViewer"), "exists == false")

        // Sent: the message's strip shows it, and the shared viewer plays it.
        activate(app.buttons["sessionReplySend"])
        let sent = app.buttons["sent-me-0-0"]
        XCTAssertTrue(sent.waitForExistence(timeout: 10), "the sent strip has no video")
        XCTAssertEqual(sent.label, "Video, 0:10, 1 of 1")
        XCTAssertFalse(element("composerAttachment").exists, "the composer kept the video after sending")
        activate(sent)
        XCTAssertTrue(element("sent-video-viewer").waitForExistence(timeout: 5))
        XCTAssertTrue(playingVideo.waitForExistence(timeout: 10), "the sent strip's viewer did not play the video")
        activate(app.buttons["sent-video-viewer-close"])
        wait(element("sent-video-viewer"), "exists == false")
    }

    /// Two videos on one message: the composer's viewer opens on the one picked and its buttons go to the other; a
    /// video's player keeps a drag across it for itself. Only the video shown plays.
    func testTheComposersViewerGoesFromOneVideoToTheOther() {
        launch("video")
        activate(app.buttons["demo-sample-video"])
        let attached = app.descendants(matching: .any).matching(identifier: "composerAttachment")
        XCTAssertTrue(attached.firstMatch.waitForExistence(timeout: 30), "the sample video was not attached")
        activate(app.buttons["demo-sample-video"])
        let second = attached.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 30), "the second video was not attached")
        activate(second)
        let position = element("composerAttachmentViewerPosition")
        XCTAssertTrue(position.waitForExistence(timeout: 5), "the viewer does not say which attachment it shows")
        wait(position, "label == 'Attachment 2 of 2'")
        XCTAssertTrue(playingVideo.waitForExistence(timeout: 10), "the second video did not play")
        activate(app.buttons["composerAttachmentViewerPrevious"])
        wait(position, "label == 'Attachment 1 of 2'")
        XCTAssertTrue(playingVideo.waitForExistence(timeout: 10), "the first video did not play")
        activate(app.buttons["composerAttachmentViewerClose"])
        wait(element("composerAttachmentViewer"), "exists == false")
    }
}
