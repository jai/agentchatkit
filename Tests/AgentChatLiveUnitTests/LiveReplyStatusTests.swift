import AgentChatKit
import AgentChatLive
import Testing

struct LiveReplyStatusTests {
    @Test func allStatusTicksMatchTheProfile() {
        let cases: [(LiveMessage.Status?, DeliveryTicks?)] = [
            (.pending, .sent), (.queued, .sent), (.delivering, .sent), (.delivered, .delivered),
            (.failed, nil), (.removed, nil), (nil, nil),
        ]
        for (status, expected) in cases {
            var message = LiveMessage(id: "m", kind: .user)
            message.status = status
            #expect(message.ticks == expected)
            #expect(message.deliveryState.ticks == expected)
        }
    }
}
