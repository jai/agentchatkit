@testable import AgentChatKit
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The message bar's room and its buttons (Agent Pager fb_da82e3aa766ed4e6: a Mac window at 150% text).
@MainActor
struct ComposerMeasuresTests {
    #if os(macOS)
    private static let standardFont: CGFloat = 14
    #else
    private static let standardFont: CGFloat = 17
    #endif

    private struct Bar: View {
        @FocusState private var focused: Bool
        let attachments: ComposerAttachments?

        var body: some View {
            SessionComposer(draft: .constant("Words"), isSending: false, send: {}, focused: $focused,
                            attachments: attachments)
        }
    }

    /// How wide the field is in a bar of 400 pt, with the theme's body font at `size`: what its buttons leave it.
    private static func fieldWidth(bodyFont size: CGFloat, attachments: ComposerAttachments? = nil) async throws -> CGFloat {
        let theme = ChatTheme(font: { _ in .system(size: size) })
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let bar = Bar(attachments: attachments).chatTheme(theme).font(theme.font(.body))
        #if os(macOS)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSHostingView(rootView: bar)
        window.contentView = root
        defer { window.close() }
        for _ in 0..<5 {
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        return try #require(views(in: root).first { $0 is NSTextField }).frame.width
        #else
        let window = UIWindow(frame: frame)
        window.rootViewController = UIHostingController(rootView: bar)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<5 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        return try #require(views(in: window).first { $0 is UITextView }).frame.width
        #endif
    }

    #if os(macOS)
    private static func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }
    #else
    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }
    #endif

    /// 22 pt at the standard size, 33 at half as much again: the field gives up those 11 pt.
    @Test func theSendButtonGrowsWithTheText() async throws {
        let standard = try await Self.fieldWidth(bodyFont: Self.standardFont)
        let bigger = try await Self.fieldWidth(bodyFont: Self.standardFont * 1.5)
        #expect(abs(standard - bigger - 11) <= 1, "the field is \(standard) pt, then \(bigger)")
    }

    @Test func thePaperclipGrowsWithSend() async throws {
        let standard = try await Self.fieldWidth(bodyFont: Self.standardFont, attachments: ComposerAttachments())
        let bigger = try await Self.fieldWidth(bodyFont: Self.standardFont * 1.5, attachments: ComposerAttachments())
        #expect(abs(standard - bigger - 22) <= 1, "the field is \(standard) pt, then \(bigger)")
    }

    #if os(macOS)
    @Test func aMacBarClearsTheWindowsCornerAsItsSidesDo() {
        let bar = NSHostingView(rootView: Color.clear.frame(width: 100, height: 40).composerBar())
        #expect(bar.fittingSize.height == 40 + ChatStyle.barFade + ChatSpace.lg)
        #expect(bar.fittingSize.width == 100 + 2 * ChatSpace.lg)
    }
    #endif
}
