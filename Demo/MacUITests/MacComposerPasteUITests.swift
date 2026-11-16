import AppKit
import XCTest

/// Command-V in the Mac composer: a picture on the clipboard is attached, as on the phone; words are pasted as words
/// (jai/agentchatkit#10).
@MainActor
final class MacComposerPasteUITests: FixtureUITestCase {
    private var field: XCUIElement { app.textFields["sessionReplyField"] }

    private func pasteInField() {
        activate(field)
        app.typeKey("v", modifierFlags: .command)
    }

    func testCommandVWithAPictureAttachesIt() throws {
        launch("composer-paste")
        let picture = try XCTUnwrap(NSImage(size: NSSize(width: 40, height: 80), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }.tiffRepresentation)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(picture, forType: .tiff)
        pasteInField()
        XCTAssertTrue(element("composerAttachment").waitForExistence(timeout: 5), "Command-V did not attach the picture")
        XCTAssertEqual(field.value as? String ?? "", "", "The picture went into the words")
    }

    func testCommandVWithWordsPastesThem() {
        launch("composer-paste")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Pasted words", forType: .string)
        pasteInField()
        wait(field, "value == 'Pasted words'")
        XCTAssertFalse(element("composerAttachment").exists, "Words were attached as a picture")
    }
}
