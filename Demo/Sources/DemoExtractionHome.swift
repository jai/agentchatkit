import AgentChatKit
import SwiftUI

/// Independent host fixtures; the original scripted tour and long chat keep their original flows.
struct DemoExtractionHome: View {
    var body: some View {
        List {
            NavigationLink("Thread list") { DemoThreadList() }
            NavigationLink("Reply queue") { DemoQueueScreen() }
            NavigationLink("Delivery status") { DemoDeliveryScreen() }
            NavigationLink("Question") { DemoQuestionScreen() }
            NavigationLink("Sent screenshots") { DemoScreenshotsScreen() }
            NavigationLink("Videos") { DemoVideoScreen() }
        }
        .navigationTitle("Shared pieces")
    }
}

struct DemoFixtureNotice: View {
    @Environment(\.chatTheme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(theme.font(.caption))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ChatSpace.md)
            .background(theme.groundCard)
            .accessibilityIdentifier("fixture-notice")
    }
}
