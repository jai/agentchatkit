import AgentChatKit
import AgentChatLive
import SwiftUI

/// The Live chat, drawn from `LiveChatModel`: the header says where the stream stands, the footer is the agent at work
/// from the chat's state, and the toolbar drops the stream, restarts the host's connections or takes the network away.
struct DemoLiveScreen: View {
    @Environment(\.chatTheme) private var theme
    @Bindable var chat: DemoLiveChat
    @Binding var themeChoice: DemoTheme
    @State private var readsEnd = true
    @FocusState private var focused: Bool
    @State private var controls: LiveChatControls
    @State private var viewing = SentScreenshotViewing()

    init(chat: DemoLiveChat, themeChoice: Binding<DemoTheme>) {
        self.chat = chat
        _themeChoice = themeChoice
        _controls = State(initialValue: LiveChatControls(live: chat.model))
    }

    private var messages: [ChatMessage] {
        chat.model.conversationMessages.map { original in
            var message = original
            if let live = chat.model.chat.message(message.id) {
                message.hasExtras = live.kind == .user || !live.attachments.isEmpty
                if live.kind == .user, live.status != nil {
                    message.ticks = nil // LiveReplyStatus owns these, including its host IDs/actions.
                    message.date = nil
                }
            }
            return message
        }
    }

    var body: some View {
        ChatView(
            messages: messages, sent: chat.sentCount, readsEnd: $readsEnd, focus: $focused,
            isSending: chat.isSending
        ) { message in
            LiveReplyStatus(controls: controls, messageID: message.id)
            LiveScreenshotStrip(live: chat.model, messageID: message.id) { _ in
                .failure(ChatActionError("The demo host does not serve attachment bytes."))
            }
        } header: {
            Text(chat.status)
                .font(theme.font(.footnote))
                .foregroundStyle(theme.inkQuiet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ChatSpace.xs)
                .accessibilityIdentifier("demo-live-status")
        } footer: {
            if chat.model.chat.question != nil {
                LiveQuestionView(controls: controls, identifiers: .init(
                    question: .init(answer: { "demo-live-option-\($0)" }),
                    text: "demo-live-answer-text", submit: "demo-live-answer-submit", decline: "demo-live-decline"
                ), choiceBehavior: .immediate)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("demo-live-question")
            } else if let state = chat.model.chat.state, state.working {
                ChatWorkingLine(activity: state.activity ?? "Working")
            }
        } composer: {
            VStack(spacing: theme.spacing.sm) {
                LiveQueuedReplies(controls: controls, draft: $chat.draft, identifiers: { message in
                    .init(row: "demo-live-queue-\(message.id)", edit: "demo-live-edit-\(message.id)",
                          remove: "demo-live-remove-\(message.id)", sendNow: "demo-live-now-\(message.id)")
                })
                SessionComposer(draft: $chat.draft, isSending: chat.isSending, send: chat.sendDraft, focused: $focused)
            }
            .composerBar()
        }
        .presentsSentScreenshots(viewing)
        .background(theme.groundPage)
        .navigationTitle("Live")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await chat.model.follow()
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Drop the stream", systemImage: "bolt.horizontal") {
                    chat.dropStream()
                }
                .accessibilityIdentifier("demo-live-drop")
                Button("Restart the host", systemImage: "arrow.clockwise.circle") {
                    chat.restartHost()
                }
                .accessibilityIdentifier("demo-live-restart")
                Button(
                    chat.isOnline ? "Go offline" : "Go online",
                    systemImage: chat.isOnline ? "wifi" : "wifi.slash"
                ) {
                    chat.setOnline(!chat.isOnline)
                }
                .accessibilityIdentifier("demo-live-network")
            }
        }
    }
}
