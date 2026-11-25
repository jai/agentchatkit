@testable import AgentChatKit
import os
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private extension EnvironmentValues {
    @Entry var somethingElse = 0
}

/// The bubbles of a chat are made once as it opens, and not again as the environment changes around an unchanged theme:
/// a bubble made again parses its Markdown again (Agent Pager fb_3cde3642c7513c88: five times in the first open).
@Suite(.serialized) @MainActor
struct ChatThemeRedrawTests {
    /// How often the theme was asked for a bubble's words' font: once for each time a bubble is made.
    private final class Made: Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)
        var value: Int { count.withLock { $0 } }
        func add() { count.withLock { $0 += 1 } }
    }

    /// How a host gives its chats a theme.
    enum Shape: CaseIterable {
        /// The theme as it is, its text roles empty.
        case plain
        /// Agent Pager's: every text role set, and the question's font set again on the way down to the chat
        /// (`chatQuestionFont`), to what the theme has; or to another, as under a row.
        case setAgainOnTheWay, changedOnTheWay

        var theme: ChatTypography {
            self == .plain ? ChatTypography() : ChatTypography(
                meta: ChatTextStyle(font: .caption), objectTitle: ChatTextStyle(font: .title3),
                body: ChatTextStyle(font: .callout), control: ChatTextStyle(font: .footnote.weight(.semibold))
            )
        }
    }

    @Observable
    final class Host {
        var somethingElse = 0
    }

    private struct Page: View {
        let host: Host
        let theme: ChatTheme
        let shape: Shape
        @State private var readsEnd = true
        @FocusState private var focused: Bool

        var body: some View {
            NavigationStack {
                ChatView(
                    messages: (0 ..< 8).map {
                        ChatMessage(id: "\($0)", role: $0.isMultiple(of: 2) ? .mine : .theirs, text: "Message \($0): **words**.")
                    },
                    sent: 0, readsEnd: $readsEnd, focus: $focused, extras: { _ in EmptyView() },
                    header: { EmptyView() }, footer: { EmptyView() }, composer: { Color.clear.frame(height: 60) }
                )
                .transformEnvironment(\.chatTheme) { theme in
                    switch shape {
                    case .plain: break
                    case .setAgainOnTheWay: theme.typography.objectTitle = ChatTextStyle(font: .title3)
                    case .changedOnTheWay: theme.typography.objectTitle = ChatTextStyle(font: .body)
                    }
                }
            }
            .environment(\.somethingElse, host.somethingElse)
            .chatTheme(theme)
        }
    }

    private static func theme(_ made: Made, _ shape: Shape) -> ChatTheme {
        ChatTheme(font: { style in
            if style == .callout {
                made.add()
            }
            return .system(style)
        }, typography: shape.theme)
    }

    private struct Opened {
        var first: Int
        var afterChange: Int
    }

    private static func open(_ shape: Shape) async throws -> Opened {
        let made = Made()
        let host = Host()
        let view = Page(host: host, theme: theme(made, shape), shape: shape)
        #if os(macOS)
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 700, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        defer { window.close() }
        #else
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        #endif
        try await Task.sleep(for: .milliseconds(1500))
        let first = made.value
        for _ in 0 ..< 3 {
            host.somethingElse += 1
            try await Task.sleep(for: .milliseconds(200))
        }
        return Opened(first: first, afterChange: made.value - first)
    }

    @Test(arguments: Shape.allCases)
    func itsBubblesAreMadeOnce(_ shape: Shape) async throws {
        let opened = try await Self.open(shape)
        #expect(opened.first == 8, "each of the 8 bubbles is made once as the chat opens")
        #expect(opened.afterChange == 0, "none again as the environment changes around them")
    }

    /// A host changes a copy; the theme it copied stays as it was, and what the host set is what it reads.
    @Test func aCopyIsChangedAlone() {
        var copy = ChatTheme.standard
        copy.typography.objectTitle = ChatTextStyle(font: .largeTitle)
        copy.symbols.copy = "star"
        copy.controls.replyLabel = "Answer"
        copy.font = { _ in .body.bold() }
        #expect(copy.typography.objectTitle?.font == .largeTitle)
        #expect(copy.symbols.copy == "star" && copy.symbols.close == ChatTheme.standard.symbols.close)
        #expect(copy.controls.replyLabel == "Answer")
        #expect(copy.font(.callout) == .body.bold())
        #expect(ChatTheme.standard.typography.objectTitle?.font == nil)
        #expect(ChatTheme.standard.symbols.copy == "doc.on.doc" && ChatTheme.standard.controls.replyLabel == "Reply")
    }

    /// Each change is read back, however many came before it and in whichever order they come again.
    @Test func everyChangeIsKept() {
        for size in Array(1 ... 20) + [3, 20, 1] {
            var copy = ChatTheme.standard
            copy.typography.objectTitle = ChatTextStyle(font: .system(size: CGFloat(size)))
            copy.spacing.lg = CGFloat(size)
            #expect(copy.typography.objectTitle?.font == .system(size: CGFloat(size)))
            #expect(copy.spacing.lg == CGFloat(size) && copy.typography.meta == nil)
        }
        #expect(ChatTheme.standard.typography.objectTitle == nil)
    }
}
