import SwiftUI

/// Context and its right-hand status, marked object title, About body, then host chips.
public struct ChatThreadRow<Accessory: View, Chips: View>: View {
    @Environment(\.chatTheme) private var theme
    public var title: String
    public var context: String?
    public var about: String?
    public var identifiers: ChatThreadRowIdentifiers
    private let titleMark: AnyView?
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
                    status
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                if let titleMark { titleMark.chatIdentifier(identifiers.titleMark) }
                Text(title)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .chatIdentifier(identifiers.title)
                if context == nil || context?.isEmpty == true { status }
            }
            .chatTextStyle(.objectTitle)
            if let about {
                Text("About: \(about)")
                    .chatTextStyle(.body)
                    .foregroundStyle(theme.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .chatIdentifier(identifiers.about)
            }
            chips.chatTextStyle(.meta).chatIdentifier(identifiers.chips)
        }
        .padding(.vertical, theme.spacing.xs)
        .accessibilityElement(children: .contain)
        .chatIdentifier(identifiers.row)
    }

    private var status: some View {
        accessory.chatTextStyle(.meta)
            .fixedSize(horizontal: false, vertical: true)
            .chatIdentifier(identifiers.status)
    }
}
