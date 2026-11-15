import AgentChatKit
import SwiftUI

struct DemoDeliveryScreen: View {
    @State private var state = ReplyDeliveryState.failed
    @State private var retries = 0
    @State private var cancels = 0
    @State private var busy = false

    var body: some View {
        VStack(alignment: .trailing, spacing: ChatSpace.lg) {
            Text("A fixture reply")
            SentReplyStatus(
                state: state, text: state == .removed ? "Cancelled" : "Fixture delivery failed",
                about: "A fixture reply", isSending: busy,
                retry: retryAction,
                cancel: cancelAction,
                identifiers: ids
            )
            Button("Reset delivery") { state = .failed }
            SentReplyStatus(state: .pending(), text: "Sent", about: "Gateway received it", identifiers: ids)
            SentReplyStatus(state: .delivered, text: "Delivered", about: "Agent received it", identifiers: ids)
            DemoFixtureNotice(text: "Retry calls: \(retries), Cancel calls: \(cancels)")
        }
        .padding(ChatSpace.md)
        .navigationTitle("Delivery status")
    }

    private var retryAction: (() -> Void)? {
        guard state == .failed else { return nil }
        return { retry() }
    }

    private var cancelAction: (() -> Void)? {
        guard state == .failed else { return nil }
        return { cancel() }
    }

    private var ids: ReplyStatusIdentifiers {
        DemoAdoptionSettings.customIDs
            ? .init(status: "host-reply-status", sentTicks: "host-sent", deliveredTicks: "host-delivered",
                    retry: "finder-message-retry", cancel: "finder-message-cancel") : .init()
    }

    private func retry() {
        retries += 1
        busy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            state = .delivered
            busy = false
        }
    }

    private func cancel() {
        cancels += 1
        state = .removed
    }
}
