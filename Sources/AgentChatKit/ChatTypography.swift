import SwiftUI

/// Host roles, independent of a particular font family or point size.
public enum ChatTextRole: Sendable {
    case meta, objectTitle, body, control
}

/// Both the font's leading and the extra distance between text lines belong to the host.
public struct ChatTextStyle: Equatable, Sendable {
    public var font: Font
    /// Nil preserves inherited line spacing or leading already encoded in the host font.
    public var lineSpacing: CGFloat?
    public var leading: Font.Leading?

    public init(font: Font, lineSpacing: CGFloat? = nil, leading: Font.Leading? = nil) {
        self.font = font
        self.lineSpacing = lineSpacing
        self.leading = leading
    }

    public var resolvedFont: Font {
        if let leading { font.leading(leading) } else { font }
    }
}

/// Nil roles fall back to ChatTheme.font. Existing font-only themes remain source compatible.
public struct ChatTypography: Equatable, Sendable {
    public var meta: ChatTextStyle?
    public var objectTitle: ChatTextStyle?
    public var body: ChatTextStyle?
    public var control: ChatTextStyle?

    public init(meta: ChatTextStyle? = nil, objectTitle: ChatTextStyle? = nil,
                body: ChatTextStyle? = nil, control: ChatTextStyle? = nil) {
        self.meta = meta
        self.objectTitle = objectTitle
        self.body = body
        self.control = control
    }
}

extension ChatTheme {
    public func textStyle(_ role: ChatTextRole, fallback: ChatTextStyle? = nil) -> ChatTextStyle {
        switch role {
        case .meta: typography.meta ?? fallback ?? ChatTextStyle(font: font(.caption))
        case .objectTitle: typography.objectTitle ?? fallback ?? ChatTextStyle(font: font(.headline))
        case .body: typography.body ?? fallback ?? ChatTextStyle(font: font(.body))
        case .control: typography.control ?? fallback ?? ChatTextStyle(font: font(.body).weight(.semibold))
        }
    }
}

extension View {
    /// Also available to host accessories/chips, so their baselines use the same host metrics.
    public func chatTextStyle(_ role: ChatTextRole, fallback: ChatTextStyle? = nil) -> some View {
        modifier(ChatTextStyleModifier(role: role, fallback: fallback))
    }
}

private struct ChatTextStyleModifier: ViewModifier {
    @Environment(\.chatTheme) private var theme
    let role: ChatTextRole
    let fallback: ChatTextStyle?

    func body(content: Content) -> some View {
        let style = theme.textStyle(role, fallback: fallback)
        if let lineSpacing = style.lineSpacing {
            content.font(style.resolvedFont).lineSpacing(lineSpacing)
        } else {
            content.font(style.resolvedFont)
        }
    }
}
