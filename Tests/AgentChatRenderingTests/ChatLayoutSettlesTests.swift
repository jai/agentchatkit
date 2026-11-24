@testable import AgentChatKit
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A chat on screen comes to rest: a view that asks for layout each time it is laid out keeps the app busy, and on the
/// Mac AppKit ends it after 520 passes (Agent Pager 0.11.1's working line, run 45390008471, 2026-11-24).
@MainActor
@Suite(.serialized)
struct ChatLayoutSettlesTests {
    #if os(macOS)
    private final class Root: NSHostingView<AnyView> {
        var layouts = 0
        override func layout() {
            layouts += 1
            super.layout()
        }
    }
    #else
    private final class Root: UIHostingController<AnyView> {
        var layouts = 0
        override func viewDidLayoutSubviews() {
            layouts += 1
            super.viewDidLayoutSubviews()
        }
    }
    #endif

    private struct Bar: View {
        @FocusState private var focused: Bool
        let isSending: Bool

        var body: some View {
            SessionComposer(draft: .constant("Words"), isSending: isSending, send: {}, focused: $focused).composerBar()
        }
    }

    private struct Chat: View {
        @FocusState private var focused: Bool
        @State private var readsEnd = true
        @State private var isWorking = false
        let count: Int

        var body: some View {
            ChatView(
                messages: (0..<count).map {
                    ChatMessage(id: "\($0)", role: $0.isMultiple(of: 2) ? .mine : .theirs, text: "Message \($0).")
                },
                sent: 0, readsEnd: $readsEnd, focus: $focused,
                extras: { _ in EmptyView() }, header: { EmptyView() },
                footer: {
                    if isWorking {
                        ChatWorkingLine().frame(maxWidth: .infinity, alignment: .leading)
                    }
                },
                composer: {
                    SessionComposer(draft: .constant(""), isSending: isWorking, send: {}, focused: $focused).composerBar()
                }
            )
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                isWorking = true
            }
        }
    }

    /// How often the view is laid out in a second and a half.
    private static func layouts(_ view: some View) async throws -> Int {
        let frame = CGRect(x: 0, y: 0, width: 700, height: 600)
        #if os(macOS)
        let window = NSWindow(contentRect: frame.offsetBy(dx: -3000, dy: -3000), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = Root(rootView: AnyView(view))
        window.contentView = root
        window.orderFront(nil)
        defer { window.close() }
        #else
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = Root(rootView: AnyView(view))
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        #endif
        try await Task.sleep(for: .milliseconds(1500))
        #expect(root.layouts > 0, "it was on screen")
        return root.layouts
    }

    /// The viewer over a message's attachments (`ChatMediaPager`): its pages are sized from the room it is given, and
    /// it must not ask for that room again as it lays them out.
    @Test func aViewerOverSeveralPicturesSettles() async throws {
        let pages = try (0..<3).map { index in
            let context = try #require(CGContext(
                data: nil, width: 60, height: 130, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            context.setFillColor(CGColor(gray: 0.3 + 0.2 * CGFloat(index), alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 130))
            return ChatMediaPage(id: index, image: try #require(context.makeImage()))
        }
        let layouts = try await Self.layouts(ChatMediaPager(pages: pages, start: 1, identifiers: .init(), close: {}))
        #expect(layouts < 100)
    }

    @Test func theWorkingLineSettles() async throws {
        let layouts = try await Self.layouts(ChatWorkingLine().frame(maxWidth: .infinity, maxHeight: .infinity))
        #expect(layouts < 100)
    }

    @Test func aBarThatIsSendingSettles() async throws {
        let layouts = try await Self.layouts(Bar(isSending: true))
        #expect(layouts < 100)
    }

    @Test(arguments: [1, 12])
    func aChatSettlesAsItsAgentStartsToWork(messages: Int) async throws {
        let layouts = try await Self.layouts(Chat(count: messages))
        #expect(layouts < 100)
    }
}
