import AgentChatKit
import SwiftUI

struct DemoThreadList: View {
    private struct Thread: Identifiable {
        let id: String
        let title: String
    }

    @State private var threads = [
        Thread(id: "archive", title: "Archive fixture"),
        Thread(id: "delete", title: "Delete fixture"),
        Thread(id: "read-only", title: "Read-only fixture"),
    ]
    @State private var archives = 0
    @State private var deletes = 0
    @State private var failNext = false

    var body: some View {
        ChatThreadList(items: threads, title: \.title, actions: actions) { thread in
            ChatThreadRow(title: thread.title, context: "Fixture · local host", about: "Shared row and navigation") {
                Text("Waiting")
            } chips: {
                Text("Demo").font(.caption)
            }
            .padding(.horizontal, ChatSpace.lg)
            .accessibilityIdentifier("fixture-thread-\(thread.id)")
        } destination: { thread in
            Text("Opened \(thread.title)").navigationTitle(thread.title)
        }
        .navigationTitle("Thread list")
        .safeAreaInset(edge: .bottom) {
            VStack {
                Toggle("Fail next action", isOn: $failNext).padding(.horizontal, ChatSpace.md)
                DemoFixtureNotice(text: "Archive calls: \(archives), Delete calls: \(deletes)")
            }
        }
    }

    private func actions(_ thread: Thread) -> ChatThreadActions {
        guard thread.id != "read-only" else { return ChatThreadActions() }
        return ChatThreadActions(archive: {
            archives += 1
            try? await Task.sleep(for: .seconds(2))
            if failNext {
                failNext = false
                return .failure(ChatActionError("Fixture archive failed"))
            }
            // This host's Archive is local hiding. The kit makes no vendor archive call.
            threads.removeAll { $0.id == thread.id }
            return .success(())
        }, delete: {
            deletes += 1
            try? await Task.sleep(for: .seconds(2))
            if failNext {
                failNext = false
                return .failure(ChatActionError("Fixture delete failed"))
            }
            threads.removeAll { $0.id == thread.id }
            return .success(())
        })
    }
}
