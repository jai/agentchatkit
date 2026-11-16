@testable import AgentChatKit
import SwiftUI
import Testing

/// The host's content for a claimed message, and what it gives in place of the words (jai/agentchatkit#11, #20).
@MainActor
struct ChatMessageContentTests {
    private let meal = ChatMessage(id: "meal", role: .theirs, text: "RAW meal")
    private let plain = ChatMessage(id: "plain", role: .theirs, text: "Words")

    @Test func theFirstFormStillBuildsAndClaims() {
        // 0.5.0's call, unchanged: no copy text or label, the bubble's menu on.
        _ = Text("chat").chatMessageContent(when: { $0.id == "meal" }) { _ in Text("Card") }
        let content = ChatMessageContent(claims: { $0.id == "meal" }, draw: { _ in AnyView(Text("Card")) })
        let drawing = content.content(for: meal)
        #expect(drawing != nil)
        #expect(drawing?.copyText == nil)
        #expect(drawing?.bubbleMenu == true)
        #expect(content.content(for: plain) == nil)
    }

    @Test func aCardGivesItsCopyTextLabelAndMenu() {
        let content = ChatMessageContent(
            claims: { _ in true }, draw: { _ in AnyView(Text("Card")) },
            copyText: { _ in "Lunch: 640 kcal" }, label: { _ in "Lunch, 640 kilocalories" }, bubbleMenu: { _ in false }
        )
        let drawing = content.content(for: meal)
        #expect(drawing?.copyText == "Lunch: 640 kcal")
        #expect(drawing?.label == "Lunch, 640 kilocalories")
        #expect(drawing?.bubbleMenu == false)
    }
}
