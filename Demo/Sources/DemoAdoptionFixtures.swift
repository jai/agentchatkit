import AgentChatKit
import SwiftUI

struct DemoAdoptionFixtures: View {
    let fixture: String

    var body: some View {
        NavigationStack {
            switch fixture {
            case let name where name.hasPrefix("live-"): DemoLiveControlsFixture(fixture: name)
            case "threads": DemoThreadList()
            case "host-threads": DemoHostThreadList()
            case "host-routes": DemoHostThreadList(usesValueNavigation: true)
            case "row": DemoThreadRows()
            case "queue": DemoQueueScreen()
            case "delivery": DemoDeliveryScreen()
            case "question": DemoQuestionScreen()
            case "screenshots": DemoScreenshotsScreen()
            case "screenshots-local": DemoScreenshotsScreen(sharesViewer: false)
            case "screenshots-conversation": DemoScreenshotConversation()
            case "message-content": DemoMessageContent()
            default: ContentUnavailableView("Unknown fixture", systemImage: "questionmark")
            }
        }
        .dynamicTypeSize(DemoAdoptionSettings.large ? .accessibility2 : .large)
    }
}

private struct DemoThreadRows: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChatSpace.lg) {
                row("context", context: "Context · host typography")
                Divider()
                row("fallback", context: nil)
            }
            .padding(ChatSpace.md)
        }
        .navigationTitle("Thread row")
    }

    private func row(_ id: String, context: String?) -> some View {
        ChatThreadRow(title: "Object title", context: context,
                      about: "Body text uses the host’s leading.\nThis second line makes line spacing visible.",
                      identifiers: DemoAdoptionSettings.rowIDs(id)) {
            Text("◈").accessibilityLabel("Host title mark")
        } accessory: {
            Text("Waiting").accessibilityIdentifier("slot-status-\(id)")
        } chips: {
            Text("Host chip").accessibilityIdentifier("slot-chip-\(id)")
        }
    }
}
