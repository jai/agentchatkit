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
            case "queue-compact": DemoQueueScreen(compact: true)
            case "delivery": DemoDeliveryScreen()
            case "question": DemoQuestionScreen()
            case "question-host-controls": DemoHostControls { DemoQuestionScreen() }
            case "queue-host-controls": DemoHostControls { DemoQueueScreen() }
            case "question-styled": DemoStyledQuestion()
            case "screenshots": DemoScreenshotsScreen()
            case "screenshots-local": DemoScreenshotsScreen(sharesViewer: false)
            case "screenshots-conversation": DemoScreenshotConversation()
            case "message-content": DemoMessageContent()
            case "reply-summary": DemoReplySummary(isOn: true)
            case "reply-summary-off": DemoReplySummary(isOn: false)
            case "composer-paste": DemoComposerPaste()
            case "video": DemoVideoScreen()
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

/// A host's own action buttons through its theme: borderless, and "Reply…" with a reply arrow (jai/agentchatkit#18).
struct DemoHostControls<Content: View>: View {
    @Environment(\.chatTheme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        var host = theme
        host.controls.style = .borderless
        host.controls.replyLabel = "Reply…"
        host.symbols.reply = "arrowshape.turn.up.left"
        return content.chatTheme(host)
    }
}
