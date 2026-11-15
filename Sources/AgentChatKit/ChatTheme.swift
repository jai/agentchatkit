import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// What a chat takes from the app around it: its fonts, colours and icons. A host sets its own with `.chatTheme(_:)` at
/// its root; with none, `standard` draws the system's, which is what PRHub's DESIGN.md draws today.
public struct ChatTheme: Sendable {
    /// A text style's font: the bubble's words are `.callout`, a time `.caption2`.
    public var font: @Sendable (Font.TextStyle) -> Font
    /// A fenced code block's words in a message.
    public var code: @MainActor @Sendable (Text) -> AnyView

    /// Words, and quiet words (a time, a tool call).
    public var ink: Color
    public var inkQuiet: Color
    /// Words on the person's own bubble, which is the tint.
    public var onBubble: Color
    /// The page under the chat, and a box on it.
    public var groundPage: Color
    public var groundCard: Color
    /// The full-screen screenshot viewer stays dark even when the host chooses a light paper theme.
    public var pictureGround: Color
    /// Behind a table's header.
    public var groundFill: Color
    /// A hairline: a box's border.
    public var line: Color
    /// Delivered, a problem, and waiting (an agent paused).
    public var toneGood: Color
    public var toneBad: Color
    public var toneWaiting: Color

    /// Semantic host typography; unset roles continue to use `font`, including later mutations of it.
    public var typography: ChatTypography
    public var spacing: ChatSpacing
    public var controlSize: ControlSize

    public var symbols: Symbols

    /// The SF Symbols a chat draws, by what they mean.
    public struct Symbols: Sendable {
        public var toolCall = "wrench.and.screwdriver"
        public var copy = "doc.on.doc"
        public var askAI = "questionmark.bubble"
        public var delivered = "checkmark.circle"
        public var close = "xmark"
        public var problem = "exclamationmark.triangle"
        public var attach = "paperclip"
        public var attachPhoto = "photo.on.rectangle"
        public var attachFile = "folder"
        public var taskOpen = "square"
        public var taskDone = "checkmark.square.fill"
        public var fold = "chevron.down"
        /// A list of chats: back to it, a new one, none open, into one, and one waiting.
        public var back = "chevron.backward"
        public var compose = "square.and.pencil"
        public var conversation = "text.bubble"
        public var drillIn = "chevron.right"
        public var paused = "pause.circle.fill"
        public var archive = "archivebox"
        public var delete = "trash"
        public var sendNow = "arrow.up"
        public var edit = "pencil"

        public init() {}
    }

    public init(
        font: @escaping @Sendable (Font.TextStyle) -> Font = ChatTheme.systemFont,
        code: @escaping @MainActor @Sendable (Text) -> AnyView = ChatTheme.systemCode,
        ink: Color = .primary, inkQuiet: Color = .secondary, onBubble: Color = .white,
        groundPage: Color = ChatTheme.systemGroundPage, groundCard: Color = ChatTheme.systemGroundCard,
        groundFill: Color = ChatTheme.systemGroundFill, pictureGround: Color = .black, line: Color = ChatTheme.systemLine,
        toneGood: Color = Color("ToneGood"), toneBad: Color = Color("ToneBad"),
        toneWaiting: Color = Color("ToneWaiting"), symbols: Symbols = Symbols(),
        typography: ChatTypography = ChatTypography(), spacing: ChatSpacing = ChatSpacing(),
        controlSize: ControlSize = .large
    ) {
        self.font = font
        self.code = code
        self.ink = ink
        self.inkQuiet = inkQuiet
        self.onBubble = onBubble
        self.groundPage = groundPage
        self.groundCard = groundCard
        self.pictureGround = pictureGround
        self.groundFill = groundFill
        self.line = line
        self.toneGood = toneGood
        self.toneBad = toneBad
        self.toneWaiting = toneWaiting
        self.symbols = symbols
        self.typography = typography
        self.spacing = spacing
        self.controlSize = controlSize
    }

    public static let standard = ChatTheme()
}

extension ChatTheme {
    /// The system font at each style: Dynamic Type on the phone; on the Mac the Mac's sizes, times the text size its
    /// View menu keeps under `macTextScale` (PRHub's and Agent Pager's Make Text Bigger).
    public static let systemFont: @Sendable (Font.TextStyle) -> Font = { style in
        #if os(macOS)
        let size = (macSizes[style] ?? 14) * macScale
        return .system(size: size, weight: style == .headline ? .semibold : .regular)
        #else
        return .system(style)
        #endif
    }

    /// A code block in the system's monospaced font, a step under the words.
    public static let systemCode: @MainActor @Sendable (Text) -> AnyView = { text in
        AnyView(text.font(systemFont(.footnote).monospaced()))
    }

    #if os(macOS)
    static let macSizes: [Font.TextStyle: CGFloat] = [
        .largeTitle: 28, .title: 22, .title2: 18, .title3: 16, .headline: 14, .subheadline: 13, .body: 14,
        .callout: 13, .footnote: 12, .caption: 11, .caption2: 11,
    ]

    static var macScale: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "macTextScale")
        return [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5].contains(stored) ? stored : 1
    }
    #endif

    public static var systemGroundPage: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    public static var systemGroundCard: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    public static var systemGroundFill: Color {
        #if os(iOS)
        Color(uiColor: .tertiarySystemFill)
        #else
        Color(nsColor: .tertiarySystemFill)
        #endif
    }

    public static var systemLine: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}

extension EnvironmentValues {
    @Entry public var chatTheme: ChatTheme = .standard
}

extension View {
    /// The fonts, colours and icons of every chat under it.
    public func chatTheme(_ theme: ChatTheme) -> some View {
        environment(\.chatTheme, theme)
    }
}

/// An icon and its words, the icon in a slot one width wide so lines of them line up (PRHub's `iconText`).
struct ChatIconTextLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChatIconTextLine(icon: configuration.icon, words: configuration.title)
    }
}

extension LabelStyle where Self == ChatIconTextLabelStyle {
    static var chatIconText: ChatIconTextLabelStyle { ChatIconTextLabelStyle() }
}

private struct ChatIconTextLine<Icon: View, Words: View>: View {
    @Environment(\.chatTheme) private var theme
    let icon: Icon
    let words: Words
    /// The slot grows with the text, as the icon does.
    @ScaledMetric(relativeTo: .footnote) private var slot = ChatSpace.lg

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
            icon
                .fixedSize()
                .frame(minWidth: slot, alignment: .leading)
                .accessibilityHidden(true)
            words
        }
    }
}
