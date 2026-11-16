@testable import AgentChatKit
import Testing

/// A grouped chat list takes each group's rows in the group's order (jai/agentchatkit#25).
struct ChatThreadGroupTests {
    private struct Thread: Identifiable, Equatable {
        let id: String
    }

    @Test func aGroupsRowsComeInItsOrderAndUnknownIDsAreLeftOut() {
        let items = [Thread(id: "a"), Thread(id: "b"), Thread(id: "c")]
        let group = ChatThreadGroup(id: "waiting", title: "Waiting on you", items: ["c", "gone", "a"])
        #expect(group.rows(from: items) == [Thread(id: "c"), Thread(id: "a")])
    }
}
