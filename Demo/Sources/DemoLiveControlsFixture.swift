import AgentChatKit
import AgentChatLive
import AgentChatLiveTesting
import Observation
import SwiftUI

/// Deterministic host controls on the real ACP host (server/dev/host.ts); buttons never assign client chat state.
@MainActor
@Observable
final class DemoLiveControlsFixtureModel {
    /// A fresh session on the dev host for each launch, so a fixture starts from nothing.
    let server = LiveDevHost(base: DemoLiveChat.hostBase, session: "controls-\(UUID().uuidString.prefix(8))")
    let live: LiveChatModel
    let controls: LiveChatControls
    var draft = "Existing draft"
    var retries = 0
    var attachmentLoads = 0
    let fixture: String

    init(fixture: String) {
        self.fixture = fixture
        live = LiveChatModel(endpoint: .init(acp: server.acp, session: server.session,
                                             bearer: { _ in "fixture" }), http: server, streams: server)
        controls = LiveChatControls(live: live)
    }

    func follow() async {
        await server.setState(.running, activity: "Reading the changes")
        if fixture == "live-queue" {
            // at order differs from publication order. The strip must preserve LiveChat's order.
            await server.publish(Self.message("remove", "Remove these words", .queued, second: 2))
            await server.publish(Self.message("edit", "Edit these words", .queued, second: 1))
            await server.publish(Self.message("now", "Send these words now", .queued, second: 3))
        } else if fixture.hasPrefix("live-status") {
            await server.publish(Self.message("pending", "Pending reply", .pending))
            await server.publish(Self.message("failed", "Failed reply", .failed))
            await server.publish(Self.message("failed-remove", "Failed reply to remove", .failed))
            await server.publish(Self.message("delivered", "Delivered reply", .delivered))
        } else if fixture.hasPrefix("live-question") {
            let options: [LiveQuestion.Option] = fixture == "live-question-text" ? [] : [
                .init(id: "phone", label: "iPhone"), .init(id: "mac", label: "Mac"),
            ]
            await server.ask("Which devices need this change?", options: options,
                             multiple: fixture == "live-question-multiple", freeText: fixture != "live-question-single")
        } else {
            var update = Self.message("pictures", "Screenshot reply", .delivered)
            update = Self.withPictures(update)
            await server.publish(update)
        }
        await live.follow()
    }

    var notice: String {
        let states = live.chat.messages.map { "\($0.id)=\($0.status?.rawValue ?? "none")" }.joined(separator: ", ")
        return states + " | Retry calls: \(retries), Attachment loads: \(attachmentLoads)"
    }

    func retry(_ message: LiveMessage) async throws {
        retries += 1
        // Only the override fixture uses this host hook; the default fixture uses live.retry.
        await server.setStatus(message.id, .delivered)
    }

    func replaceQuestion() async {
        await server.ask("Choose again", options: [.init(id: "phone", label: "iPhone"), .init(id: "mac", label: "Mac")],
                         multiple: true, freeText: true)
    }

    func replacePictures() async {
        await server.publish([
            "sessionUpdate": "user_message", "messageId": "pictures",
            "content": [["type": "resource_link", "name": "replacement.png", "uri": "attachments/replacement",
                         "mimeType": "image/png"]],
        ])
    }

    private static func message(_ id: String, _ words: String, _ status: LiveMessage.Status,
                                second: Int = 0) -> JSONValue {
        ["sessionUpdate": "user_message", "messageId": .string(id),
         "content": [["type": "text", "text": .string(words)]],
         "_meta": ["agentchatkit": ["status": .string(status.rawValue),
                                    "at": .string("2026-01-01T12:00:0\(second).000Z"), "clientRef": .string("fixture-\(id)")]]]
    }

    private static func withPictures(_ update: JSONValue) -> JSONValue {
        var fields = update.object ?? [:]
        fields["content"] = [
            ["type": "resource_link", "name": "notes.txt", "uri": "attachments/notes", "mimeType": "text/plain"],
            ["type": "resource_link", "name": "broken.jpg", "uri": "attachments/broken", "mimeType": "image/jpeg"],
            ["type": "resource_link", "name": "screen.png", "uri": "attachments/screen", "mimeType": "image/png"],
            ["type": "resource_link", "name": "screen2.png", "uri": "attachments/screen2", "mimeType": "image/png"],
        ]
        return .object(fields)
    }
}

struct DemoLiveControlsFixture: View {
    @Environment(\.chatTheme) private var theme
    @State private var host: DemoLiveControlsFixtureModel
    @State private var viewing = SentScreenshotViewing()
    let sharesViewer: Bool

    init(fixture: String) {
        _host = State(initialValue: DemoLiveControlsFixtureModel(fixture: fixture))
        sharesViewer = fixture != "live-screenshots-local"
    }

    var body: some View {
        Group {
            if sharesViewer { content.presentsSentScreenshots(viewing) } else { content }
        }
        .task { await host.follow() }
        .navigationTitle("Live shared controls")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                Text(host.live.chat.state?.working == true ? "Working" : "Waiting")
                    .chatTextStyle(.meta).accessibilityIdentifier("live-working")
                LiveQueuedReplies(controls: host.controls, draft: $host.draft, identifiers: { message in
                    .init(row: "live-queue-\(message.id)", text: "live-text-\(message.id)",
                          status: "live-status-\(message.id)", edit: "live-edit-\(message.id)",
                          remove: "live-remove-\(message.id)", sendNow: "live-now-\(message.id)")
                })
                if host.fixture == "live-queue" {
                    TextEditor(text: $host.draft).frame(minHeight: 80).chatTextStyle(.body)
                        .accessibilityIdentifier("live-draft")
                    Text("Conversation: " + host.live.conversationMessages.map(\.id).joined(separator: ", "))
                        .chatTextStyle(.meta).accessibilityIdentifier("live-conversation")
                    Button("Deliver now reply") {
                        Task { await host.server.setStatus("now", .delivered) }
                    }
                    .accessibilityIdentifier("live-deliver")
                }
                ForEach(host.live.chat.messages.filter { $0.kind == .user && $0.status != .queued }) { message in
                    LiveReplyStatus(controls: host.controls, messageID: message.id,
                                    identifiers: .init(status: "live-reply-\(message.id)",
                                                       sentTicks: "live-sent-\(message.id)",
                                                       deliveredTicks: "live-delivered-\(message.id)",
                                                       retry: "live-retry-\(message.id)", cancel: "live-cancel-\(message.id)",
                                                       error: "live-error-\(message.id)"),
                                    retry: host.fixture == "live-status-override" ? host.retry : nil)
                    if host.fixture.hasPrefix("live-status"), message.status != .removed {
                        Text("ID: \(message.id), Ref: \(message.clientRef ?? "none")")
                            .chatTextStyle(.meta).accessibilityIdentifier("live-identity-\(message.id)")
                    }
                }
                if host.fixture.hasPrefix("live-status") {
                    Button("Deliver retried reply") { Task { await host.server.setStatus("failed", .delivered) } }
                        .chatTextStyle(.control).controlSize(theme.controlSize)
                        .accessibilityIdentifier("live-deliver-retry")
                }
                LiveQuestionView(controls: host.controls, identifiers: .init(
                    question: .init(question: "live-question", answer: { "live-answer-\($0)" }),
                    text: "live-answer-text", submit: "live-submit", decline: "live-decline", error: "live-question-error"
                ), choiceBehavior: host.fixture == "live-question-immediate" ? .immediate : .automatic)
                if host.fixture.hasPrefix("live-question") {
                    Button("Ask a replacement question") { Task { await host.replaceQuestion() } }
                        .chatTextStyle(.control).controlSize(theme.controlSize)
                        .accessibilityIdentifier("live-replace-question")
                }
                ForEach(host.live.chat.messages.filter { !$0.attachments.isEmpty }) { message in
                    let bytes = SampleScreenshot.png() ?? Data()
                    let model = host
                    LiveScreenshotStrip(live: host.live, messageID: message.id,
                                        identifiers: DemoAdoptionSettings.screenshotIDs) { attachment in
                        await MainActor.run { model.attachmentLoads += 1 }
                        return .success(attachment.name == "broken.jpg" ? Data() : bytes)
                    }
                }
                if host.fixture.hasPrefix("live-screenshots") {
                    Button("Replace attachments") { Task { await host.replacePictures() } }
                        .chatTextStyle(.control).controlSize(theme.controlSize)
                        .accessibilityIdentifier("live-replace-pictures")
                }
                if let answer = host.live.chat.messages.last(where: { $0.id.hasPrefix("u") }) {
                    Text(answer.text).chatTextStyle(.body).accessibilityIdentifier("live-answer-received")
                }
                DemoFixtureNotice(text: host.notice)
            }
            .padding(theme.spacing.md)
        }
    }
}
