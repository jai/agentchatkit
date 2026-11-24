@testable import AgentChatKit
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The spinner is the size of the text it stands by (Agent Pager fb_0d3b7679635181ed: "size and thickness").
@MainActor
struct ChatSpinnerTests {
    private static func theme(_ size: CGFloat) -> ChatTheme {
        ChatTheme(font: { _ in .system(size: size) })
    }

    private static func capitals(_ size: CGFloat) -> CGFloat {
        #if os(macOS)
        NSFont.systemFont(ofSize: size).capHeight
        #else
        UIFont.systemFont(ofSize: size).capHeight
        #endif
    }

    private static func width(_ view: some View) -> CGFloat {
        #if os(macOS)
        NSHostingView(rootView: view.fixedSize()).fittingSize.width
        #else
        UIHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 2000, height: 2000)).width
        #endif
    }

    /// The system's spinners are as tall as the kit scales them from.
    @Test func theSystemsSpinnersAreTheHeightsTheKitKnows() {
        #if os(macOS)
        let sizes: [ControlSize] = [.small, .large]
        #else
        let sizes: [ControlSize] = [.regular, .large]
        #endif
        let heights = sizes.map { Self.width(ProgressView().controlSize($0).dynamicTypeSize(.large)) }
        #expect(heights == [ChatSpinner.heights.small, ChatSpinner.heights.large])
    }

    /// What the spinner takes of the line: all but its words, the gap and the sides.
    @Test(arguments: [13.0, 19.5, 40])
    func theWorkingLinesSpinnerIsAsTallAsItsCapitals(size: CGFloat) {
        let theme = Self.theme(size)
        let words = Self.width(Text("Starting the agent…").font(theme.font(.footnote)))
        let line = Self.width(ChatWorkingLine(activity: "Starting the agent…").chatTheme(theme))
        let spinner = line - words - ChatSpace.sm - 2 * ChatSpace.md
        #expect(abs(spinner - Self.capitals(size)) <= 1, "the spinner takes \(spinner) pt")
    }

    #if os(iOS)
    private struct Bar: View {
        @FocusState private var focused: Bool

        var body: some View {
            SessionComposer(draft: .constant(""), isSending: true, send: {}, focused: $focused)
        }
    }

    /// The spinner as it is drawn, its scale with it.
    private static func drawn(_ view: some View) async throws -> CGRect {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<5 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        let spinner = try #require(views(in: window).first { $0 is UIActivityIndicatorView })
        return spinner.convert(spinner.bounds, to: window)
    }

    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    @Test(arguments: [13.0, 19.5])
    func theWorkingLinesSpinnerIsDrawnAtThatSize(size: CGFloat) async throws {
        let drawn = try await Self.drawn(ChatWorkingLine().chatTheme(Self.theme(size)))
        #expect(abs(drawn.height - Self.capitals(size)) <= 1, "the spinner is \(drawn.height) pt tall")
    }

    /// There the system's own spinner grows as well (observed, iOS 27.2).
    @Test func theLargestTextSizeScalesItOnce() async throws {
        let line = ChatWorkingLine().chatTheme(Self.theme(40)).dynamicTypeSize(.accessibility5)
        let drawn = try await Self.drawn(line)
        #expect(abs(drawn.height - Self.capitals(40)) <= 1, "the spinner is \(drawn.height) pt tall")
    }

    @Test(arguments: [17.0, 25.5])
    func sendsSpinnerIsAsTallAsItsArrow(size: CGFloat) async throws {
        let drawn = try await Self.drawn(Bar().chatTheme(Self.theme(size)))
        #expect(abs(drawn.height - Self.capitals(size) * 1.3) <= 1, "the spinner is \(drawn.height) pt tall")
    }
    #endif
}
