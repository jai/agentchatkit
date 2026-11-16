import AgentChatKit
import SwiftUI

/// A host drawing two agent answers itself, inside the kit's bubbles: a link card that opens what it names, and a meal
/// card that logs the meal. The other messages are the kit's Markdown and Jai's words.
struct DemoMessageContent: View {
    @State private var host = DemoMessageContentHost()
    @State private var readsEnd = true
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let messages = [
        ChatMessage(id: "ask", role: .mine, text: "What changed, and what was lunch?"),
        ChatMessage(id: "plain", role: .theirs, text: "Plain **Markdown** from the agent."),
        ChatMessage(id: "links", role: .theirs, text: "RAW links: PR #12"),
        ChatMessage(id: "meal", role: .theirs, text: "RAW meal: 640 kcal"),
    ]

    var body: some View {
        ChatView(messages: messages, sent: messages.count, readsEnd: $readsEnd, focus: $focused) { _ in
            EmptyView()
        } header: {
            EmptyView()
        } footer: {
            ChatWorkingLine(activity: "Searching threads")
            DemoFixtureNotice(text: host.notice)
        } composer: {
            SessionComposer(draft: $draft, isSending: false, send: {}, focused: $focused)
                .composerBar()
        }
        .chatMessageContent(when: { $0.id == "links" || $0.id == "meal" }) { [host] message in
            if message.id == "links" {
                Button("Open PR #12", systemImage: "arrow.triangle.pull") { host.opened.append("PR #12") }
                    .accessibilityIdentifier("card-link-pr12")
            } else {
                DemoMealCard(host: host)
            }
        }
        .navigationTitle("Host content")
    }
}

@MainActor
@Observable
final class DemoMessageContentHost {
    var opened: [String] = []
    var logged = 0
    var notice: String { "Opened: \(opened.joined(separator: ", ")); Logged: \(logged)" }
}

private struct DemoMealCard: View {
    let host: DemoMessageContentHost

    var body: some View {
        VStack(alignment: .leading, spacing: ChatSpace.xs) {
            Text("Lunch").font(.headline)
            Grid(alignment: .leading) {
                GridRow { Text("kcal"); Text("protein"); Text("carbs") }.foregroundStyle(.secondary)
                GridRow { Text("640"); Text("32 g"); Text("71 g") }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("card-meal-figures")
            Button(host.logged == 0 ? "Log it" : "Logged") { host.logged += 1 }
                .disabled(host.logged > 0)
                .accessibilityIdentifier("card-log")
        }
    }
}
