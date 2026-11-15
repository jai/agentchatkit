import Foundation
import Testing
@testable import AgentChatKit

@MainActor
struct ReplyQueueControllerTests {
    private func reply(
        _ id: String, at time: Double = 0, state: ReplyDeliveryState = .inThreadQueue, actionPending: Bool = false
    ) -> QueuedReply<String> {
        .init(id: id, clientRef: "ref-\(id)", text: "Words \(id)", createdAt: Date(timeIntervalSince1970: time),
              state: state, statusText: "Queued", actionPending: actionPending)
    }

    @Test func onlyThreadQueuedRepliesAppearOldestFirstWithStableTies() {
        let model = ReplyQueueController(replies: [
            reply("new", at: 2), reply("sent", state: .delivered), reply("first", at: 1), reply("tie", at: 1),
            reply("local", state: .queued), reply("removed", state: .removed),
        ], remove: { _ in .success(nil) })
        #expect(model.queued.map(\.id) == ["first", "tie", "new"])
        #expect(!model.canSendNow)
    }

    @Test func failedEditKeepsTheDraftAndReplyAndShowsTheHostsError() async {
        let item = reply("edit")
        let problem = ChatActionError("The thread took it before that reached it.")
        let model = ReplyQueueController(replies: [item], draft: "Existing", remove: { _ in .failure(problem) })
        let result = await model.edit(item)
        #expect(result.failure == problem)
        #expect(model.draft == "Existing")
        #expect(model.queued == [item])
        #expect(model.errors[item.id] == problem)
        #expect(model.asking.isEmpty)
    }

    @Test func editRemovesBeforePrependingAndKeepsWordsTypedWhileWaiting() async {
        let item = reply("edit")
        let gate = QueueGate()
        var removals = 0
        let model = ReplyQueueController(replies: [item], draft: "Before", remove: { _ in
            removals += 1
            await gate.pause()
            return .success(nil)
        })
        let edit = Task { await model.edit(item) }
        await gate.waitUntilEntered()
        #expect(model.draft == "Before")
        #expect(model.isBusy(item))
        #expect(await model.remove(item).failure == .busy)
        model.draft = "Typed while waiting"
        gate.release()
        #expect(await edit.value.failure == nil)
        #expect(removals == 1)
        #expect(model.queued.isEmpty)
        #expect(model.draft == "Words edit\n\nTyped while waiting")
    }

    @Test func editIntoAnEmptyDraftHasNoExtraWhitespaceAndAcceptedActionStaysDisabled() async throws {
        let item = reply("edit")
        var accepted = item
        accepted.actionPending = true
        accepted.statusText = "Removing…"
        let model = ReplyQueueController(replies: [item], remove: { _ in .success(accepted) })
        #expect(await model.edit(item).failure == nil)
        #expect(model.draft == item.text)
        let pending = try #require(model.queued.first)
        #expect(model.isBusy(pending))
        #expect(await model.edit(item).failure == .busy)
        #expect(model.draft == item.text, "a second tap must not duplicate its words")
    }

    @Test func aHostPendingActionAndAReplyThatLeftCannotBeMutated() async {
        let pending = reply("pending", actionPending: true)
        let sent = reply("sent", state: .delivered)
        var calls = 0
        let model = ReplyQueueController(replies: [pending, sent], remove: { _ in calls += 1; return .success(nil) })
        #expect(await model.remove(pending).failure == .busy)
        #expect(await model.remove(sent).failure == .unavailable)
        #expect(await model.sendNow(pending).failure == .unavailable)
        #expect(calls == 0)
    }

    @Test func sendNowIntentWaitsForTheQueueThenIsConsumedOnceEvenOnFailure() async {
        let item = reply("once")
        var calls = 0
        let model = ReplyQueueController<String>(remove: { _ in .success(nil) }, sendNow: { _ in
            calls += 1
            return .failure(ChatActionError("Try explicitly"))
        })
        model.sendNowWhenQueued(clientRef: item.clientRef)
        await model.sendNowWhereQueued()
        #expect(calls == 0)
        model.replaceReplies([item])
        await model.sendNowWhereQueued()
        model.sendNowWhenQueued(clientRef: item.clientRef)
        model.replaceReplies([item])
        await model.sendNowWhereQueued()
        #expect(calls == 1)
        #expect(model.errors[item.id]?.message == "Try explicitly")
        _ = await model.sendNow(item)
        #expect(calls == 2, "explicit retry remains available")
    }

    @Test func concurrentSnapshotProcessingSendsAnIntentOnlyOnceAndRetainsTheHostsState() async {
        let item = reply("once")
        let gate = QueueGate()
        var calls = 0
        let model = ReplyQueueController(replies: [item], remove: { _ in .success(nil) }, sendNow: { reply in
            calls += 1
            await gate.pause()
            var delivered = reply
            delivered.state = .delivered
            return .success(delivered)
        })
        model.sendNowWhenQueued(clientRef: item.clientRef)
        let sending = Task { await model.sendNowWhereQueued() }
        await gate.waitUntilEntered()
        await model.sendNowWhereQueued()
        #expect(await model.sendNow(item).failure == .busy)
        gate.release()
        await sending.value
        #expect(calls == 1)
        #expect(model.queued.isEmpty)
        #expect(model.replies.first?.state == .delivered)
        model.replaceReplies([item])
        await model.sendNowWhereQueued()
        #expect(calls == 1, "a stale queued snapshot cannot send the intent again")
    }

    @Test func aDirectSendNowConsumesTheComposerIntentAndFailureCanBeRetried() async {
        let item = reply("direct")
        var calls = 0
        let problem = ChatActionError("First request failed")
        let model = ReplyQueueController(replies: [item], remove: { _ in .success(nil) }, sendNow: { _ in
            calls += 1
            return calls == 1 ? .failure(problem) : .success(nil)
        })
        model.sendNowWhenQueued(clientRef: item.clientRef)
        #expect(await model.sendNow(item).failure == problem)
        await model.sendNowWhereQueued()
        #expect(calls == 1)
        #expect(await model.sendNow(item).failure == nil)
        #expect(calls == 2)
        #expect(model.errors[item.id] == nil)
        #expect(model.queued.isEmpty)
    }
}

private extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { error } else { nil }
    }
}

@MainActor
private final class QueueGate {
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
