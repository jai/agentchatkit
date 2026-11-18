import SwiftUI

/// Context and its right-hand status, marked object title, About body, then host chips.
public struct ChatThreadRow<Accessory: View, Chips: View>: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public var title: String
    public var context: String?
    public var about: String?
    public var identifiers: ChatThreadRowIdentifiers
    private let titleMark: AnyView?
    private var gutter: CGFloat?
    private let accessory: Accessory
    private let chips: Chips

    public init(
        title: String, context: String? = nil, about: String? = nil,
        identifiers: ChatThreadRowIdentifiers = .init(),
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder chips: () -> Chips
    ) {
        self.title = title
        self.context = context
        self.about = about
        self.identifiers = identifiers
        titleMark = nil
        self.accessory = accessory()
        self.chips = chips()
    }

    public init<Mark: View>(
        title: String, context: String? = nil, about: String? = nil,
        identifiers: ChatThreadRowIdentifiers = .init(),
        @ViewBuilder titleMark: () -> Mark,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder chips: () -> Chips
    ) {
        self.title = title
        self.context = context
        self.about = about
        self.identifiers = identifiers
        self.titleMark = AnyView(titleMark())
        self.accessory = accessory()
        self.chips = chips()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if let context, !context.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                    Text(context)
                        .chatTextStyle(.meta)
                        .foregroundStyle(theme.inkQuiet)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .chatIdentifier(identifiers.context)
                    if !statusOnOwnLine { status }
                }
                .padding(.leading, pastGutter)
            }
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                if let titleMark {
                    titleMark.chatIdentifier(identifiers.titleMark)
                        .frame(width: gutter, alignment: .trailing)
                } else if let gutter {
                    Color.clear.frame(width: gutter, height: 0)
                }
                Text(title)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .chatIdentifier(identifiers.title)
                if !hasContext, !statusOnOwnLine { status }
            }
            .chatTextStyle(.objectTitle)
            if statusOnOwnLine {
                status
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, pastGutter)
            }
            if let about {
                Text("About: \(about)")
                    .chatTextStyle(.body)
                    .foregroundStyle(theme.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .chatIdentifier(identifiers.about)
                    .padding(.leading, pastGutter)
            }
            chips.chatTextStyle(.meta).chatIdentifier(identifiers.chips)
                .padding(.leading, pastGutter)
        }
        .padding(.vertical, theme.spacing.xs)
        .accessibilityElement(children: .contain)
        .chatIdentifier(identifiers.row)
    }

    private var hasContext: Bool { context?.isEmpty == false }

    /// At the accessibility text sizes the status takes a line of its own under the title: beside it, its words were
    /// cut ("Running a…") and the title had a third of the row (Jai, Agent Pager build 565).
    private var statusOnOwnLine: Bool { typeSize.isAccessibilitySize }

    /// A line under the title starts where the title does: past the gutter and the space after it.
    private var pastGutter: CGFloat { gutter.map { $0 + theme.spacing.sm } ?? 0 }

    /// The title mark hangs in a column this wide, so every row's title, and the lines under it, start at one edge
    /// whatever its mark (an app's icon, a state's). Nil: the mark sits just before the title.
    public func markGutter(_ width: CGFloat?) -> Self {
        var row = self
        row.gutter = width
        return row
    }

    private var status: some View {
        accessory.chatTextStyle(.meta)
            .fixedSize(horizontal: false, vertical: true)
            .chatIdentifier(identifiers.status)
    }
}
