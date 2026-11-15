import SwiftUI

/// Above the composer, not in the conversation. The host alone says whether Send now interrupts a turn.
public struct ThreadQueuedReplies<ID: Hashable & Sendable>: View {
    @Environment(\.chatTheme) private var theme
    public let model: ReplyQueueController<ID>
    public var interrupts: Bool

    public init(model: ReplyQueueController<ID>, interrupts: Bool = false) {
        self.model = model
        self.interrupts = interrupts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ChatSpace.sm) {
            ForEach(model.queued) { reply in
                row(reply)
            }
        }
    }

    private func row(_ reply: QueuedReply<ID>) -> some View {
        VStack(alignment: .leading, spacing: ChatSpace.xs) {
            Text(ChatQuickReply.shown(reply.text))
                .font(theme.font(.body))
                .lineLimit(2)
            Text(model.errors[reply.id]?.message ?? reply.statusText)
                .font(theme.font(.caption))
                .foregroundStyle(model.errors[reply.id] == nil ? theme.inkQuiet : theme.toneBad)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ChatSpace.sm) {
                    editAndRemove(reply)
                    Spacer(minLength: 0)
                    sendNow(reply)
                }
                VStack(alignment: .leading, spacing: ChatSpace.sm) {
                    HStack(spacing: ChatSpace.sm) { editAndRemove(reply) }
                    sendNow(reply)
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy(reply))
        }
        .padding(ChatSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.groundCard, in: .rect(cornerRadius: ChatRadius.md))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queued-reply")
    }

    @ViewBuilder private func editAndRemove(_ reply: QueuedReply<ID>) -> some View {
        Button("Edit", systemImage: theme.symbols.compose) { Task { await model.edit(reply) } }
        Button("Remove", systemImage: theme.symbols.delete, role: .destructive) {
            Task { await model.remove(reply) }
        }
        .tint(theme.toneBad)
    }

    @ViewBuilder private func sendNow(_ reply: QueuedReply<ID>) -> some View {
        if model.canSendNow {
            Button(interrupts ? "Send now · stops its turn" : "Send now", systemImage: theme.symbols.sendNow) {
                Task { await model.sendNow(reply) }
            }
            .tint(interrupts ? theme.toneBad : .accentColor)
            .accessibilityHint(interrupts ? "Stops what the thread is doing and sends this now" : "")
        }
    }
}
