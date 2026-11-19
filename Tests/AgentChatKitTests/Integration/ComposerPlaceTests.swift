#if os(macOS)
@testable import AgentChatKit
import AppKit
import Testing

/// Command-V attaches a picture only while the window's text cursor is in the composer (jai/agentchatkit#10).
@MainActor
struct ComposerPlaceTests {
    private func window(cursorAt cursorFrame: NSRect) -> (NSWindow, ComposerPlace) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        let composer = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        let field = NSTextView(frame: cursorFrame)
        window.contentView?.addSubview(composer)
        window.contentView?.addSubview(field)
        let place = ComposerPlace()
        place.view = composer
        window.makeFirstResponder(field)
        return (window, place)
    }

    @Test func aCursorInTheComposerTakesThePicture() {
        let (window, place) = window(cursorAt: NSRect(x: 20, y: 20, width: 300, height: 30))
        #expect(place.holdsTextCursor(of: window))
    }

    @Test func aCursorElsewhereInTheWindowDoesNot() {
        let (window, place) = window(cursorAt: NSRect(x: 20, y: 200, width: 300, height: 30))
        #expect(!place.holdsTextCursor(of: window))
    }

    @Test func anotherWindowDoesNot() {
        let (_, place) = window(cursorAt: NSRect(x: 20, y: 20, width: 300, height: 30))
        let (other, _) = window(cursorAt: NSRect(x: 20, y: 20, width: 300, height: 30))
        #expect(!place.holdsTextCursor(of: other))
    }
}
#endif
