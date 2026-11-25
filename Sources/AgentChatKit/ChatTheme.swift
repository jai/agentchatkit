import os
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// What a chat takes from the app around it: its fonts, colours and icons. A host sets its own with `.chatTheme(_:)` at
/// its root; with none, `standard` draws the system's, which is what PRHub's DESIGN.md draws today.
public struct ChatTheme: Sendable {
    /// Its values, in a box no one changes: a theme nobody changed is the same box, and SwiftUI sees the same theme.
    /// Compared field by field, `typography`'s empty roles did not always compare equal to their own copies, so as a
    /// chat opened SwiftUI took an unchanged theme for a new one and made each bubble again, its Markdown parsed again,
    /// up to five times (Agent Pager fb_3cde3642c7513c88).
    ///
    /// A host also changes the theme on its way down (`transformEnvironment(\.chatTheme) { $0.typography… }`), and
    /// SwiftUI runs that again and again: a change to what a theme already has is the theme itself, and the same change
    /// of the same theme is the same box. A box for each change made every bubble again (0.12.1).
    private final class Box: Sendable {
        let values: Values
        /// The themes lately made from this one by a change, newest last.
        private let changed = OSAllocatedUnfairLock(uncheckedState: [(field: AnyKeyPath, box: Box)]())

        init(_ values: Values) {
            self.values = values
        }

        func changing<Value: Equatable>(_ field: WritableKeyPath<Values, Value>, to value: Value) -> Box {
            if values[keyPath: field] == value {
                return self
            }
            return changed.withLockUnchecked { changed in
                if let made = changed.first(where: { $0.field == field && $0.box.values[keyPath: field] == value }) {
                    return made.box
                }
                var values = values
                values[keyPath: field] = value
                let box = Box(values)
                changed.append((field, box))
                if changed.count > 8 {
                    changed.removeFirst()
                }
                return box
            }
        }
    }

    private struct Values: Sendable {
        var font: @Sendable (Font.TextStyle) -> Font
        var code: @MainActor @Sendable (Text) -> AnyView
        var ink: Color
        var inkQuiet: Color
        var onBubble: Color
        var groundPage: Color
        var groundCard: Color
        var pictureGround: Color
        var groundFill: Color
        var line: Color
        var toneGood: Color
        var toneBad: Color
        var toneWaiting: Color
        var typography: ChatTypography
        var spacing: ChatSpacing
        var controlSize: ControlSize
        var symbols: Symbols
        var controls = Controls()
    }

    private var box: Box

    /// A text style's font: the bubble's words are `.callout`, a time `.caption2`.
    public var font: @Sendable (Font.TextStyle) -> Font {
        get { box.values.font }
        set {
            // Two closures cannot be compared: a change is always another theme.
            var values = box.values
            values.font = newValue
            box = Box(values)
        }
    }

    /// A fenced code block's words in a message.
    public var code: @MainActor @Sendable (Text) -> AnyView {
        get { box.values.code }
        set {
            // Two closures cannot be compared: a change is always another theme.
            var values = box.values
            values.code = newValue
            box = Box(values)
        }
    }

    /// Words, and quiet words (a time, a tool call).
    public var ink: Color {
        get { box.values.ink }
        set { box = box.changing(\.ink, to: newValue) }
    }

    public var inkQuiet: Color {
        get { box.values.inkQuiet }
        set { box = box.changing(\.inkQuiet, to: newValue) }
    }

    /// Words on the person's own bubble, which is the tint.
    public var onBubble: Color {
        get { box.values.onBubble }
        set { box = box.changing(\.onBubble, to: newValue) }
    }

    /// The page under the chat, and a box on it.
    public var groundPage: Color {
        get { box.values.groundPage }
        set { box = box.changing(\.groundPage, to: newValue) }
    }

    public var groundCard: Color {
        get { box.values.groundCard }
        set { box = box.changing(\.groundCard, to: newValue) }
    }

    /// The full-screen screenshot viewer stays dark even when the host chooses a light paper theme.
    public var pictureGround: Color {
        get { box.values.pictureGround }
        set { box = box.changing(\.pictureGround, to: newValue) }
    }

    /// Behind a table's header.
    public var groundFill: Color {
        get { box.values.groundFill }
        set { box = box.changing(\.groundFill, to: newValue) }
    }

    /// A hairline: a box's border.
    public var line: Color {
        get { box.values.line }
        set { box = box.changing(\.line, to: newValue) }
    }

    /// Delivered, a problem, and waiting (an agent paused).
    public var toneGood: Color {
        get { box.values.toneGood }
        set { box = box.changing(\.toneGood, to: newValue) }
    }

    public var toneBad: Color {
        get { box.values.toneBad }
        set { box = box.changing(\.toneBad, to: newValue) }
    }

    public var toneWaiting: Color {
        get { box.values.toneWaiting }
        set { box = box.changing(\.toneWaiting, to: newValue) }
    }

    /// Semantic host typography; unset roles continue to use `font`, including later mutations of it.
    public var typography: ChatTypography {
        get { box.values.typography }
        set { box = box.changing(\.typography, to: newValue) }
    }

    public var spacing: ChatSpacing {
        get { box.values.spacing }
        set { box = box.changing(\.spacing, to: newValue) }
    }

    public var controlSize: ControlSize {
        get { box.values.controlSize }
        set { box = box.changing(\.controlSize, to: newValue) }
    }

    public var symbols: Symbols {
        get { box.values.symbols }
        set { box = box.changing(\.symbols, to: newValue) }
    }

    /// The action buttons' style and the Reply button's words (`Controls`).
    public var controls: Controls {
        get { box.values.controls }
        set { box = box.changing(\.controls, to: newValue) }
    }

    /// The SF Symbols a chat draws, by what they mean.
    public struct Symbols: Equatable, Sendable {
        public var toolCall = "wrench.and.screwdriver"
        public var copy = "doc.on.doc"
        public var askAI = "questionmark.bubble"
        /// No longer drawn: the delivery ticks draw their own (`DeliveryTickMarks`). Kept so a host that sets it builds.
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
        /// A question's Reply button.
        public var reply = "square.and.pencil"
        /// Back to a chat's newest words, from higher up it (`ChatView`).
        public var scrollToEnd = "arrow.down"

        public init() {}
    }

    /// The host app's colour of this name when its asset catalog has one, else `fallback`: a missing named colour draws
    /// nothing, so a host without these assets would show no "Needs you" or error text at all.
    public static func named(_ name: String, or fallback: Color) -> Color {
        #if canImport(UIKit)
        UIColor(named: name) != nil ? Color(name) : fallback
        #elseif canImport(AppKit)
        NSColor(named: name) != nil ? Color(name) : fallback
        #else
        fallback
        #endif
    }

    public init(
        font: @escaping @Sendable (Font.TextStyle) -> Font = ChatTheme.systemFont,
        code: @escaping @MainActor @Sendable (Text) -> AnyView = ChatTheme.systemCode,
        ink: Color = .primary, inkQuiet: Color = .secondary, onBubble: Color = .white,
        groundPage: Color = ChatTheme.systemGroundPage, groundCard: Color = ChatTheme.systemGroundCard,
        groundFill: Color = ChatTheme.systemGroundFill, pictureGround: Color = .black, line: Color = ChatTheme.systemLine,
        toneGood: Color = ChatTheme.named("ToneGood", or: .green), toneBad: Color = ChatTheme.named("ToneBad", or: .red),
        toneWaiting: Color = ChatTheme.named("ToneWaiting", or: .orange), symbols: Symbols = Symbols(),
        typography: ChatTypography = ChatTypography(), spacing: ChatSpacing = ChatSpacing(),
        controlSize: ControlSize = .large
    ) {
        box = Box(Values(
            font: font, code: code, ink: ink, inkQuiet: inkQuiet,
            onBubble: onBubble, groundPage: groundPage, groundCard: groundCard, pictureGround: pictureGround,
            groundFill: groundFill, line: line, toneGood: toneGood, toneBad: toneBad, toneWaiting: toneWaiting,
            typography: typography, spacing: spacing, controlSize: controlSize, symbols: symbols
        ))
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
