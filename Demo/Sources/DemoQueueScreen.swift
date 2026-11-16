import AgentChatKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class DemoQueueHost {
    var removes = 0
    var sends = 0
    var failNext = false

    func remove(_ reply: QueuedReply<String>) async -> Result<QueuedReply<String>?, ChatActionError> {
        removes += 1
        try? await Task.sleep(for: .seconds(2))
        if failNext {
            failNext = false
            return .failure(ChatActionError("The thread took it before that reached it."))
        }
        return .success(nil)
    }

    func send(_ reply: QueuedReply<String>) async -> Result<QueuedReply<String>?, ChatActionError> {
        sends += 1
        try? await Task.sleep(for: .seconds(2))
        if failNext {
            failNext = false
            return .failure(ChatActionError("Fixture send failed"))
        }
        return .success(nil)
    }
}

struct DemoQueueScreen: View {
    @State private var host: DemoQueueHost
    @State private var model: ReplyQueueController<String>
    /// A phone's compact strip, at most 160 points tall (jai/agentchatkit#19).
    var isCompact = false

    init(compact: Bool = false) {
        isCompact = compact
        let host = DemoQueueHost()
        _host = State(initialValue: host)
        _model = State(initialValue: ReplyQueueController(
            replies: [Self.reply("now", index: 2), Self.reply("edit", index: 0), Self.reply("remove", index: 1)],
            draft: "Existing draft", remove: host.remove, sendNow: host.send
        ))
    }

    private static func reply(_ id: String, index: Int) -> QueuedReply<String> {
        QueuedReply(id: id, clientRef: id, text: "Queue \(id)", createdAt: Date(timeIntervalSince1970: Double(index)),
                    statusText: "Queued, goes when the thread finishes this turn")
    }

    var body: some View {
        @Bindable var host = host
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: ChatSpace.md) {
                ThreadQueuedReplies(model: model, interrupts: true, identifiers: { reply in
                    DemoAdoptionSettings.customIDs ? QueuedReplyIdentifiers(
                        row: "queue-\(reply.id)", text: "queue-text-\(reply.id)", status: "queue-status-\(reply.id)",
                        edit: "edit-\(reply.id)", remove: "remove-\(reply.id)", sendNow: "send-\(reply.id)"
                    ) : .init()
                })
                .compact(isCompact)
                .maxHeight(isCompact ? 160 : nil)
                .modifier(DemoStripName(isNamed: isCompact))
                TextEditor(text: $model.draft)
                    .frame(minHeight: ChatStyle.attachmentSize)
                    .accessibilityLabel("Draft")
                    .accessibilityIdentifier("fixture-queue-draft")
                Toggle("Fail next action", isOn: $host.failNext)
                Toggle("Offer Send now", isOn: $model.offersSendNow)
                Button("Queue with Send now intent") {
                    let reply = Self.reply("once", index: 3)
                    model.sendNowWhenQueued(clientRef: reply.clientRef)
                    model.replaceReplies(model.replies.filter { $0.id != reply.id } + [reply])
                    Task { await model.sendNowWhereQueued() }
                }
                Button("Refresh queued snapshot") {
                    // Repeated stale host snapshots must never re-issue the composer intent.
                    model.replaceReplies(model.replies.filter { $0.id != "once" } + [Self.reply("once", index: 3)])
                    Task { await model.sendNowWhereQueued() }
                }
            }
            .padding(ChatSpace.md)
        }
        .navigationTitle("Reply queue")
        .safeAreaInset(edge: .bottom) {
            DemoFixtureNotice(text: "Remove calls: \(host.removes), Send now calls: \(host.sends)")
        }
    }
}

/// The compact strip as one element, so its test can measure it; the full strip's tests find its rows directly.
private struct DemoStripName: ViewModifier {
    let isNamed: Bool

    func body(content: Content) -> some View {
        if isNamed {
            content.accessibilityElement(children: .contain).accessibilityIdentifier("queue-strip")
        } else {
            content
        }
    }
}
