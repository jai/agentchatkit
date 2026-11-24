import AgentChatKit
import SwiftUI

/// A composer whose send button's long-press offers "Send now", as Agent Pager's does for a thread at work.
struct DemoComposerSendNow: View {
    @State var draft = ""
    var isSending = false
    @State private var notice = "Nothing sent"
    @State private var readsEnd = true
    @FocusState private var focused: Bool

    var body: some View {
        ChatView(
            messages: [ChatMessage(id: "greeting", role: .theirs, text: "Working on it.")], sent: 0,
            readsEnd: $readsEnd, focus: $focused, extras: { _ in EmptyView() }, header: { EmptyView() },
            footer: { Text(notice).accessibilityIdentifier("fixture-notice") }
        ) {
            SessionComposer(
                draft: $draft, isSending: isSending, send: { sent("Sent") }, focused: $focused,
                sendNow: SessionComposer.SendNow(label: "Send now") { sent("Sent now") }
            )
            .composerBar()
        }
        .navigationTitle("Send now")
    }

    private func sent(_ how: String) {
        notice = "\(how): \(draft)"
        draft = ""
    }
}
