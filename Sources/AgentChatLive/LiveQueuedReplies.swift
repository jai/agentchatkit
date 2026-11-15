import AgentChatKit
import SwiftUI

/// The authoritative queued messages, above the host's composer. No second queue or polling controller.
public struct LiveQueuedReplies: View {
    @Environment(\.chatTheme) private var theme
    public let controls: LiveChatControls
    @Binding private var draft: String
    public var interrupts: Bool
    private let identifiers: (LiveMessage) -> QueuedReplyIdentifiers

    public init(controls: LiveChatControls, draft: Binding<String>, interrupts: Bool = false,
                identifiers: @escaping (LiveMessage) -> QueuedReplyIdentifiers = { _ in .init() }) {
        self.controls = controls
        _draft = draft
        self.interrupts = interrupts
        self.identifiers = identifiers
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ForEach(controls.live.chat.queuedReplies) { message in
                QueuedReplyRow(text: message.text, status: "Queued", error: controls.errors[message.id],
                               interrupts: interrupts,
                               identifiers: identifiers(message), edit: {
                    Task {
                        await controls.edit(message.id) { words in
                            // Read after suspension; preserve any words typed while removing the original.
                            draft = draft.isEmpty ? words : words + "\n\n" + draft
                        }
                    }
                }, remove: {
                    Task { await controls.remove(message.id) }
                }, sendNow: {
                    Task { await controls.sendNow(message.id) }
                })
                .disabled(controls.busy.contains(message.id))
            }
        }
    }
}
