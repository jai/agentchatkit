import AgentChatKit
import AgentChatLiveTesting
import DurableNetworking
import Foundation
import Testing
@testable import AgentChatLive

/// Exercises the same action coordinator used by the SwiftUI adapters, over real in-memory ACP requests/updates.
@MainActor
struct LiveControlsTests {
    private let server = LiveLoopbackServer()

    private func start() async throws -> (LiveChatModel, LiveChatControls, Task<Void, Never>, RecordedLiveTransport) {
        let transport = RecordedLiveTransport(server: server)
        let live = LiveChatModel(endpoint: .init(acp: URL(string: "https://host.test/acp")!, session: "chat-1",
                                                 bearer: { _ in "token" }), http: transport, streams: transport,
                                 timing: .init(backoff: [.milliseconds(1)], jitter: 0,
                                               backoffResetsAfter: .seconds(10), answerLimit: .seconds(5)))
        let following = Task { await live.follow() }
        try await eventually { live.phase == .live }
        return (live, LiveChatControls(live: live), following, transport)
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Live control state did not arrive")
    }

    @Test func queuedProjectionUsesAtOrderAndExcludesOnlyQueuedFromConversation() async throws {
        await server.publish(message("later", status: .queued, second: 2))
        await server.publish(message("first", status: .queued, second: 1))
        await server.publish(message("pending", status: .pending, second: 3))
        await server.publish(message("removed", status: .removed, second: 4))
        let (live, _, following, _) = try await start()
        defer { following.cancel() }
        #expect(live.chat.queuedReplies.map(\.id) == ["first", "later"])
        #expect(live.conversationMessages.map(\.id) == ["pending"])
        #expect(live.chatMessages.map(\.id) == ["first", "later", "pending"], "Legacy projection remains compatible")
        await server.setStatus("later", .delivering)
        try await eventually { live.conversationMessages.map(\.id) == ["later", "pending"] }
        #expect(live.chat.queuedReplies.map(\.id) == ["first"])
        #expect(live.chat.state?.working == false)
        await server.setState(.running, activity: "Reading")
        try await eventually { live.chat.state?.working == true }
    }

    @Test func sendNowUsesForceOnlyEditAndStreamWinsOverDelayedAcknowledgement() async throws {
        await server.setState(.running)
        let (live, controls, following, transport) = try await start()
        defer { following.cancel() }
        let id = try await live.send("Keep these words", clientRef: "force-intent")
        try await eventually { live.chat.queuedReplies.count == 1 }
        await transport.holdMessageResults()
        let sending = Task { await controls.sendNow(id) }
        try await eventually { live.chat.message(id)?.status == .pending }
        #expect(controls.busy.contains(id))
        #expect(await controls.sendNow(id) == false, "A second tap cannot duplicate an in-flight edit")
        #expect(live.chat.queuedReplies.isEmpty)
        await server.setStatus(id, .delivered)
        try await eventually { live.chat.message(id)?.ticks == .delivered }
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
        let (live, controls, following, transport) = try await start()
        defer { following.cancel() }
        let id = try await live.send("Original words")
        try await eventually { live.chat.message(id)?.status == .queued }
        var draft = "Existing draft"
        await transport.holdMessageResults()
        let editing = Task {
            await controls.edit(id) { words in draft = words + "\n\n" + draft }
        }
        try await eventually { live.chat.message(id)?.status == .removed }
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
        let (live, controls, following, transport) = try await start()
        defer { following.cancel() }
        let id = try await live.send("Original")
        try await eventually { live.chat.message(id)?.status == .queued }
        await transport.holdMessageResults()
        var draft = "Current draft"
        let editing = Task { await controls.edit(id) { draft = $0 } }
        try await eventually { live.chat.message(id)?.status == .removed }
        // A later authoritative update arrives before the older request's acknowledgement.
        await server.setStatus(id, .delivered)
        try await eventually { live.chat.message(id)?.status == .delivered }
        await transport.releaseMessageResults()
        #expect(await editing.value == false)
        #expect(draft == "Current draft")
        #expect(live.chat.message(id)?.status == .delivered)
        #expect(controls.errors[id] == .unavailable)
    }

    @Test func pendingCancelRemovesButDeliveredAndFailedNeverSendInvalidRemoveOrEdit() async throws {
        let (live, controls, following, transport) = try await start()
        defer { following.cancel() }
        let id = try await live.send("Pending")
        try await eventually { live.chat.message(id)?.status == .pending }
        #expect(await controls.remove(id))
        try await eventually { live.chat.message(id)?.status == .removed }
        #expect(live.conversationMessages.isEmpty)
        let failed = try await live.send("Failed")
        await server.setStatus(failed, .failed)
        try await eventually { live.chat.message(failed)?.status == .failed }
        let before = await transport.posts.count
        #expect(await controls.remove(failed) == false)
        #expect(await controls.sendNow(failed) == false)
        #expect(await controls.edit(failed, restore: { _ in Issue.record("Restored failed reply") }) == false)
        #expect(await transport.posts.count == before)
        var retries = 0
        #expect(await controls.retry(failed) { message in
            #expect(message.id == failed)
            retries += 1
            await server.setStatus(message.id, .delivered)
        })
        try await eventually { live.chat.message(failed)?.status == .delivered }
        #expect(retries == 1)
        #expect(await transport.posts.count == before, "Host Retry hook adds no invented ACP method")
    }

    @Test func failedRemovalPreservesDraftAndCanRetryAfterReconnection() async throws {
        await server.setState(.running)
        let (live, controls, following, _) = try await start()
        defer { following.cancel() }
        let id = try await live.send("Keep original")
        try await eventually { live.chat.message(id)?.status == .queued }
        await server.setDown(true)
        var draft = "Unchanged"
        #expect(await controls.edit(id, restore: { draft = $0 }) == false)
        #expect(draft == "Unchanged")
        #expect(controls.errors[id] != nil)
        #expect(controls.busy.isEmpty)
        await server.setDown(false)
        try await eventually { live.phase == .live }
        #expect(await controls.remove(id))
        try await eventually { live.chat.queuedReplies.isEmpty }
        #expect(controls.errors[id] == nil)
    }

    @Test func snapshotAfterFailedForceCannotResurrectAQueuedReply() async throws {
        await server.setState(.running)
        let (live, controls, following, _) = try await start()
        defer { following.cancel() }
        let id = try await live.send("Original")
        try await eventually { live.chat.message(id)?.status == .queued }
        await server.setDown(true)
        #expect(await controls.sendNow(id) == false)
        await server.setStatus(id, .delivered)
        await server.forgetHistory()
        await server.setDown(false)
        try await eventually { live.phase == .live && live.chat.message(id)?.status == .delivered }
        #expect(live.timings.last?.fromStart == true)
        #expect(live.chat.queuedReplies.isEmpty)
        #expect(live.conversationMessages.map(\.id) == [id])
        #expect(controls.busy.isEmpty)
    }

    @Test func questionAnswersUseSchemaFieldsAndDeclineAndRejectStaleQuestions() async throws {
        let (live, controls, following, transport) = try await start()
        defer { following.cancel() }
        let choices: [LiveQuestion.Option] = [.init(id: "a", label: "A"), .init(id: "b", label: "B")]
        await server.ask("Single", options: choices, freeText: false)
        try await eventually { live.chat.question?.message == "Single" }
        let single = try #require(live.chat.question)
        #expect(await controls.answer(single, options: ["b"]))
        try await eventually { live.chat.messages.last?.text == "B" }
        await server.ask("Multiple", options: choices, multiple: true)
        try await eventually { live.chat.question?.message == "Multiple" }
        #expect(await controls.answer(try #require(live.chat.question), options: ["a", "b"], text: "Both"))
        try await eventually { live.chat.messages.last?.text == "A, B: Both" }
        await server.ask("Text", options: [], freeText: true)
        try await eventually { live.chat.question?.message == "Text" }
        #expect(await controls.answer(try #require(live.chat.question), options: [], text: "My words"))
        try await eventually { live.chat.messages.last?.text == "My words" }
        await server.ask("Decline", options: choices)
        try await eventually { live.chat.question?.message == "Decline" }
        #expect(await controls.answer(try #require(live.chat.question), options: [], decline: true))
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

/// Holds RPC message results while continuing to deliver notifications. This models a slow acknowledgement without
/// hiding fresh stream state, and records request bodies to assert semantics against the real loopback server.
private actor RecordedLiveTransport: HTTPTransport, StreamingTransport {
    let server: LiveLoopbackServer
    private(set) var posts: [JSONValue] = []
    private var holding = false
    private var held: [(String, AsyncThrowingStream<String, any Error>.Continuation)] = []

    init(server: LiveLoopbackServer) { self.server = server }
    func holdMessageResults() { holding = true }
    func releaseMessageResults() {
        holding = false
        let results = held
        held = []
        for (line, continuation) in results { continuation.yield(line) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let body = request.httpBody { posts.append(try JSONValue.decode(body)) }
        return try await server.send(request)
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
        let response = HTTPURLResponse(url: request.url ?? URL(filePath: "/"), statusCode: stream.status,
                                       httpVersion: "HTTP/2", headerFields: nil) ?? HTTPURLResponse()
        return LineStream(response: response, lines: lines)
    }

    private func forward(_ line: String, to continuation: AsyncThrowingStream<String, any Error>.Continuation) {
        if holding, let json = LiveEventParser().message(from: line), json.at("result", "messageId") != nil {
            held.append((line, continuation))
        } else { continuation.yield(line) }
    }
}
