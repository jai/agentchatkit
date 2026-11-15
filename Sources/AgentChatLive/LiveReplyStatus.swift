import AgentChatKit
import SwiftUI

/// Sent ticks and supported actions from the current stream state. Failed Retry uses the live RPC unless the host overrides it.
/// When used in ChatView.extras, clear that ChatMessage's ticks to avoid drawing them twice, and set hasExtras.
public struct LiveReplyStatus: View {
    @Environment(\.chatTheme) private var theme
    public let controls: LiveChatControls
    public let messageID: String
    public var identifiers: ReplyStatusIdentifiers
    private let retry: LiveChatControls.Retry?

    public init(controls: LiveChatControls, messageID: String, identifiers: ReplyStatusIdentifiers = .init(),
                retry: LiveChatControls.Retry? = nil) {
        self.controls = controls
        self.messageID = messageID
        self.identifiers = identifiers
        self.retry = retry
    }

    public var body: some View {
        if let message = controls.live.chat.message(messageID), message.kind == .user,
           message.status != nil, message.status != .removed {
            SentReplyStatus(state: message.deliveryState, text: message.detail ?? message.status?.rawValue ?? "",
                            date: message.date, about: message.text,
                            isSending: controls.busy.contains(messageID), retry: retryAction(message),
                            cancel: cancelAction(message), identifiers: identifiers)
            if let error = controls.errors[messageID] {
                Text(error.message).chatTextStyle(.meta).foregroundStyle(theme.toneBad)
                    .liveIdentifier(identifiers.error)
            }
        }
    }

    private func retryAction(_ message: LiveMessage) -> (() -> Void)? {
        guard message.status == .failed else { return nil }
        return { Task { await controls.retry(messageID, using: retry) } }
    }

    private func cancelAction(_ message: LiveMessage) -> (() -> Void)? {
        guard message.status == .pending || message.status == .queued || message.status == .failed else { return nil }
        return { Task { await controls.remove(messageID) } }
    }
}

public extension LiveMessage {
    /// Queued also means one tick in ACP (the generic non-live host's outbox mapping differs).
    var deliveryState: ReplyDeliveryState {
        switch status {
        case .pending, .queued: .pending()
        case .delivering: .delivering
        case .delivered: .delivered
        case .failed: .failed
        case .removed: .removed
        case nil: .other
        }
    }
}
