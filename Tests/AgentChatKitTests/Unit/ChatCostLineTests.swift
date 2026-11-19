@testable import AgentChatKit
import Foundation
import Testing

/// The cost line's words, as PR Hub and FeedbackKit wrote their own (jai/agentchatkit#24).
struct ChatCostLineTests {
    private let english = Locale(identifier: "en_US")

    @Test func spentAndLimitWholeAmountsShowNoCents() {
        #expect(ChatCostLine.words(spent: 0.42, limit: 2, locale: english) == "$0.42 so far, of $2")
        #expect(ChatCostLine.words(spent: 3, limit: 10, locale: english) == "$3 so far, of $10")
    }

    @Test func noLimitSaysOnlyWhatWasSpent() {
        #expect(ChatCostLine.words(spent: 1.5, limit: nil, locale: english) == "$1.50 so far")
    }
}
