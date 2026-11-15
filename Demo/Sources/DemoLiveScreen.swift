import AgentChatKit
import AgentChatLive
import SwiftUI

/// The Live chat, drawn from `LiveChatModel`: the header says where the stream stands, the footer is the agent at work
/// from the chat's state, and the toolbar drops the stream or takes the network away.
struct DemoLiveScreen: View {
    @Environment(\.chatTheme) private var theme
    @Bindable var chat: DemoLiveChat
    @Binding var themeChoice: DemoTheme
    @State private var readsEnd = true
    @FocusState private var focused: Bool

    var body: some View {
        ChatView(
            messages: chat.model.chatMessages, sent: chat.sentCount, readsEnd: $readsEnd, focus: $focused,
            isSending: chat.isSending
        ) { _ in
            EmptyView()
        } header: {
            Text(chat.status)
                .font(theme.font(.footnote))
                .foregroundStyle(theme.inkQuiet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ChatSpace.xs)
                .accessibilityIdentifier("demo-live-status")
        } footer: {
            if let state = chat.model.chat.state, state.working {
                WorkingLine(activity: state.activity ?? "Working")
            }
        } composer: {
            SessionComposer(draft: $chat.draft, isSending: chat.isSending, send: chat.sendDraft, focused: $focused)
                .composerBar()
        }
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
                Button(
                    chat.isOnline ? "Go offline" : "Go online",
                    systemImage: chat.isOnline ? "wifi" : "wifi.slash"
                ) {
                    chat.setOnline(!chat.isOnline)
                }
                .accessibilityIdentifier("demo-live-network")
                Menu("Theme", systemImage: "paintpalette") {
                    Picker("Theme", selection: $themeChoice) {
                        ForEach(DemoTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
        }
    }
}
