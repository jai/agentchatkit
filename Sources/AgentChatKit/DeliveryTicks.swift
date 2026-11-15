import SwiftUI

/// How far a message of Jai's has got, as ticks beside its time, as a messaging app shows it: one once the Worker has
/// it, two once the agent has it. A message still on its way, or failed, has none: its status says so in words.
/// Every chat draws them: a thread in Agent Pager, Ask AI on a PR.
public enum DeliveryTicks: Int, Equatable, Sendable {
    case sent = 1
    case delivered = 2

    /// What VoiceOver says for them.
    public var spoken: String {
        switch self {
        case .sent: "Sent"
        case .delivered: "Delivered"
        }
    }
}

/// Under one of Jai's bubbles: its time, then its ticks, the second over the first.
public struct DeliveryTicksLine: View {
    @Environment(\.chatTheme) private var theme
    public let ticks: DeliveryTicks
    public let date: Date?
    /// The message's words, as its value, so the line can be found by the message it is under.
    public var about: String?
    public var identifier: String?

    public init(ticks: DeliveryTicks, date: Date?, about: String? = nil, identifier: String? = nil) {
        self.ticks = ticks
        self.date = date
        self.about = about
        self.identifier = identifier ?? "reply-ticks-\(ticks.rawValue)"
    }

    public var body: some View {
        HStack(spacing: theme.spacing.xs) {
            if let date {
                Text(date.formatted(date: .omitted, time: .shortened))
            }
            HStack(spacing: ChatStyle.tickOverlap) {
                ForEach(0..<ticks.rawValue, id: \.self) { _ in
                    Image(systemName: theme.symbols.delivered)
                }
            }
            .foregroundStyle(ticks == .delivered ? theme.toneGood : theme.inkQuiet)
        }
        .chatTextStyle(.meta, fallback: ChatTextStyle(font: theme.font(.caption2)))
        .foregroundStyle(theme.inkQuiet)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([date?.formatted(date: .omitted, time: .shortened), ticks.spoken].compactMap(\.self)
            .joined(separator: ", "))
        .accessibilityValue(about ?? "")
        .chatIdentifier(identifier)
    }
}
