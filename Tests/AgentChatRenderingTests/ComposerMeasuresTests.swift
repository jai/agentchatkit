#if os(macOS)
@testable import AgentChatKit
import AppKit
import SwiftUI
import Testing

/// The message bar's room (Agent Pager fb_da82e3aa766ed4e6: a Mac window at 150% text).
@MainActor
struct ComposerMeasuresTests {
    @Test func aMacBarClearsTheWindowsCornerAsItsSidesDo() {
        let bar = NSHostingView(rootView: Color.clear.frame(width: 100, height: 40).composerBar())
        #expect(bar.fittingSize.height == 40 + ChatStyle.barFade + ChatSpace.lg)
        #expect(bar.fittingSize.width == 100 + 2 * ChatSpace.lg)
    }
}
#endif
