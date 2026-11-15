import SwiftUI

/// Host mutations only. Archive may hide locally; Delete means only what the supplied hook implements.
public struct ChatThreadActions {
    public typealias Action = @MainActor () async -> Result<Void, ChatActionError>
    public var archive: Action?
    public var delete: Action?

    public init(archive: Action? = nil, delete: Action? = nil) {
        self.archive = archive
        self.delete = delete
    }
}

extension View {
    /// Optional contextual/swipe actions. Missing hooks omit controls. Delete always asks before calling the host.
    public func chatThreadActions(title: String, actions: ChatThreadActions) -> some View {
        modifier(ChatThreadActionModifier(title: title, actions: actions))
    }
}

private struct ChatThreadActionModifier: ViewModifier {
    @Environment(\.chatTheme) private var theme
    let title: String
    let actions: ChatThreadActions
    private enum ActionState {
        case idle
        case confirmingDelete
        case pending
        case failed(ChatActionError)
    }
    @State private var state: ActionState = .idle
    private var pending: Bool {
        if case .pending = state { true } else { false }
    }
    private var error: ChatActionError? {
        if case let .failed(error) = state { error } else { nil }
    }

    func body(content: Content) -> some View {
        content
            .contextMenu { buttons }
            .disabled(pending)
            .overlay(alignment: .trailing) {
                if pending { ProgressView().padding(ChatSpace.sm).accessibilityLabel("Updating thread") }
            }
            .confirmationDialog("Delete \(title)?", isPresented: Binding(
                get: { if case .confirmingDelete = state { true } else { false } },
                set: { if !$0, case .confirmingDelete = state { state = .idle } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { run(actions.delete) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn’t update \(title)", isPresented: Binding(
                get: { error != nil }, set: { if !$0, case .failed = state { state = .idle } }
            )) {
                Button("OK") { state = .idle }
            } message: {
                Text(error?.message ?? "")
            }
    }

    @ViewBuilder private var buttons: some View {
        if actions.archive != nil {
            Button("Archive", systemImage: theme.symbols.archive) { run(actions.archive) }
                .disabled(pending)
        }
        if actions.delete != nil {
            Button("Delete", systemImage: theme.symbols.delete, role: .destructive) { state = .confirmingDelete }
                .disabled(pending)
        }
    }

    private func run(_ action: ChatThreadActions.Action?) {
        guard !pending, let action else { return }
        state = .pending
        Task {
            switch await action() {
            case .success: state = .idle
            case let .failure(problem): state = .failed(problem)
            }
        }
    }
}
