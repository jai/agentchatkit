import SwiftUI

/// How a status line reads: quiet words, a problem, something waiting, or done.
public enum ChatStatusTone: Sendable {
    case quiet, problem, waiting, good
}

/// One button at the end of a status line: Retry, Clear, Reconnect.
public struct ChatStatusAction {
    public var title: String
    public var systemImage: String?
    public var identifier: String?
    public var perform: () -> Void

    public init(_ title: String, systemImage: String? = nil, identifier: String? = nil, perform: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.identifier = identifier
        self.perform = perform
    }
}

/// A line of status around a chat, in one place for every app: a problem with Retry ("Couldn't read the thread"), an
/// agent or runner offline, a send error or a context chip above the reply box ("Sources/App.swift:42" with Clear).
/// Put it in `ChatView`'s header, footer or composer slot. The words, tone, symbol and button are the host's.
public struct ChatStatusLine: View {
    @Environment(\.chatTheme) private var theme
    public let text: String
    public var tone: ChatStatusTone
    public var systemImage: String?
    public var action: ChatStatusAction?
    public var identifier: String?

    public init(_ text: String, tone: ChatStatusTone = .quiet, systemImage: String? = nil,
                action: ChatStatusAction? = nil, identifier: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
        self.action = action
        self.identifier = identifier
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ChatSpace.sm) {
            if let symbol = systemImage ?? (tone == .problem ? theme.symbols.problem : nil) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .chatIdentifier(identifier)
            if let action {
                Button(action.title, systemImage: action.systemImage ?? "", action: action.perform)
                    .labelStyle(action.systemImage == nil ? AnyLabelStyle(.titleOnly) : AnyLabelStyle(.titleAndIcon))
                    .chatControlButton(standard: .borderless)
                    .chatIdentifier(action.identifier)
            }
        }
        .chatTextStyle(.meta)
        .foregroundStyle(color)
        .padding(.horizontal, ChatSpace.md)
        .accessibilityElement(children: .contain)
    }

    private var color: Color {
        switch tone {
        case .quiet: theme.inkQuiet
        case .problem: theme.toneBad
        case .waiting: theme.toneWaiting
        case .good: theme.toneGood
        }
    }
}

/// What an agent's work has cost so far, and of what limit: "$0.42 so far, of $2".
public struct ChatCostLine: View {
    public let spent: Double
    public var limit: Double?
    public var currencyCode: String
    public var identifier: String?

    public init(spent: Double, limit: Double? = nil, currencyCode: String = "USD", identifier: String? = nil) {
        self.spent = spent
        self.limit = limit
        self.currencyCode = currencyCode
        self.identifier = identifier
    }

    public var body: some View {
        ChatStatusLine(Self.words(spent: spent, limit: limit, currencyCode: currencyCode), identifier: identifier)
    }

    /// The line's words. Whole amounts show no cents ("$2"); others show two places ("$0.42").
    public static func words(spent: Double, limit: Double?, currencyCode: String = "USD",
                             locale: Locale = .current) -> String {
        let spentWords = amount(spent, currencyCode, locale) + " so far"
        guard let limit else {
            return spentWords
        }
        return spentWords + ", of " + amount(limit, currencyCode, locale)
    }

    private static func amount(_ value: Double, _ code: String, _ locale: Locale) -> String {
        let whole = value == value.rounded()
        return value.formatted(.currency(code: code).locale(locale).precision(.fractionLength(whole ? 0 : 2)))
    }
}

/// A label style chosen at run time.
private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
