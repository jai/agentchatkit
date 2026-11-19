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
            DeliveryTickMarks(count: ticks.rawValue)
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

/// The ticks themselves, drawn as a messaging app draws them: one tick, or a second tick a little along whose short
/// arm would only cross the first, so only its long arm is drawn. They grow with the text.
struct DeliveryTickMarks: View {
    let count: Int
    @ScaledMetric(relativeTo: .caption2) private var width = 9.0

    var body: some View {
        let height = width * 7 / 9
        let gap = width * ChatStyle.tickGap
        let style = StrokeStyle(lineWidth: width * 0.2, lineCap: .round, lineJoin: .round)
        ZStack(alignment: .leading) {
            Tick(arms: .both).stroke(style: style).frame(width: width, height: height)
            if count > 1 {
                Tick(arms: .long).stroke(style: style).frame(width: width, height: height).offset(x: gap)
            }
        }
        .frame(width: count > 1 ? width + gap : width, height: height, alignment: .leading)
    }

    private struct Tick: Shape {
        enum Arms { case both, long }
        let arms: Arms

        func path(in rect: CGRect) -> Path {
            let corner = CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.12)
            var path = Path()
            if arms == .both {
                path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
                path.addLine(to: corner)
            } else {
                path.move(to: corner)
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return path
        }
    }
}
