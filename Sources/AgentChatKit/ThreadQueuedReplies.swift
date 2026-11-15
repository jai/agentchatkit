import SwiftUI

/// Above the composer, not in the conversation. The host alone says whether Send now interrupts a turn.
public struct ThreadQueuedReplies<ID: Hashable & Sendable>: View {
    @Environment(\.chatTheme) private var theme
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
        QueuedReplyRow(text: reply.text, status: model.errors[reply.id]?.message ?? reply.statusText,
                       hasError: model.errors[reply.id] != nil, isBusy: model.isBusy(reply),
                       interrupts: interrupts, identifiers: identifiers(reply),
                       edit: { Task { await model.edit(reply) } },
                       remove: { Task { await model.remove(reply) } },
                       sendNow: model.canSendNow ? { Task { await model.sendNow(reply) } } : nil)
    }
}

/// Stateless queue presentation shared by snapshot hosts and AgentChatLive. Actions own no reply state here.
public struct QueuedReplyRow: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public var text: String
    public var status: String
    public var hasError: Bool
    public var isBusy: Bool
    public var interrupts: Bool
    public var identifiers: QueuedReplyIdentifiers
    private let edit: () -> Void
    private let remove: () -> Void
    private let sendNow: (() -> Void)?

    public init(text: String, status: String, hasError: Bool = false, isBusy: Bool = false,
                interrupts: Bool = false, identifiers: QueuedReplyIdentifiers = .init(),
                edit: @escaping () -> Void, remove: @escaping () -> Void, sendNow: (() -> Void)? = nil) {
        self.text = text
        self.status = status
        self.hasError = hasError
        self.isBusy = isBusy
        self.interrupts = interrupts
        self.identifiers = identifiers
        self.edit = edit
        self.remove = remove
        self.sendNow = sendNow
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(ChatQuickReply.shown(text))
                .chatTextStyle(.body)
                .chatIdentifier(identifiers.text)
                .lineLimit(2)
            Text(status)
                .chatTextStyle(.meta)
                .chatIdentifier(identifiers.status)
                .foregroundStyle(hasError ? theme.toneBad : theme.inkQuiet)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.spacing.sm) {
                    editAndRemove
                    Spacer(minLength: 0)
                    sendNowButton
                }
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    leftControls
                    HStack { Spacer(minLength: 0); sendNowButton }
                }
            }
            .labelStyle(.titleAndIcon)
            .chatTextStyle(.control)
            .controlSize(theme.controlSize)
            .disabled(isBusy)
        }
        .padding(theme.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.groundCard, in: .rect(cornerRadius: ChatRadius.md))
        .accessibilityElement(children: .contain)
        .chatIdentifier(identifiers.row)
    }

    @ViewBuilder private var leftControls: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.sm) { editAndRemove }
        } else {
            HStack(spacing: theme.spacing.sm) { editAndRemove }
        }
    }

    @ViewBuilder private var editAndRemove: some View {
        Button(action: edit) {
            Label("Edit", systemImage: theme.symbols.edit).frame(minHeight: minimumHeight)
        }
        .buttonStyle(.bordered)
        .chatIdentifier(identifiers.edit)
        Button(role: .destructive, action: remove) {
            Label("Remove", systemImage: theme.symbols.delete).frame(minHeight: minimumHeight)
        }
        .buttonStyle(.bordered)
        .tint(theme.toneBad)
        .chatIdentifier(identifiers.remove)
    }

    @ViewBuilder private var sendNowButton: some View {
        if let sendNow {
            Button(action: sendNow) {
                Label(interrupts ? "Send now · stops its turn" : "Send now", systemImage: theme.symbols.sendNow)
                    .frame(minHeight: minimumHeight)
            }
            .buttonStyle(.borderedProminent)
            .chatIdentifier(identifiers.sendNow)
            .tint(interrupts ? theme.toneBad : .accentColor)
            .accessibilityHint(interrupts ? "Stops what the thread is doing and sends this now" : "")
        }
    }
}
