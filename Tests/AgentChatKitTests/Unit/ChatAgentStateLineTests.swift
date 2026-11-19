@testable import AgentChatKit
import Testing

/// A thread row's agent state in words (jai/agentchatkit#25).
struct ChatAgentStateLineTests {
    @Test func eachStateHasItsWords() {
        #expect(ChatAgentStateLine.words(.working("Searching threads")) == "Searching threads…")
        #expect(ChatAgentStateLine.words(.working("Reading…")) == "Reading…")
        #expect(ChatAgentStateLine.words(.needsYou) == "Needs you")
        #expect(ChatAgentStateLine.words(.idle) == "Idle")
        var labels = ChatAgentStateLabels()
        labels.offline = "Runner offline"
        #expect(ChatAgentStateLine.words(.offline, labels: labels) == "Runner offline")
    }
}
