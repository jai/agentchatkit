import AgentChatKit
@testable import AgentChatLive
import AgentChatLiveTesting
import DurableNetworking
import Foundation
import Observation
import Testing

/// Exercises the same action coordinator used by the SwiftUI adapters, over real in-memory ACP requests/updates.
@Suite(.timeLimit(.minutes(1)), .enabled(if: LiveHostSuites.run, "AGENTCHAT_LIVE_TESTS=off"))
@MainActor
struct LiveControlsTests {
    private let server = LiveDevHost()

    private func model(_ transport: RecordedLiveTransport, kept: LiveChat = LiveChat()) -> LiveChatModel {
        LiveChatModel(endpoint: .init(acp: server.acp, session: server.session,
                                      bearer: { _ in "token" }), http: transport, streams: transport, kept: kept,
                      timing: .init(backoff: [.milliseconds(1)], jitter: 0,
                                    backoffResetsAfter: .seconds(10), answerLimit: .seconds(5)))
    }

    private func start() async throws -> LiveControlsHarness {
        let transport = RecordedLiveTransport(server: server)
        let live = model(transport)
        let following = Task { await live.follow() }
        try await observeUntil { live.phase == .live }
        return LiveControlsHarness(live: live, controls: LiveChatControls(live: live), following: following, transport: transport)
    }

    /// Wake on observable changes, not a clock or repeated trial of the action under test.
    private func observeUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        while !condition() {
            try Task.checkCancellation()
            let (changes, wake) = AsyncStream<Void>.makeStream()
            withObservationTracking {
                if condition() { wake.yield(()) }
            } onChange: {
                wake.yield(())
            }
            for await _ in changes { break }
            wake.finish()
        }
    }

    @Test func queuedProjectionUsesAtOrderAndExcludesOnlyQueuedFromConversation() async throws {
        await server.publish(message("later", status: .queued, second: 2))
        await server.publish(message("first", status: .queued, second: 1))
        await server.publish(message("pending", status: .pending, second: 3))
        await server.publish(message("removed", status: .removed, second: 4))
        let harness = try await start()
        let live = harness.live
        let following = harness.following
        defer { following.cancel() }
        #expect(live.chat.queuedReplies.map(\.id) == ["first", "later"])
        #expect(live.conversationMessages.map(\.id) == ["pending"])
        #expect(live.chatMessages.map(\.id) == ["first", "later", "pending"], "Legacy projection remains compatible")
        await server.setStatus("later", .delivering)
        try await observeUntil { live.conversationMessages.map(\.id) == ["later", "pending"] }
        #expect(live.chat.queuedReplies.map(\.id) == ["first"])
        #expect(live.chat.state?.working == false)
        await server.setState(.running, activity: "Reading")
        try await observeUntil { live.chat.state?.working == true }
    }

    @Test func sendNowUsesForceOnlyEditAndStreamWinsOverDelayedAcknowledgement() async throws {
        await server.setState(.running)
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Keep these words", clientRef: "force-intent")
        try await observeUntil { live.chat.queuedReplies.count == 1 }
        await transport.holdMessageResults()
        let sending = Task { await controls.sendNow(id) }
        try await observeUntil { live.chat.message(id)?.status == .pending }
        #expect(controls.busy.contains(id))
        #expect(await controls.sendNow(id) == false, "A second tap cannot duplicate an in-flight edit")
        #expect(live.chat.queuedReplies.isEmpty)
        await server.setStatus(id, .delivered)
        try await observeUntil { live.chat.message(id)?.ticks == .delivered }
        #expect(await controls.sendNow(id) == false, "No invalid edit after a streamed delivery")
        await transport.releaseMessageResults()
        #expect(await sending.value)
        #expect(live.chat.message(id)?.status == .delivered, "Completion cannot resurrect a queue row")
        #expect(controls.busy.isEmpty)
        let edits = await transport.posts.filter { $0["method"]?.string == "_agentchatkit/edit" }
        #expect(edits.count == 1)
        let params = try #require(edits.first?["params"])
        #expect(params["messageId"]?.string == id)
        #expect(params["force"] == .bool(true))
        #expect(params["prompt"] == nil, "Send now must preserve text/attachments")
        let prompts = await transport.posts.filter { $0["method"]?.string == "session/prompt" }
        #expect(prompts.count == 1, "No replacement prompt or polling request")
    }

    @Test func editRemovesOriginalThenPreservesWordsTypedDuringRequest() async throws {
        await server.setState(.running)
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Original words")
        try await observeUntil { live.chat.message(id)?.status == .queued }
        var draft = "Existing draft"
        await transport.holdMessageResults()
        let editing = Task {
            await controls.edit(id) { words in draft = words + "\n\n" + draft }
        }
        try await observeUntil { live.chat.message(id)?.status == .removed }
        #expect(draft == "Existing draft", "Restore only once removal is acknowledged")
        draft += " typed while waiting"
        #expect(await controls.remove(id) == false)
        await transport.releaseMessageResults()
        #expect(await editing.value)
        #expect(draft == "Original words\n\nExisting draft typed while waiting")
        #expect(live.conversationMessages.isEmpty)
        #expect(live.chat.queuedReplies.isEmpty)
        let removes = await transport.posts.filter { $0["method"]?.string == "_agentchatkit/remove" }
        #expect(removes.count == 1)
        #expect(removes.first?.at("params", "messageId")?.string == id)
    }

    @Test func laterDeliveryWhileRemovalWaitsCannotRestoreAnObsoleteDraft() async throws {
        await server.setState(.running)
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Original")
        try await observeUntil { live.chat.message(id)?.status == .queued }
        await transport.holdMessageResults()
        var draft = "Current draft"
        let editing = Task { await controls.edit(id) { draft = $0 } }
        try await observeUntil { live.chat.message(id)?.status == .removed }
        // A later authoritative update arrives before the older request's acknowledgement.
        await server.setStatus(id, .delivered)
        try await observeUntil { live.chat.message(id)?.status == .delivered }
        await transport.releaseMessageResults()
        #expect(await editing.value == false)
        #expect(draft == "Current draft")
        #expect(live.chat.message(id)?.status == .delivered)
        #expect(controls.errors[id] == nil, "Newer delivery supersedes the older removal result")
    }

    @Test func pendingCancelAndFailedRemoveUseTheLiveRemoveRequest() async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let pending = try await live.send("Pending", clientRef: "pending-ref")
        try await observeUntil { live.chat.message(pending)?.status == .pending }
        #expect(await controls.remove(pending))
        #expect(live.chat.message(pending)?.status == .removed)
        let failed = try await live.send("Failed", clientRef: "remove-ref")
        await server.setStatus(failed, .failed)
        try await observeUntil { live.chat.message(failed)?.status == .failed }
        let before = await transport.posts.count
        #expect(await controls.sendNow(failed) == false)
        #expect(await controls.edit(failed, restore: { _ in Issue.record("Restored failed reply") }) == false)
        #expect(await transport.posts.count == before, "Queued Edit/Send now do not apply to failed replies")
        #expect(await controls.remove(failed))
        #expect(live.chat.message(failed)?.status == .removed)
        #expect(live.chat.message(failed)?.clientRef == "remove-ref")
        #expect(live.conversationMessages.isEmpty)
        let removes = await transport.posts.filter { $0["method"]?.string == "_agentchatkit/remove" }
        #expect(removes.count == 2)
        #expect(removes.map { $0.at("params", "messageId")?.string } == [pending, failed])
        await server.setStatus(failed, .delivered)
        try await observeUntil { live.chat.message(failed)?.status == .delivered }
        let after = await transport.posts.count
        #expect(await controls.remove(failed) == false)
        #expect(await controls.retry(failed) == false)
        #expect(await transport.posts.count == after, "Delivered controls cannot issue another mutation")
    }

    @Test func defaultRetryForcesTheFailedMessageWithTheSameIdentityAndClientRef() async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Retry these words", clientRef: "retry-ref")
        await server.setStatus(id, .failed)
        try await observeUntil { live.chat.message(id)?.status == .failed }
        #expect(await controls.retry(id))
        #expect(live.chat.message(id)?.status == .pending)
        #expect(live.chat.message(id)?.clientRef == "retry-ref")
        #expect(live.chat.message(id)?.text == "Retry these words")
        #expect(live.chat.messages.map(\.id) == [id])
        let edits = await transport.posts.filter { $0["method"]?.string == "_agentchatkit/edit" }
        #expect(edits.count == 1)
        #expect(edits.first?.at("params", "messageId")?.string == id)
        #expect(edits.first?.at("params", "force") == true)
        #expect(edits.first?.at("params", "prompt") == nil)
        let prompts = await transport.posts.filter { $0["method"]?.string == "session/prompt" }
        #expect(prompts.count == 1, "Retry cannot create another prompt or clientRef")
    }

    @Test func hostRetryOverrideStillOwnsItsOperation() async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Override", clientRef: "override-ref")
        await server.setStatus(id, .failed)
        try await observeUntil { live.chat.message(id)?.status == .failed }
        let before = await transport.posts.count
        var retries = 0
        // Out of #expect: an #expect inside another's closure is a recursive macro expansion.
        let retried = await controls.retry(id) { message in
            #expect(message.id == id)
            #expect(message.clientRef == "override-ref")
            retries += 1
            await server.setStatus(message.id, .delivered)
        }
        #expect(retried)
        try await observeUntil { live.chat.message(id)?.status == .delivered }
        #expect(retries == 1)
        #expect(await transport.posts.count == before, "Override replaces the default RPC")
    }
}

extension LiveControlsTests {
    @Test func editRestoresCurrentRemovedWordsAndCurrentDraftWhenTheRemoveReplyIsLost() async throws {
        await server.setState(.running)
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Original words", clientRef: "lost-remove-ref")
        try await observeUntil { live.chat.message(id)?.status == .queued }
        await transport.gateChanges(at: .afterSend)
        var draft = "Existing draft"
        let editing = Task { await controls.edit(id) { draft = $0 + "\n\n" + draft } }
        await transport.waitForChangeReply()
        try await observeUntil { live.chat.message(id)?.status == .removed }
        #expect(draft == "Existing draft", "No restoration before the in-flight operation finishes")
        draft += " typed while waiting"
        // Use the authoritative removed record, including words streamed after the request began.
        await server.publish(["sessionUpdate": "user_message", "messageId": .string(id),
                              "content": [["type": "text", "text": "Updated original words"]]])
        try await observeUntil { live.chat.message(id)?.text == "Updated original words" }
        await transport.loseChangeReplies()
        #expect(await editing.value)
        #expect(draft == "Updated original words\n\nExisting draft typed while waiting")
        #expect(live.chat.message(id)?.status == .removed)
        #expect(controls.errors[id] == nil)
        #expect(controls.busy.isEmpty)
    }

    // A loop, not @Test(arguments:): a parameterized test in a @MainActor suite aborted swift test on the macOS 26
    // runtime ("freed pointer was not the last allocation").
    @Test func newerStreamStateSupersedesALostDefaultRetryReply() async throws {
        for status in [LiveMessage.Status.pending, .delivering, .delivered, .removed] {
            try await Self().newerStreamStateSupersedesALostDefaultRetryReply(status) // A fresh session each time.
        }
    }

    private func newerStreamStateSupersedesALostDefaultRetryReply(_ status: LiveMessage.Status) async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Retry", clientRef: "gated-retry-ref")
        await server.setStatus(id, .failed)
        try await observeUntil { live.chat.message(id)?.status == .failed }
        await transport.gateChanges(at: .afterSend)
        let retrying = Task { await controls.retry(id) }
        await transport.waitForChangeReply()
        try await observeUntil { live.chat.message(id)?.status == .pending }
        await server.setStatus(id, status)
        try await observeUntil { live.chat.message(id)?.status == status }
        await transport.loseChangeReplies()
        #expect(await retrying.value == (status != .removed))
        #expect(live.chat.message(id)?.clientRef == "gated-retry-ref")
        #expect(live.chat.messages.map(\.id) == [id])
        #expect(controls.errors[id] == nil)
        #expect(controls.busy.isEmpty)
    }

    @Test func newerDeliverySupersedesALostEditRemoveReplyWithoutRestoringWords() async throws {
        await server.setState(.running)
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Original")
        try await observeUntil { live.chat.message(id)?.status == .queued }
        await transport.gateChanges(at: .afterSend)
        var draft = "Current draft"
        let editing = Task { await controls.edit(id) { draft = $0 } }
        await transport.waitForChangeReply()
        try await observeUntil { live.chat.message(id)?.status == .removed }
        await server.setStatus(id, .delivered)
        try await observeUntil { live.chat.message(id)?.status == .delivered }
        await transport.loseChangeReplies()
        #expect(await editing.value == false)
        #expect(draft == "Current draft")
        #expect(controls.errors[id] == nil)
        #expect(live.chat.message(id)?.status == .delivered)
    }

    @Test func failedRemoveReplyIsSuccessfulOnlyWithExplicitStreamedRemoval() async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Failed", clientRef: "gated-remove-ref")
        await server.setStatus(id, .failed)
        try await observeUntil { live.chat.message(id)?.status == .failed }
        await transport.gateChanges(at: .afterSend)
        let removing = Task { await controls.remove(id) }
        await transport.waitForChangeReply()
        try await observeUntil { live.chat.message(id)?.status == .removed }
        await transport.loseChangeReplies()
        #expect(await removing.value)
        #expect(controls.errors[id] == nil)
        #expect(live.chat.message(id)?.clientRef == "gated-remove-ref")
    }

    @Test func cappedSnapshotAbsenceCannotConfirmEditRemoval() async throws {
        await server.publish(message("old", status: .queued, second: 0))
        for index in 0..<201 {
            await server.agentSays("agent-\(index)", "Newer message", at: Date(timeIntervalSince1970: Double(index)))
        }
        var old = LiveMessage(id: "old", kind: .user, text: "Old retained words")
        old.status = .queued
        let transport = RecordedLiveTransport(server: server)
        await transport.holdResumeResult()
        await transport.gateChanges(at: .beforeSend)
        let live = model(transport, kept: LiveChat(cursor: nil, messages: [old]))
        let controls = LiveChatControls(live: live)
        let following = Task { await live.follow() }
        defer { following.cancel() }
        await transport.waitForResumeResult()
        #expect(live.chat.message("old")?.status == .queued)
        var draft = "Current draft"
        let editing = Task { await controls.edit("old") { draft = $0 + "\n\n" + draft } }
        await transport.waitForChangeReply()
        await transport.releaseResumeResult()
        try await observeUntil { live.phase == .live && live.chat.message("old") == nil }
        #expect(live.chat.messages.count == 200)
        draft += " typed during snapshot"
        await transport.loseChangeReplies()
        #expect(await editing.value == false)
        #expect(draft == "Current draft typed during snapshot")
        #expect(controls.errors["old"] == nil)
        #expect(controls.busy.isEmpty)
    }

    @Test func anEarlierRequestErrorDisappearsWhenTheStreamConfirmsDelivery() async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let id = try await live.send("Retry")
        await server.setStatus(id, .failed)
        try await observeUntil { live.chat.message(id)?.status == .failed }
        await transport.gateChanges(at: .beforeSend)
        let retrying = Task { await controls.retry(id) }
        await transport.waitForChangeReply()
        await transport.loseChangeReplies()
        #expect(await retrying.value == false)
        #expect(controls.errors[id] != nil)
        await server.setStatus(id, .delivered)
        try await observeUntil { live.chat.message(id)?.status == .delivered }
        #expect(controls.errors[id] == nil)
    }

    @Test func refusedDeclineRetainsQuestionAndAllowsASeparateDeclineRequest() async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        await server.ask("Decline?", options: [.init(id: "a", label: "A")])
        try await observeUntil { live.chat.question != nil }
        let question = try #require(live.chat.question)
        await transport.refuseNextQuestionResponse(403)
        #expect(await controls.decline(question) == false)
        #expect(live.chat.question == question)
        #expect(controls.error(for: question) != nil)
        #expect(controls.answering == false)
        #expect(await controls.decline(question))
        #expect(live.chat.question == nil)
        #expect(controls.error(for: question) == nil)
        let declines = await transport.posts.filter { $0.at("result", "action") == "decline" }
        #expect(declines.count == 2)
        #expect(declines.allSatisfy { $0["id"] == question.requestID })
    }
}

extension LiveControlsTests {
    @Test func failedRemovalPreservesDraftAndCanRetryAfterReconnection() async throws {
        await server.setState(.running)
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        defer { following.cancel() }
        let id = try await live.send("Keep original")
        try await observeUntil { live.chat.message(id)?.status == .queued }
        await server.setDown(true)
        try await observeUntil { live.phase == .reconnecting } // The drop has reached the model.
        var draft = "Unchanged"
        #expect(await controls.edit(id, restore: { draft = $0 }) == false)
        #expect(draft == "Unchanged")
        #expect(controls.errors[id] != nil)
        #expect(controls.busy.isEmpty)
        await server.setDown(false)
        try await observeUntil { live.phase == .live }
        #expect(await controls.remove(id))
        try await observeUntil { live.chat.queuedReplies.isEmpty }
        #expect(controls.errors[id] == nil)
    }

    @Test func snapshotAfterFailedForceCannotResurrectAQueuedReply() async throws {
        await server.setState(.running)
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        defer { following.cancel() }
        let id = try await live.send("Original")
        try await observeUntil { live.chat.message(id)?.status == .queued }
        await server.setDown(true)
        #expect(await controls.sendNow(id) == false)
        await server.setStatus(id, .delivered)
        await server.forgetHistory()
        await server.setDown(false)
        try await observeUntil { live.phase == .live && live.chat.message(id)?.status == .delivered }
        #expect(live.timings.last?.fromStart == true)
        #expect(live.chat.queuedReplies.isEmpty)
        #expect(live.conversationMessages.map(\.id) == [id])
        #expect(controls.busy.isEmpty)
    }

    @Test func questionAnswersUseSchemaFieldsAndDeclineAndRejectStaleQuestions() async throws {
        let harness = try await start()
        let live = harness.live
        let controls = harness.controls
        let following = harness.following
        let transport = harness.transport
        defer { following.cancel() }
        let choices: [LiveQuestion.Option] = [.init(id: "a", label: "A"), .init(id: "b", label: "B")]
        await server.ask("Single", options: choices, freeText: false)
        try await observeUntil { live.chat.question?.message == "Single" }
        let single = try #require(live.chat.question)
        #expect(await controls.answer(single, options: ["b"]))
        try await observeUntil { live.chat.messages.last?.text == "B" }
        await server.ask("Multiple", options: choices, multiple: true)
        try await observeUntil { live.chat.question?.message == "Multiple" }
        #expect(await controls.answer(try #require(live.chat.question), options: ["a", "b"], text: "Both"))
        try await observeUntil { live.chat.messages.last?.text == "A, B: Both" }
        await server.ask("Text", options: [], freeText: true)
        try await observeUntil { live.chat.question?.message == "Text" }
        #expect(await controls.answer(try #require(live.chat.question), options: [], text: "My words"))
        try await observeUntil { live.chat.messages.last?.text == "My words" }
        await server.ask("Decline", options: choices)
        try await observeUntil { live.chat.question?.message == "Decline" }
        #expect(await controls.decline(try #require(live.chat.question)))
        #expect(live.chat.question == nil)
        #expect(await controls.answer(single, options: ["a"]) == false, "Old buttons cannot answer a new question")
        let responses = await transport.posts.filter { $0["method"] == nil && $0["result"] != nil }
        #expect(responses.count == 4)
        #expect(responses[0].at("result", "content", "choice") == .string("b"))
        #expect(responses[0].at("result", "content", "choices") == nil)
        #expect(responses[1].at("result", "content", "choices") == ["a", "b"])
        #expect(responses[1].at("result", "content", "text") == "Both")
        #expect(responses[2].at("result", "content", "text") == "My words")
        #expect(responses[2].at("result", "content", "choice") == nil)
        #expect(responses[3].at("result", "action") == "decline")
    }

    @Test func allStatusTicksMatchTheProfile() {
        let cases: [(LiveMessage.Status?, DeliveryTicks?)] = [
            (.pending, .sent), (.queued, .sent), (.delivering, .sent), (.delivered, .delivered),
            (.failed, nil), (.removed, nil), (nil, nil),
        ]
        for (status, expected) in cases {
            var message = LiveMessage(id: "m", kind: .user)
            message.status = status
            #expect(message.ticks == expected)
            #expect(message.deliveryState.ticks == expected)
        }
    }

    private func message(_ id: String, status: LiveMessage.Status, second: Int) -> JSONValue {
        ["sessionUpdate": "user_message", "messageId": .string(id),
         "content": [["type": "text", "text": .string(id)]],
         "_meta": ["agentchatkit": ["status": .string(status.rawValue),
                                    "at": .string("2026-01-01T00:00:0\(second).000Z")]]]
    }
}

/// Holds RPC results while forwarding notifications. Request gates can lose a POST reply after its streamed
/// mutation, or lose the request before it reaches the server. No production transport/server behavior is changed.
private actor RecordedLiveTransport: HTTPTransport, StreamingTransport {
    enum ChangeGate: Equatable { case beforeSend, afterSend }
    let server: LiveDevHost
    private(set) var posts: [JSONValue] = []
    private var holding = false
    private var held: [(String, AsyncThrowingStream<String, any Error>.Continuation)] = []
    private var changeGate: ChangeGate?
    private var changeIDs: Set<JSONValue> = []
    private var lostIDs: Set<JSONValue> = []
    private var changeReplies: [CheckedContinuation<Void, any Error>] = []
    private var changeWaiters: [CheckedContinuation<Void, Never>] = []
    private var holdingResume = false
    private var resumeResults: [(String, AsyncThrowingStream<String, any Error>.Continuation)] = []
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseRefusal: Int?

    init(server: LiveDevHost) { self.server = server }
    func holdMessageResults() { holding = true }
    func releaseMessageResults() {
        holding = false
        let results = held
        held = []
        for (line, continuation) in results { continuation.yield(line) }
    }

    func gateChanges(at gate: ChangeGate) {
        changeGate = gate
        holding = true
    }

    func waitForChangeReply() async {
        if !changeReplies.isEmpty { return }
        await withCheckedContinuation { changeWaiters.append($0) }
    }

    func loseChangeReplies() {
        changeGate = nil
        holding = false
        held = [] // The RPC acknowledgement was lost, while notifications remain visible.
        lostIDs.formUnion(changeIDs)
        changeIDs = []
        let replies = changeReplies
        changeReplies = []
        for reply in replies { reply.resume(throwing: URLError(.networkConnectionLost)) }
    }

    func holdResumeResult() { holdingResume = true }
    func waitForResumeResult() async {
        if !resumeResults.isEmpty { return }
        await withCheckedContinuation { resumeWaiters.append($0) }
    }
    func releaseResumeResult() {
        holdingResume = false
        let results = resumeResults
        resumeResults = []
        for (line, continuation) in results { continuation.yield(line) }
    }
    func refuseNextQuestionResponse(_ status: Int) { responseRefusal = status }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json = try request.httpBody.map(JSONValue.decode)
        if let json { posts.append(json) }
        if json?["method"] == nil, let status = responseRefusal {
            responseRefusal = nil
            return (Data(), response(request, status))
        }
        let isChange = ["_agentchatkit/edit", "_agentchatkit/remove"].contains(json?["method"]?.string ?? "")
        if isChange, changeGate != nil, let id = json?["id"] { changeIDs.insert(id) }
        if isChange, changeGate == .beforeSend { try await pauseChange() }
        let result = try await server.send(request)
        if isChange, changeGate == .afterSend { try await pauseChange() }
        return result
    }

    private func pauseChange() async throws {
        try await withCheckedThrowingContinuation { continuation in
            changeReplies.append(continuation)
            let waiters = changeWaiters
            changeWaiters = []
            for waiter in waiters { waiter.resume() }
        }
    }

    func open(_ request: URLRequest) async throws -> LineStream {
        let stream = try await server.open(request)
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let pump = Task {
            do {
                for try await line in stream.lines { self.forward(line, to: continuation) }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in pump.cancel() }
        return LineStream(response: response(request, stream.status), lines: lines)
    }

    private func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url ?? URL(filePath: "/"), statusCode: status,
                        httpVersion: "HTTP/2", headerFields: nil) ?? HTTPURLResponse()
    }

    private func forward(_ line: String, to continuation: AsyncThrowingStream<String, any Error>.Continuation) {
        let json = LiveEventParser().message(from: line)
        if let id = json?["id"], lostIDs.contains(id) { return }
        if holding, json?.at("result", "messageId") != nil {
            held.append((line, continuation))
        } else if holdingResume, json?["result"] != nil {
            resumeResults.append((line, continuation))
            let waiters = resumeWaiters
            resumeWaiters = []
            for waiter in waiters { waiter.resume() }
        } else { continuation.yield(line) }
    }
}

@MainActor
private struct LiveControlsHarness {
    let live: LiveChatModel
    let controls: LiveChatControls
    let following: Task<Void, Never>
    let transport: RecordedLiveTransport
}
