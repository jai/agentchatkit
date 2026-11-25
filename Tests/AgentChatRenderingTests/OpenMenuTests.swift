#if os(iOS)
@testable import AgentChatKit
import ObjectiveC
import SwiftUI
import Testing
import UIKit

/// An open menu's rows are not made anew as its screen is drawn again: a row made anew under a finger takes no tap
/// (Agent Pager fb_569733d05b7b197c).
@MainActor @Suite(.serialized)
struct OpenMenuTests {
    private struct Box: View {
        @FocusState private var focused: Bool
        let draw: Int
        var sending = false
        var attachments: ComposerAttachments?
        var sendNow: ((String) -> Void)?
        var send: (String) -> Void = { _ in }
        var pick: ((ModelReasoning.Pick) -> Void)?

        var body: some View {
            SessionComposer(
                draft: .constant("Words \(draw)"), isSending: sending, send: { send("draw \(draw)") }, focused: $focused,
                attachments: attachments,
                sendNow: sendNow.map { sendNow in .init(label: "Send now") { sendNow("draw \(draw)") } },
                modelPicker: pick.map { pick in ModelPicker(options: OpenMenuTests.options()) { pick($0) } }
            ).composerBar()
        }
    }

    static func options() -> ModelReasoning {
        let levels = [ModelReasoning.Effort(id: "low", label: "Low"), .init(id: "high", label: "High")]
        return ModelReasoning(
            models: [.init(id: "opus", label: "Opus", efforts: levels), .init(id: "sonnet", label: "Sonnet", efforts: levels)],
            model: "opus", effort: "high", fast: false
        )
    }

    @Test func theModelChipKeepsItsRows() async throws {
        let made = try await rowsMadeAnew { draw in
            VStack {
                Text("\(draw)")
                ModelReasoningChip(picker: ModelPicker(options: Self.options()) { _ in _ = draw })
            }
        }
        #expect(made == 0)
    }

    @Test func theModelChipByTheReplyBoxKeepsItsRows() async throws {
        let made = try await rowsMadeAnew { Box(draw: $0, pick: { _ in }) }
        #expect(made == 0)
    }

    @Test func sendNowKeepsItsRowAsWordsCome() async throws {
        let made = try await rowsMadeAnew { Box(draw: $0, sendNow: { _ in }) }
        #expect(made == 0)
    }

    @Test func sendNowKeepsItsRowAsSendingStartsAndEnds() async throws {
        let made = try await rowsMadeAnew { Box(draw: $0, sending: $0 % 2 == 1, sendNow: { _ in }) }
        #expect(made == 0)
    }

    @Test func thePaperclipKeepsItsRows() async throws {
        let attachments = ComposerAttachments()
        let made = try await rowsMadeAnew { Box(draw: $0, attachments: attachments) }
        #expect(made == 0)
    }

    @Test func thePaperclipKeepsItsRowsAsTheThemeIsChangedOnItsWay() async throws {
        let attachments = ComposerAttachments()
        let made = try await rowsMadeAnew { draw in
            Box(draw: draw, attachments: attachments)
                .transformEnvironment(\.chatTheme) { $0.typography.objectTitle = ChatTextStyle(font: .body) }
        }
        #expect(made == 0)
    }

    @Test func thePaperclipKeepsItsRowsAsAScreenshotLandsAndGoes() async throws {
        let attachments = ComposerAttachments()
        let size = CGSize(width: 8, height: 8)
        let picture = UIGraphicsImageRenderer(size: size).pngData { $0.fill(CGRect(origin: .zero, size: size)) }
        let made = try await rowsMadeAnew(between: {
            if let image = attachments.images.first {
                attachments.remove(image.id)
            } else {
                await attachments.add(picture)
            }
        }) { Box(draw: $0, attachments: attachments) }
        #expect(made == 0)
    }

    /// What the others would count with a menu drawn with its screen.
    @Test func aPlainMenusRowsAreMadeAnew() async throws {
        let made = try await rowsMadeAnew { draw in
            VStack {
                Text("\(draw)")
                Menu("Menu") { Button("Row") { _ = draw } } primaryAction: { _ = draw }
            }
        }
        #expect(made > 0)
    }

    @Test func aTapSendsWithTheLatestDraw() async throws {
        var sent: [String] = []
        let screen = Screen()
        let window = try window(Redrawn(screen: screen) { draw in
            Box(draw: draw, sendNow: { _ in }, send: { sent.append($0) })
        })
        defer { window.isHidden = true }
        try await settle()
        try await redraw(screen)
        try menuButton(window).performPrimaryAction()
        try await settle()
        #expect(sent == ["draw 1"])
    }

    // MARK: - A screen drawn again

    @Observable final class Screen {
        var draws = 0
        @ObservationIgnored var drawn = 0
    }

    private struct Redrawn<Content: View>: View {
        let screen: Screen
        @ViewBuilder let content: (Int) -> Content
        var body: some View {
            screen.drawn = screen.draws
            return content(screen.draws)
        }
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(800)) }

    private func window(_ view: some View) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }

    private func menuButton(_ window: UIWindow) throws -> UIControl {
        func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
        return try #require(
            views(window).lazy.compactMap { $0 as? UIControl }
                .first { $0.isContextMenuInteractionEnabled && $0.contextMenuInteraction != nil }
        )
    }

    private func redraw(_ screen: Screen) async throws {
        screen.draws += 1
        for _ in 0..<500 where screen.drawn < screen.draws {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(screen.drawn == screen.draws)
        try await Task.sleep(for: .milliseconds(100))
    }

    /// Opens a menu: by its tap, or by the long-press where the tap does something else.
    private func open(_ button: UIControl) async throws {
        let opened = MenuUpdates.opened
        if button.showsMenuAsPrimaryAction {
            button.performPrimaryAction()
        } else {
            let interaction = try #require(button.contextMenuInteraction)
            let selector = NSSelectorFromString("_presentMenuAtLocation:")
            try #require(interaction.responds(to: selector))
            typealias Present = @convention(c) (AnyObject, Selector, CGPoint) -> Void
            unsafeBitCast(interaction.method(for: selector), to: Present.self)(
                interaction, selector, CGPoint(x: button.bounds.midX, y: button.bounds.midY)
            )
        }
        for _ in 0..<250 where MenuUpdates.opened == opened {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(MenuUpdates.opened > opened)
        // SwiftUI itself makes a menu's rows anew just after it shows.
        try await settle()
    }

    /// How often an open menu's rows were made anew over ten draws of its screen.
    private func rowsMadeAnew(
        between: () async -> Void = {}, @ViewBuilder _ content: @escaping (Int) -> some View
    ) async throws -> Int {
        let screen = Screen()
        let window = try window(Redrawn(screen: screen, content: content))
        defer { window.isHidden = true }
        try await settle()
        let button = try menuButton(window)
        try await open(button)
        let before = MenuUpdates.count
        for _ in 0..<10 {
            await between()
            try await redraw(screen)
        }
        let updates = MenuUpdates.count - before
        button.contextMenuInteraction?.dismissMenu()
        try await settle()
        return updates
    }
}

@MainActor private enum MenuUpdates {
    static var opened: Int { _ = swizzled; return shown }
    static var count: Int { _ = swizzled; return updates }
    fileprivate static var shown = 0
    fileprivate static var updates = 0

    private static let swizzled: Void = {
        func exchange(_ type: AnyClass, _ original: Selector, _ counting: Selector) {
            guard let one = class_getInstanceMethod(type, original), let other = class_getInstanceMethod(type, counting) else { return }
            method_exchangeImplementations(one, other)
        }
        exchange(UIContextMenuInteraction.self, #selector(UIContextMenuInteraction.updateVisibleMenu(_:)),
                 #selector(UIContextMenuInteraction.countingUpdate(_:)))
        exchange(UIControl.self, #selector(UIControl.contextMenuInteraction(_:willDisplayMenuFor:animator:)),
                 #selector(UIControl.countingDisplay(_:willDisplayMenuFor:animator:)))
    }()
}

private extension UIContextMenuInteraction {
    @objc func countingUpdate(_ block: @escaping (UIMenu) -> UIMenu) {
        MenuUpdates.updates += 1
        countingUpdate(block)
    }
}

private extension UIControl {
    @objc func countingDisplay(
        _ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        MenuUpdates.shown += 1
        countingDisplay(interaction, willDisplayMenuFor: configuration, animator: animator)
    }
}
#endif
