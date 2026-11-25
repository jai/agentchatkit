import SwiftUI

/// The look of a chat's action buttons: a queued reply's Edit, Remove and Send now, a sent reply's Retry and Cancel, and
/// a question's Reply. Their words take the theme's `.control` text role (`ChatTheme.typography.control`).
public enum ChatControlStyle: Sendable {
    /// The kit's own: bordered, Send now prominent, Retry and Cancel borderless.
    case standard
    case bordered
    case borderless
    case plain
}

extension ChatTheme {
    /// A host's own action buttons: their style, and the Reply button's words (its symbol is `symbols.reply`).
    public struct Controls: Equatable, Sendable {
        public var style = ChatControlStyle.standard
        public var replyLabel = "Reply"

        public init() {}
    }
}

/// An action button in the theme's style, or the kit's own (`standard`) when the theme keeps it.
struct ChatControlButtonStyle: ViewModifier {
    @Environment(\.chatTheme) private var theme
    let standard: ChatControlStyle
    var isProminent = false

    func body(content: Content) -> some View {
        switch theme.controls.style == .standard ? standard : theme.controls.style {
        case .standard, .bordered:
            if isProminent, theme.controls.style == .standard {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        case .borderless:
            content.buttonStyle(.borderless)
        case .plain:
            content.buttonStyle(.plain)
        }
    }
}

extension View {
    /// The kit's action button, in the host's style when its theme sets one.
    func chatControlButton(standard: ChatControlStyle = .bordered, prominent: Bool = false) -> some View {
        modifier(ChatControlButtonStyle(standard: standard, isProminent: prominent))
    }
}
