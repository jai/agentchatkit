import SwiftUI

/// The host maps its delivery model here; no network or vendor state is inferred by the kit.
public enum ReplyDeliveryState: Hashable, Sendable {
    case queued
    case pending(attempts: Int = 0)
    case delivering
    case delivered
    case inThreadQueue
    case failed
    case removed
    case other

    public var ticks: DeliveryTicks? {
        switch self {
        case .pending(attempts: 0), .delivering: .sent
        case .delivered: .delivered
        case .queued, .pending, .inThreadQueue, .failed, .removed, .other: nil
        }
    }
}

/// Sent ticks, or the host's exact status wording and optional Retry/Cancel actions.
public struct SentReplyStatus: View {
    @Environment(\.chatTheme) private var theme
    public var state: ReplyDeliveryState
    public var text: String
    public var date: Date?
    public var symbol: String?
    public var about: String?
    public var isSending: Bool
    public var retry: (() -> Void)?
    public var cancel: (() -> Void)?
    public var identifiers: ReplyStatusIdentifiers

    public init(
        state: ReplyDeliveryState, text: String, date: Date? = nil, symbol: String? = nil,
        about: String? = nil, isSending: Bool = false, retry: (() -> Void)? = nil, cancel: (() -> Void)? = nil,
        identifiers: ReplyStatusIdentifiers = .init()
    ) {
        self.state = state
        self.text = text
        self.date = date
        self.symbol = symbol
        self.about = about
        self.isSending = isSending
        self.retry = retry
        self.cancel = cancel
        self.identifiers = identifiers
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.xs) {
            if let ticks = state.ticks {
                DeliveryTicksLine(ticks: ticks, date: date, about: about,
                                  identifier: ticks == .sent ? identifiers.sentTicks : identifiers.deliveredTicks)
            } else {
                Label {
                    Text(text)
                } icon: {
                    if let symbol { Image(systemName: symbol) }
                }
                .labelStyle(.chatIconText)
                .chatTextStyle(.meta)
                .foregroundStyle(state == .failed ? theme.toneBad : theme.inkQuiet)
                .multilineTextAlignment(.trailing)
                .id(StatusKey(text: text, symbol: symbol, state: state))
                .transition(.opacity)
            }
            if retry != nil || cancel != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.spacing.lg) { actionButtons }
                    VStack(alignment: .trailing, spacing: theme.spacing.sm) { actionButtons }
                }
                .chatTextStyle(.control)
                .controlSize(theme.controlSize)
                .chatControlButton(standard: .borderless)
                .disabled(isSending)
            }
        }
        .animation(ChatMotion.fold, value: text)
        .accessibilityElement(children: .contain)
        .chatIdentifier(state.ticks == nil ? identifiers.status : nil)
        .accessibilityValue(about ?? "")
    }

    @ViewBuilder private var actionButtons: some View {
        if let retry { Button("Retry", action: retry).chatIdentifier(identifiers.retry) }
        if let cancel {
            Button("Cancel", role: .destructive, action: cancel).chatIdentifier(identifiers.cancel)
        }
    }

    private struct StatusKey: Equatable, Hashable {
        let text: String
        let symbol: String?
        let state: ReplyDeliveryState
    }
}
