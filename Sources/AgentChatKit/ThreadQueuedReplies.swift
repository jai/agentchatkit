import AgentChatCore
import SwiftUI

/// Above the composer, not in the conversation. The host alone says whether Send now interrupts a turn.
public struct ThreadQueuedReplies<ID: Hashable & Sendable>: View {
    @Environment(\.chatTheme) private var theme
    public let model: ReplyQueueController<ID>
    public var interrupts: Bool
    private let identifiers: (QueuedReply<ID>) -> QueuedReplyIdentifiers
    private var isCompact = false
    private var heightLimit: CGFloat?

    public init(model: ReplyQueueController<ID>, interrupts: Bool = false,
                identifiers: @escaping (QueuedReply<ID>) -> QueuedReplyIdentifiers = { _ in .init() }) {
        self.model = model
        self.interrupts = interrupts
        self.identifiers = identifiers
    }

    public var body: some View {
        Group {
            if let heightLimit {
                // As tall as its replies up to the limit, then they scroll: the reply box stays above the keyboard.
                ViewThatFits(in: .vertical) {
                    rows
                    ScrollView { rows }.scrollIndicators(.automatic)
                }
                .frame(maxHeight: heightLimit)
            } else {
                rows
            }
        }
        .animation(ChatMotion.fold, value: model.queued)
        .animation(ChatMotion.fold, value: model.errors)
    }

    /// Each reply on one line with its buttons as icons beside its status, for a phone's narrow column (under 60% of
    /// a full row's height). The buttons keep their names for VoiceOver and their touch targets.
    public func compact(_ isCompact: Bool = true) -> Self {
        var replies = self
        replies.isCompact = isCompact
        return replies
    }

    /// At most `limit` points tall; more replies than fit scroll inside it. Nil: as tall as the replies.
    public func maxHeight(_ limit: CGFloat?) -> Self {
        var replies = self
        replies.heightLimit = limit
        return replies
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ForEach(model.queued) { reply in
                row(reply).transition(.opacity)
            }
        }
    }

    private func row(_ reply: QueuedReply<ID>) -> some View {
        QueuedReplyRow(text: reply.text, status: reply.statusText, error: model.errors[reply.id],
                       interrupts: interrupts, identifiers: identifiers(reply),
                       edit: { Task { await model.edit(reply) } },
                       remove: { Task { await model.remove(reply) } },
                       sendNow: model.canSendNow ? { Task { await model.sendNow(reply) } } : nil)
            .compact(isCompact)
            .disabled(model.isBusy(reply))
    }
}

/// Stateless queue presentation shared by snapshot hosts and AgentChatLive. Actions own no reply state here.
public struct QueuedReplyRow: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public var text: String
    public var status: String
    public var error: ChatActionError?
    public var interrupts: Bool
    public var identifiers: QueuedReplyIdentifiers
    private let edit: () -> Void
    private let remove: () -> Void
    private let sendNow: (() -> Void)?
    private var isCompact = false

    public init(text: String, status: String, error: ChatActionError? = nil,
                interrupts: Bool = false, identifiers: QueuedReplyIdentifiers = .init(),
                edit: @escaping () -> Void, remove: @escaping () -> Void, sendNow: (() -> Void)? = nil) {
        self.text = text
        self.status = status
        self.error = error
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

    /// The reply on one line, its buttons as icons beside its status (`ThreadQueuedReplies.compact()`).
    public func compact(_ isCompact: Bool = true) -> Self {
        var row = self
        row.isCompact = isCompact
        return row
    }

    public var body: some View {
        Group {
            if isCompact { compactBody } else { fullBody }
        }
        .padding(theme.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.groundCard, in: .rect(cornerRadius: ChatRadius.md))
        .accessibilityElement(children: .contain)
        .chatIdentifier(identifiers.row)
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ChatQuickReply.shown(text))
                .chatTextStyle(.body)
                .chatIdentifier(identifiers.text)
                .lineLimit(1)
            if typeSize.isAccessibilitySize {
                // Beside three buttons the status was one letter ("Q…") at the largest sizes: it gets its own lines,
                // the buttons theirs. Both stop growing at the first accessibility size, so the row still leaves room
                // above the keyboard; a long press on an icon shows its name large (Large Content Viewer).
                VStack(alignment: .trailing, spacing: theme.spacing.xs) {
                    compactStatus
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: theme.spacing.xs) { compactButtons }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            } else {
                HStack(spacing: theme.spacing.xs) {
                    compactStatus.lineLimit(1)
                    Spacer(minLength: 0)
                    compactButtons
                }
            }
        }
    }

    private var compactStatus: some View {
        Text(error?.message ?? status)
            .chatTextStyle(.meta)
            .chatIdentifier(identifiers.status)
            .foregroundStyle(error != nil ? theme.toneBad : theme.inkQuiet)
    }

    /// Edit, Remove and Send now as icons, each with its name for VoiceOver and the Large Content Viewer.
    private var compactButtons: some View {
        Group {
            editAndRemove
            sendNowButton
        }
        .labelStyle(.iconOnly)
        .chatTextStyle(.control)
        // Regular chrome round an icon: the large size's padding doubled the row; the frame keeps the touch target.
        .controlSize(.regular)
        .accessibilityShowsLargeContentViewer()
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(ChatQuickReply.shown(text))
                .chatTextStyle(.body)
                .chatIdentifier(identifiers.text)
                .lineLimit(2)
            Text(error?.message ?? status)
                .chatTextStyle(.meta)
                .chatIdentifier(identifiers.status)
                .foregroundStyle(error != nil ? theme.toneBad : theme.inkQuiet)
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
        }
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
            Label("Edit", systemImage: theme.symbols.edit).frame(minWidth: isCompact ? minimumHeight : nil, minHeight: minimumHeight)
        }
        .chatControlButton()
        .chatIdentifier(identifiers.edit)
        Button(role: .destructive, action: remove) {
            Label("Remove", systemImage: theme.symbols.delete).frame(minWidth: isCompact ? minimumHeight : nil, minHeight: minimumHeight)
        }
        .chatControlButton()
        .tint(theme.toneBad)
        .chatIdentifier(identifiers.remove)
    }

    @ViewBuilder private var sendNowButton: some View {
        if let sendNow {
            Button(action: sendNow) {
                Label(interrupts ? "Send now · stops its turn" : "Send now", systemImage: theme.symbols.sendNow)
                    .frame(minWidth: isCompact ? minimumHeight : nil, minHeight: minimumHeight)
            }
            .chatControlButton(prominent: true)
            .chatIdentifier(identifiers.sendNow)
            .tint(interrupts ? theme.toneBad : .accentColor)
            .accessibilityHint(interrupts ? "Stops what the thread is doing and sends this now" : "")
        }
    }
}
