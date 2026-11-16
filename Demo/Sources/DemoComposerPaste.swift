import AgentChatKit
import SwiftUI

/// A chat whose composer takes pictures: Command-V with a picture on the clipboard attaches it, with words it pastes
/// them (jai/agentchatkit#10).
struct DemoComposerPaste: View {
    @State private var attachments = ComposerAttachments()
    @State private var readsEnd = true
    @State private var draft = ""
    @FocusState private var focused: Bool
    private let messages = [ChatMessage(id: "hello", role: .theirs, text: "Paste a screenshot.")]

    var body: some View {
        ChatView(messages: messages, sent: 0, readsEnd: $readsEnd, focus: $focused) { _ in
            EmptyView()
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        } composer: {
            SessionComposer(draft: $draft, isSending: false, send: {}, focused: $focused, attachments: attachments)
                .composerBar()
        }
        .navigationTitle("Paste")
    }
}
