import SwiftUI

/// Above the composer, not in the conversation. The host alone says whether Send now interrupts a turn.
public struct ThreadQueuedReplies<ID: Hashable & Sendable>: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public let model: ReplyQueueController<ID>
    public var interrupts: Bool
    private let identifiers: (QueuedReply<ID>) -> QueuedReplyIdentifiers

    public init(model: ReplyQueueController<ID>, interrupts: Bool = false,
                identifiers: @escaping (QueuedReply<ID>) -> QueuedReplyIdentifiers = { _ in .init() }) {
        self.model = model
        self.interrupts = interrupts
        self.identifiers = identifiers
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ForEach(model.queued) { reply in
                row(reply).transition(.opacity)
            }
        }
        .animation(ChatMotion.fold, value: model.queued)
        .animation(ChatMotion.fold, value: model.errors)
    }

    private func row(_ reply: QueuedReply<ID>) -> some View {
        let ids = identifiers(reply)
        return VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(ChatQuickReply.shown(reply.text))
                .chatTextStyle(.body)
                .chatIdentifier(ids.text)
                .lineLimit(2)
            Text(model.errors[reply.id]?.message ?? reply.statusText)
                .chatTextStyle(.meta)
                .chatIdentifier(ids.status)
                .foregroundStyle(model.errors[reply.id] == nil ? theme.inkQuiet : theme.toneBad)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.spacing.sm) {
                    editAndRemove(reply)
                    Spacer(minLength: 0)
                    sendNow(reply)
                }
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    leftControls(reply)
                    HStack { Spacer(minLength: 0); sendNow(reply) }
                }
            }
            .labelStyle(.titleAndIcon)
            .chatTextStyle(.control)
            .controlSize(theme.controlSize)
            .disabled(model.isBusy(reply))
        }
        .padding(theme.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.groundCard, in: .rect(cornerRadius: ChatRadius.md))
        .accessibilityElement(children: .contain)
        .chatIdentifier(ids.row)
    }

    @ViewBuilder private func leftControls(_ reply: QueuedReply<ID>) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.sm) { editAndRemove(reply) }
        } else {
            HStack(spacing: theme.spacing.sm) { editAndRemove(reply) }
        }
    }

    @ViewBuilder private func editAndRemove(_ reply: QueuedReply<ID>) -> some View {
        Button("Edit", systemImage: theme.symbols.edit) { Task { await model.edit(reply) } }
            .buttonStyle(.bordered)
            .chatIdentifier(identifiers(reply).edit)
        Button("Remove", systemImage: theme.symbols.delete, role: .destructive) {
            Task { await model.remove(reply) }
        }
        .buttonStyle(.bordered)
        .tint(theme.toneBad)
        .chatIdentifier(identifiers(reply).remove)
    }

    @ViewBuilder private func sendNow(_ reply: QueuedReply<ID>) -> some View {
        if model.canSendNow {
            Button(interrupts ? "Send now · stops its turn" : "Send now", systemImage: theme.symbols.sendNow) {
                Task { await model.sendNow(reply) }
            }
            .buttonStyle(.borderedProminent)
            .chatIdentifier(identifiers(reply).sendNow)
            .tint(interrupts ? theme.toneBad : .accentColor)
            .accessibilityHint(interrupts ? "Stops what the thread is doing and sends this now" : "")
        }
    }
}
