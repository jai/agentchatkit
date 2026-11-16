import AgentChatKit
import SwiftUI

/// Deliberately uses String route values, the same type as the item IDs. Only this host registers destinations.
struct DemoHostThreadList: View {
    private struct Thread: Identifiable {
        let id: String
        let title: String
    }

    var usesValueNavigation = false
    @State private var threads = [Thread(id: "alpha", title: "Alpha host thread"),
                                  Thread(id: "beta", title: "Beta host thread"),
                                  Thread(id: "read-only", title: "Read-only host thread")]
    @State private var selection: String?
    @State private var opened = "none"
    @State private var opens = 0
    @State private var archives = 0
    @State private var deletes = 0
    @State private var failNext = false

    var body: some View {
        ChatThreadList(items: threads, title: \.title, actions: actions,
                       rowIdentifier: { "sessionRow-\($0.id)" }, selection: $selection, open: openAction) { thread in
            hostRow(thread)
        } header: {
            Button("New host thread") {
                guard !threads.contains(where: { $0.id == "new" }) else { return }
                threads.append(Thread(id: "new", title: "New host thread"))
            }
            .accessibilityIdentifier("host-new")
        } footer: {
            Text(threads.isEmpty ? "Host empty state" : "Host footer · ready")
                .accessibilityIdentifier("host-footer")
        }
        .navigationDestination(for: String.self) { route in
            Text("Host route: \(route)").accessibilityIdentifier("host-route")
        }
        .navigationTitle("Host threads")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading) {
                Toggle("Fail next action", isOn: $failNext)
                Text("Selection: \(selection ?? "none")").accessibilityIdentifier("host-selection")
                Text("Opened: \(opened), Open calls: \(opens)").accessibilityIdentifier("host-open")
                DemoFixtureNotice(text: "Archive calls: \(archives), Delete calls: \(deletes)")
            }
            .padding(.horizontal, ChatSpace.md)
        }
    }

    private var openAction: ((Thread) -> Void)? {
        guard !usesValueNavigation else { return nil }
        return { thread in open(thread) }
    }

    @ViewBuilder private func hostRow(_ thread: Thread) -> some View {
        if usesValueNavigation {
            NavigationLink(value: "host:\(thread.id)") { label(thread) }
        } else {
            #if os(macOS)
            // Native List owns mouse/arrow selection. Return calls the host's open callback above.
            label(thread)
            #else
            Button { selection = thread.id; open(thread) } label: { label(thread) }
                .buttonStyle(.plain)
            #endif
        }
    }

    private func label(_ thread: Thread) -> some View {
        ChatThreadRow(title: thread.title, context: "Host context", about: "Host selection and action hooks",
                      identifiers: .init(row: "sessionRow-\(thread.id)")) {
            Text("◈")
        } accessory: {
            Text("Ready").accessibilityIdentifier("host-status-\(thread.id)")
        } chips: {
            Text("Host chip").accessibilityIdentifier("host-chip-\(thread.id)")
        }
        .contentShape(.rect)
    }

    private func open(_ thread: Thread) {
        opened = thread.id
        opens += 1
    }

    private func actions(_ thread: Thread) -> ChatThreadActions {
        guard thread.id != "read-only" else { return .init() }
        return ChatThreadActions(archive: {
            archives += 1
            try? await Task.sleep(for: .seconds(2))
            if failNext {
                failNext = false
                return .failure(ChatActionError("Host archive failed"))
            }
            threads.removeAll { $0.id == thread.id }
            return .success(())
        }, delete: {
            deletes += 1
            try? await Task.sleep(for: .seconds(2))
            if failNext {
                failNext = false
                return .failure(ChatActionError("Host delete failed"))
            }
            threads.removeAll { $0.id == thread.id }
            return .success(())
        }, identifiers: .init(archive: "archive-\(thread.id)", delete: "delete-\(thread.id)",
                              confirmDelete: "confirm-\(thread.id)", cancelDelete: "cancel-\(thread.id)",
                              dismissError: "dismiss-\(thread.id)", progress: "pending-\(thread.id)"))
            .menuItems {
                Button("Open host thread") { open(thread) }
                    .accessibilityIdentifier("host-open-\(thread.id)")
            }
    }
}
