import Testing
@testable import AgentChatKit

struct ReplyDeliveryStateTests {
    @Test func gatewayReceiptIsOneTickAndAgentReceiptIsTwo() {
        #expect(ReplyDeliveryState.pending().ticks == .sent)
        #expect(ReplyDeliveryState.delivering.ticks == .sent)
        #expect(ReplyDeliveryState.delivered.ticks == .delivered)
        #expect(DeliveryTicks.sent.spoken == "Sent")
        #expect(DeliveryTicks.delivered.spoken == "Delivered")
    }

    @Test func localQueuedRetryingFailedRemovedAndUnknownSayTheirStatusWithoutTicks() {
        let states: [ReplyDeliveryState] = [.queued, .pending(attempts: 1), .pending(attempts: 3),
                                          .inThreadQueue, .failed, .removed, .other,]
        for state in states { #expect(state.ticks == nil, "\(state)") }
    }
}
