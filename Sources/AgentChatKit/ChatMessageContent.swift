import SwiftUI

public extension View {
    /// Draws the messages the host claims inside the kit's bubble, in place of their words: a link card, a meal card.
    /// The bubble, its side, colour, time, ticks and Copy stay the kit's; every message the host does not claim is
    /// drawn as before (an agent's in Markdown). Put it on the `ChatView` or above it.
    ///
    /// The kit draws a claimed message again when the message changes, not when the host's view is drawn again: what
    /// the content shows of the host's own state (a meal just logged) belongs in the views it returns, such as an
    /// `@Observable` model they read.
    ///
    /// - Parameters:
    ///   - claims: Whether the host draws this message.
    ///   - content: What goes in the bubble, for a message it claims.
    func chatMessageContent<Content: View>(
        when claims: @escaping @MainActor (ChatMessage) -> Bool,
        @ViewBuilder content: @escaping @MainActor (ChatMessage) -> Content
    ) -> some View {
        environment(\.chatMessageContent, ChatMessageContent(claims: claims) { AnyView(content($0)) })
    }

    /// `chatMessageContent(when:content:)`, with what a card that draws something other than the message's words gives
    /// in their place (jai/agentchatkit#20).
    ///
    /// - Parameters:
    ///   - copyText: What the bubble's Copy copies (the message's words when nil or when it returns nil).
    ///   - accessibilityLabel: What VoiceOver reads for the content, such as a meal's name and figures; its controls stay
    ///     reachable inside it.
    ///   - bubbleMenu: Whether the bubble's own long-press menu (Copy, Summarize) wraps this message's content. False for
    ///     a card with its own long press, such as a link row's preview and menu.
    func chatMessageContent<Content: View>(
        when claims: @escaping @MainActor (ChatMessage) -> Bool,
        copyText: (@MainActor (ChatMessage) -> String?)? = nil,
        accessibilityLabel: (@MainActor (ChatMessage) -> String?)? = nil,
        bubbleMenu: @escaping @MainActor (ChatMessage) -> Bool = { _ in true },
        @ViewBuilder content: @escaping @MainActor (ChatMessage) -> Content
    ) -> some View {
        environment(\.chatMessageContent, ChatMessageContent(
            claims: claims, draw: { AnyView(content($0)) }, copyText: copyText, label: accessibilityLabel,
            bubbleMenu: bubbleMenu
        ))
    }
}

/// What the host gives for one claimed message.
struct HostDrawing {
    let view: AnyView
    let copyText: String?
    let label: String?
    let bubbleMenu: Bool
}

/// The host's drawing for the messages it claims. Equal to every other, so a host drawn again does not draw every
/// bubble again (each agent bubble parses its Markdown as it is made).
struct ChatMessageContent: Equatable {
    let claims: @MainActor (ChatMessage) -> Bool
    let draw: @MainActor (ChatMessage) -> AnyView
    var copyText: (@MainActor (ChatMessage) -> String?)?
    var label: (@MainActor (ChatMessage) -> String?)?
    var bubbleMenu: @MainActor (ChatMessage) -> Bool = { _ in true }

    @MainActor
    func content(for message: ChatMessage) -> HostDrawing? {
        guard claims(message) else {
            return nil
        }
        return HostDrawing(view: draw(message), copyText: copyText?(message), label: label?(message),
                           bubbleMenu: bubbleMenu(message))
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var chatMessageContent: ChatMessageContent?
}
