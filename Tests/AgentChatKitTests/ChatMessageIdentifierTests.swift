@testable import AgentChatKit
import Testing

/// A host's UI tests find a message by its identifier: its side, then its id (jai/agentchatkit#12).
struct ChatMessageIdentifierTests {
    @Test func eachSideHasItsOwnStart() {
        #expect(ChatMessage(id: "m1", role: .mine, text: "Hi").accessibilityIdentifier == "chat-message-you-m1")
        #expect(ChatMessage(id: "a2", role: .theirs, text: "Hello").accessibilityIdentifier == "chat-message-agent-a2")
        #expect(ChatMessage(id: "t3", role: .tool(name: "Read"), text: "File").accessibilityIdentifier == "chat-message-tool-t3")
    }
}
