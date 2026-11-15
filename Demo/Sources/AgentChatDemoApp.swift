import AgentChatKit
import SwiftUI

/// AgentChatKit's demo: a host app with two chats with a scripted agent and three looks. Launch arguments set it up
/// for UI tests and screenshots: `-DemoPace fast|slow` (the agent's speed), `-DemoChat tour|long|live` (open on a chat),
/// `-DemoTheme prHub|terminal|paper`. `-DemoChat extraction` opens independent shared-control fixtures.
@main
struct AgentChatDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoRoot()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}

struct DemoRoot: View {
    /// Seeded from `-DemoTheme`, then the toolbar's: `@AppStorage` would keep reading the launch argument over a pick.
    @State private var themeChoice: DemoTheme
    @State private var chats: [DemoChat]
    @State private var live: DemoLiveChat
    @State private var selection: String?
    @State private var column = NavigationSplitViewColumn.sidebar

    init() {
        let pace = DemoPace.current
        let tour = DemoChat(
            id: "tour", title: "Tour",
            messages: [ChatMessage(id: "greeting", role: .theirs, text: DemoScript.greeting, date: .now)],
            pace: pace
        )
        let long = DemoChat(id: "long", title: "Long chat", messages: DemoScript.longHistory(now: .now), pace: pace)
        _chats = State(initialValue: [tour, long])
        _live = State(initialValue: DemoLiveChat(pace: pace))
        let theme = UserDefaults.standard.string(forKey: "DemoTheme").flatMap { DemoTheme(rawValue: $0) }
        _themeChoice = State(initialValue: theme ?? .prHub)
        let opened = UserDefaults.standard.string(forKey: "DemoChat")
        _selection = State(initialValue: opened)
        _column = State(initialValue: opened == nil ? .sidebar : .detail)
    }

    var body: some View {
        Group {
            if let fixture = DemoAdoptionSettings.fixture {
                DemoAdoptionFixtures(fixture: fixture)
            } else {
                mainContent
            }
        }
        .chatTheme(DemoAdoptionSettings.theme(themeChoice.chat))
        .tint(themeChoice.tint)
        .preferredColorScheme(DemoAdoptionSettings.colorScheme ?? themeChoice.colorScheme)
    }

    private var mainContent: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            List(selection: $selection) {
                ForEach(chats) { chat in
                    NavigationLink(value: chat.id) {
                        Label(chat.title, systemImage: chat.id == "long" ? "text.alignleft" : "sparkles")
                    }
                    .accessibilityIdentifier("demo-chat-\(chat.id)")
                }
                NavigationLink(value: "live") {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("demo-chat-live")
                NavigationLink(value: "extraction") { Text("Shared pieces") }
                    .accessibilityIdentifier("demo-chat-extraction")
            }
            .navigationTitle("AgentChatKit")
        } detail: {
            if selection == "live" {
                DemoLiveScreen(chat: live, themeChoice: $themeChoice)
            } else if selection == "extraction" {
                NavigationStack { DemoExtractionHome() }
            } else if let chat = chats.first(where: { $0.id == selection }) {
                DemoChatScreen(chat: chat, themeChoice: $themeChoice)
                    .id(chat.id)
            } else {
                ContentUnavailableView("Pick a chat", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }
}
