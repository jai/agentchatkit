#if os(iOS)
@testable import AgentChatKit
import SwiftUI
import Testing
import UIKit

/// What the reader sees as a chat changes under them, read off the screen's layers each few milliseconds: a message
/// already there keeps its view and stays opaque, moves one way at most, and ends with the page at its end. Jai,
/// 2026-11-24: the feed blinked and jumped as messages were added.
@Suite(.serialized) @MainActor
struct ChatFeedTests {
    @Observable
    final class Feed {
        var messages: [ChatMessage]
        var waitWhat: Bool
        var isLoadingEarlier = false
        var readsEnd = true

        init(_ messages: [ChatMessage], waitWhat: Bool = false) {
            self.messages = messages
            self.waitWhat = waitWhat
        }
    }

    /// The markers drawn in each message's bubble: UIKit views, whose place and opacity on screen can be read.
    final class Marks {
        var views: [String: [UIView]] = [:]
    }

    private struct Marker: UIViewRepresentable {
        let id: String
        let marks: Marks

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            marks.views[id, default: []].append(view)
            return view
        }

        func updateUIView(_ view: UIView, context: Context) {}
    }

    private struct Page: View {
        @Bindable var feed: Feed
        let marks: Marks
        @FocusState private var focused: Bool

        var body: some View {
            ChatView(
                messages: feed.messages, sent: 0, readsEnd: $feed.readsEnd, isLoadingEarlier: feed.isLoadingEarlier,
                focus: $focused, waitWhat: feed.waitWhat ? {} : nil,
                extras: { _ in Text("Sending") }, header: { EmptyView() }, footer: { EmptyView() },
                composer: { Color.clear.frame(height: 60) }
            )
            .chatMessageContent(when: { _ in true }) { message in
                Text(message.text).background { Marker(id: message.id, marks: marks) }
            }
        }
    }

    private struct Frame {
        var y: CGFloat
        var opacity: CGFloat
    }

    /// One message's frames, from before a change until it settled.
    private struct Film {
        var frames: [Frame] = []
        /// Views made for it by the change: one made again is an old one fading out under a new one fading in.
        var madeAgain = 0
        var distanceToEnd: CGFloat = 0

        var moved: CGFloat { (frames.last?.y ?? 0) - (frames.first?.y ?? 0) }
        var dimmest: CGFloat { frames.map(\.opacity).min() ?? 0 }
        /// How far it was past either end of its way: below where it started, above where it settled.
        var overshoot: CGFloat {
            guard let first = frames.first?.y, let last = frames.last?.y else { return .infinity }
            return frames.map { max($0.y - max(first, last), min(first, last) - $0.y, 0) }.max() ?? 0
        }
    }

    private static func message(_ number: Int, _ role: ChatMessage.Role = .theirs) -> ChatMessage {
        ChatMessage(id: "m\(number)", role: role,
                    text: "Message \(number)\n" + String(repeating: "words of it ", count: 6 + number % 5 * 8), date: .now)
    }

    private static func tool(_ id: String) -> ChatMessage {
        ChatMessage(id: id, role: .tool(name: "Bash"), text: "ls")
    }

    private static func frame(_ view: UIView, in window: UIWindow) -> Frame {
        var shown = Frame(y: 0, opacity: 1)
        var layer: CALayer? = view.layer
        while let model = layer, model !== window.layer {
            let drawn = model.presentation() ?? model
            shown.opacity *= CGFloat(drawn.opacity)
            shown.y += drawn.frame.minY
            if let parent = model.superlayer {
                shown.y -= (parent.presentation() ?? parent).bounds.minY
            }
            layer = model.superlayer
        }
        return shown
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        (view as? UIScrollView) ?? view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    private static func film(_ id: String, in feed: Feed, as change: () -> Void) async throws -> Film {
        let marks = Marks()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = UIHostingController(rootView: Page(feed: feed, marks: marks))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(600))

        let made = try #require(marks.views[id]?.count, "\(id) is drawn")
        func take() throws -> Frame {
            let view = try #require(marks.views[id]?.last { $0.window === window }, "\(id) is on the page")
            return frame(view, in: window)
        }
        var film = try Film(frames: [take()])
        change()
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .milliseconds(700) {
            try await Task.sleep(for: .milliseconds(8))
            try film.frames.append(take())
        }
        film.madeAgain = (marks.views[id]?.count ?? 0) - made
        let page = try #require(scrollView(in: window))
        film.distanceToEnd = page.contentSize.height + page.adjustedContentInset.bottom - page.bounds.maxY
        return film
    }

    private static func expectSteady(_ film: Film) {
        #expect(film.madeAgain == 0, "its view is kept")
        #expect(film.dimmest > 0.98, "it stays opaque")
        #expect(film.overshoot < 2, "it moves one way")
    }

    /// With "Wait, what?", a message after the agent's newest takes it from that one's bubble.
    @Test(arguments: [true, false])
    func aMessageLands(waitWhat: Bool) async throws {
        let feed = Feed((0 ..< 20).map { Self.message($0) }, waitWhat: waitWhat)
        let film = try await Self.film("m19", in: feed) { feed.messages.append(Self.message(20)) }
        Self.expectSteady(film)
        #expect(film.moved < -50, "the new message made its room above the field")
        #expect(abs(film.distanceToEnd) < 1, "the page is at its end")
    }

    /// Agent Pager draws the newest 40: a short message in as a tall one leaves at the top threw the page down 84 pt
    /// and slid it back.
    @Test func aMessageLandsAsTheOldestLeaves() async throws {
        let feed = Feed((0 ..< 40).map { Self.message($0) })
        let film = try await Self.film("m38", in: feed) { feed.messages = feed.messages.dropFirst() + [Self.tool("t")] }
        Self.expectSteady(film)
        #expect(film.moved < -10, "the new line made its room above the field")
        #expect(abs(film.distanceToEnd) < 1, "the page is at its end")
    }

    /// Older messages going in above flew the page through all of them.
    @Test func earlierMessagesGoInAbove() async throws {
        let feed = Feed((20 ..< 40).map { Self.message($0) })
        feed.readsEnd = false
        feed.isLoadingEarlier = true
        let film = try await Self.film("m38", in: feed) {
            feed.messages = (0 ..< 20).map { Self.message($0) } + feed.messages
        }
        Self.expectSteady(film)
        #expect(abs(film.moved) < 2, "what they read stays where it is")
    }

    @Test func aMessageLandingLeavesAReaderFurtherUpWhereTheyAre() async throws {
        let feed = Feed((0 ..< 20).map { Self.message($0) })
        feed.readsEnd = false
        let film = try await Self.film("m18", in: feed) { feed.messages.append(Self.message(20)) }
        Self.expectSteady(film)
        #expect(abs(film.moved) < 2)
    }

    /// His message reaches the host: its status line goes and its ticks come, in the same bubble.
    @Test func aStatusGivesWayToTicksUnderTheSameBubble() async throws {
        var mine = Self.message(19, .mine)
        mine.hasExtras = true
        let feed = Feed((0 ..< 19).map { Self.message($0) } + [mine])
        let film = try await Self.film("m19", in: feed) {
            feed.messages[19].hasExtras = false
            feed.messages[19].ticks = .sent
        }
        Self.expectSteady(film)
    }
}
#endif
