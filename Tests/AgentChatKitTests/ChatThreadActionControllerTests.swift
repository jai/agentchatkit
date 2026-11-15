import AgentChatCore
import Testing
@testable import AgentChatKit

@MainActor
struct ChatThreadActionControllerTests {
    @Test func deletionRequiresHookAndConfirmationAndCancelCallsNothing() {
        let controller = ChatThreadActionController()
        controller.requestDelete(.init())
        #expect(controller.isIdle)
        var calls = 0
        let actions = ChatThreadActions(delete: { calls += 1; return .success(()) })
        controller.requestDelete(actions)
        #expect(controller.isConfirmingDelete)
        controller.requestDelete(actions)
        controller.archive(.init(archive: { calls += 1; return .success(()) }))
        #expect(controller.isConfirmingDelete)
        controller.dismissConfirmation()
        #expect(controller.isIdle)
        #expect(calls == 0)
    }

    @Test func repeatedEntryPointsCannotReplacePendingOrErrorState() async {
        let controller = ChatThreadActionController()
        let gate = ThreadActionGate()
        var calls = 0
        let actions = ChatThreadActions(archive: {
            calls += 1
            return .success(())
        }, delete: {
            calls += 1
            await gate.pause()
            return .failure(ChatActionError("Host denied deletion"))
        })
        controller.requestDelete(actions)
        controller.confirmDelete(actions)
        await gate.waitUntilEntered()
        #expect(controller.isPending)
        controller.requestDelete(actions) // Keyboard Delete while a row menu's Delete is running.
        controller.confirmDelete(actions)
        controller.archive(actions)
        #expect(calls == 1)
        gate.release()
        // Yield to the controller task, with a bounded wait rather than a timing-dependent sleep.
        for _ in 0..<100 where controller.isPending { await Task.yield() }
        #expect(controller.error?.message == "Host denied deletion")
        controller.requestDelete(actions)
        controller.archive(actions)
        #expect(calls == 1)
        #expect(controller.error != nil)
        controller.dismissError()
        #expect(controller.isIdle)
    }

    @Test func temporarilyAbsentIdentityKeepsItsPendingController() async {
        let store = ChatThreadActionStore<String>()
        let controller = store.controller(for: "alpha")
        let gate = ThreadActionGate()
        controller.archive(.init(archive: {
            await gate.pause()
            return .success(())
        }))
        await gate.waitUntilEntered()
        store.retain([])
        #expect(store.controller(for: "alpha") === controller)
        #expect(store.controller(for: "alpha").isPending)
        gate.release()
    }

    @Test func storeSharesOneControllerPerIdentityAndRetainsSurvivingRows() {
        let store = ChatThreadActionStore<String>()
        let first = store.controller(for: "alpha")
        #expect(first === store.controller(for: "alpha"))
        #expect(first !== store.controller(for: "beta"))
        first.requestDelete(.init(delete: { .success(()) }))
        store.retain(["alpha"])
        #expect(first === store.controller(for: "alpha"))
        #expect(store.controller(for: "alpha").isConfirmingDelete)
        store.retain([])
        #expect(first !== store.controller(for: "alpha"))
    }
}

@MainActor
private final class ThreadActionGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            paused = continuation
            entered = true
            entry?.resume()
            entry = nil
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entry = $0 }
    }

    func release() {
        paused?.resume()
        paused = nil
    }
}
