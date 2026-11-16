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
}

/// The host's drawing for the messages it claims. Equal to every other, so a host drawn again does not draw every
/// bubble again (each agent bubble parses its Markdown as it is made).
struct ChatMessageContent: Equatable {
    let claims: @MainActor (ChatMessage) -> Bool
    let draw: @MainActor (ChatMessage) -> AnyView

    @MainActor
    func content(for message: ChatMessage) -> AnyView? {
        claims(message) ? draw(message) : nil
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var chatMessageContent: ChatMessageContent?
}
