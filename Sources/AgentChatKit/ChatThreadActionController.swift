import AgentChatCore
import Observation

/// One tagged state for every entry point of a row action: menu, phone swipe and Mac Delete.
@MainActor
@Observable
final class ChatThreadActionController {
    enum Operation { case archive, delete }
    enum State {
        case idle
        case confirmingDelete
        case pending(Operation)
        case failed(Operation, ChatActionError)
    }

    private(set) var state: State = .idle

    var isIdle: Bool { if case .idle = state { true } else { false } }
    var isPending: Bool { if case .pending = state { true } else { false } }
    var isConfirmingDelete: Bool { if case .confirmingDelete = state { true } else { false } }
    var error: ChatActionError? { if case let .failed(_, error) = state { error } else { nil } }

    func requestDelete(_ actions: ChatThreadActions) {
        guard isIdle, actions.delete != nil else { return }
        state = .confirmingDelete
    }

    func dismissConfirmation() {
        if isConfirmingDelete { state = .idle }
    }

    func dismissError() {
        if case .failed = state { state = .idle }
    }

    func archive(_ actions: ChatThreadActions) {
        guard isIdle, let action = actions.archive else { return }
        run(.archive, action: action)
    }

    func confirmDelete(_ actions: ChatThreadActions) {
        // The native dialog may reset its presentation binding before invoking the chosen button.
        // Only that confirmation button calls this method; keyboard/menu/swipe always request first.
        guard isIdle || isConfirmingDelete else { return }
        guard let action = actions.delete else { state = .idle; return }
        run(.delete, action: action)
    }

    private func run(_ operation: Operation, action: @escaping ChatThreadActions.Action) {
        state = .pending(operation)
        Task {
            switch await action() {
            case .success: state = .idle
            case let .failure(error): state = .failed(operation, error)
            }
        }
    }
}

/// Identity cache, not UI state. Controllers themselves publish their tagged state through Observation.
@MainActor
final class ChatThreadActionStore<ID: Hashable> {
    private var controllers: [ID: ChatThreadActionController] = [:]

    func controller(for id: ID) -> ChatThreadActionController {
        if let controller = controllers[id] { return controller }
        let controller = ChatThreadActionController()
        controllers[id] = controller
        return controller
    }

    func retain(_ ids: Set<ID>) {
        // A temporarily removed/reinserted identity must still share its in-flight operation.
        controllers = controllers.filter { ids.contains($0.key) || $0.value.isPending }
    }
}
