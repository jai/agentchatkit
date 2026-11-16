import AgentChatKit
import SwiftUI

/// A long agent reply and a short one. "reply-summary" summarizes with a stand-in for Apple Intelligence, so the test
/// does not depend on the device; "reply-summary-off" is a host that turned summaries off (jai/agentchatkit#2).
struct DemoReplySummary: View {
    let isOn: Bool
    @State private var readsEnd = true
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let messages = [
        ChatMessage(id: "ask", role: .mine, text: "Why did the release not go out?"),
        ChatMessage(id: "long", role: .theirs, text: String(repeating: """
        CI on main waited for GitHub's runners, then one iPhone test failed once and passed on the second try. \
        The release went out once main was green.
        """, count: 6)),
        ChatMessage(id: "short", role: .theirs, text: "Done."),
    ]

    var body: some View {
        ChatView(messages: messages, sent: messages.count, readsEnd: $readsEnd, focus: $focused) { _ in
            EmptyView()
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        } composer: {
            SessionComposer(draft: $draft, isSending: false, send: {}, focused: $focused)
                .composerBar()
        }
        .chatSummaries(isOn ? Self.standIn : .off)
        .navigationTitle("Summaries")
    }

    private static let standIn = ChatSummaries(isAvailable: { true }) { _ in
        try await Task.sleep(for: .milliseconds(300))
        return "Short version: the release went out once main was green."
    }
}
