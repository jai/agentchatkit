import SwiftUI

/// Shared phone/Mac thread heading. Hosts supply status, chips and navigation without vendor semantics.
public struct ChatThreadRow<Accessory: View, Chips: View>: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public var title: String
    public var context: String?
    public var about: String?
    private let accessory: Accessory
    private let chips: Chips

    public init(
        title: String, context: String? = nil, about: String? = nil,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder chips: () -> Chips
    ) {
        self.title = title
        self.context = context
        self.about = about
        self.accessory = accessory()
        self.chips = chips()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ChatSpace.xs) {
            if let context {
                Text(context).font(theme.font(.caption)).foregroundStyle(theme.inkQuiet)
            }
            headingLayout {
                Text(title)
                    .font(theme.font(.headline))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                accessory
            }
            if let about {
                Text("About: \(about)")
                    .font(theme.font(.subheadline)).foregroundStyle(theme.inkQuiet)
            }
            chips
        }
        .padding(.vertical, ChatSpace.xs)
        .accessibilityElement(children: .contain)
    }

    private var headingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ChatSpace.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ChatSpace.sm))
    }
}
