import Foundation
import Testing
@testable import AgentChatLive
import AgentChatLiveTesting

/// `LiveChatModel` following the loopback server: the stream, its drops, reads while down, one cursor, the writes.
@MainActor
struct FollowTests {
    private let server = LiveLoopbackServer()

    private func model(bearer: @escaping @Sendable (Bool) async throws -> String = { _ in "token" }) -> LiveChatModel {
        LiveChatModel(
            endpoint: LiveEndpoint(chat: URL(string: "https://host.test/chats/chat-1")!, bearer: bearer),
            http: server, streams: server,
            timing: LiveTiming(backoff: [.milliseconds(1)], jitter: 0, backoffResetsAfter: .seconds(10),
                               readInterval: .milliseconds(1)),
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    private func message(_ id: String, _ role: LiveMessage.Role = .assistant, _ text: String? = nil) -> LiveMessage {
        LiveMessage(id: id, seq: 0, role: role, text: text ?? "Words \(id).", at: LiveDates.string(.now))
    }

    /// Waits up to two seconds for a condition the model reaches on its own.
    private func eventually(_ what: String, _ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("never: \(what)")
    }

    @Test func aFreshChatStartsWithItsSnapshotThenTakesEachChangeAsItComes() async throws {
        await server.put(message("m1", .user))
        await server.put(message("m2"))
        let live = model()
        let following = Task { await live.follow() }
        defer { following.cancel() }
        try await eventually("snapshot") { live.chat.messages.map(\.id) == ["m1", "m2"] }
        #expect(live.phase == .live)
        await server.put(message("m3"))
        try await eventually("m3 streamed") { live.chat.messages.map(\.id) == ["m1", "m2", "m3"] }
        #expect(live.chat.cursor == "c:3")
        let requests = await server.requests
        #expect(requests.first == "GET /chats/chat-1/live?v=1")
    }

    @Test func aChatNamedLiveIsServedToo() async throws {
        let server = LiveLoopbackServer(chatID: "live")
        await server.put(message("m1"))
        let live = LiveChatModel(
            endpoint: LiveEndpoint(chat: URL(string: "https://host.test/chats/live")!, bearer: { _ in "t" }),
            http: server, streams: server
        )
        let following = Task { await live.follow() }
        defer { following.cancel() }
        try await eventually("snapshot") { live.chat.messages.map(\.id) == ["m1"] }
        let reply = try await live.send("Hi", clientRef: "x")
        #expect(reply.status == .pending)
    }

    @Test func aDroppedStreamReadsWhileDownThenResumesFromItsCursorTakingNothingTwice() async throws {
        await server.put(message("m1", .user))
        let live = model()
        let following = Task { await live.follow() }
        defer { following.cancel() }
        try await eventually("open") { live.phase == .live }

        await server.setDown(true)
        try await eventually("reading") { live.phase == .reading }
        await server.setDown(false)
        // Written while the stream was down: a read or the resumed stream brings it, once.
        await server.put(message("m2"))
        await server.put(message("m3"))
        try await eventually("caught up") { live.chat.messages.map(\.id) == ["m1", "m2", "m3"] }
        try await eventually("streaming again") { live.streamsOpened == 2 && live.phase == .live }
        await server.put(message("m4"))
        try await eventually("m4 on the new stream") { live.chat.messages.count == 4 }

        let requests = await server.requests
        #expect(requests.contains { $0.hasPrefix("GET /chats/chat-1/live/read?v=1&after=c:1") })
        #expect(requests.contains { $0.hasPrefix("GET /chats/chat-1/live?v=1&after=c:") })
        #expect(Set(live.chat.messages.map(\.id)).count == live.chat.messages.count)
    }

    @Test func aRotateReconnectsAtOnceAndAGoneStops() async throws {
        await server.put(message("m1"))
        let live = model()
        let following = Task { await live.follow() }
        try await eventually("open") { live.phase == .live }
        await server.close(LiveClose(code: 4000, reason: "rotate"))
        try await eventually("reopened") { live.streamsOpened == 2 && live.phase == .live }
        await server.close(LiveClose(code: 4004, reason: "gone"))
        await following.value
        #expect(live.phase == .stopped(.gone))
    }

    @Test func anExpiredBearerIsRenewedOnceThenFollowed() async throws {
        await server.accept(bearer: "new")
        await server.put(message("m1"))
        let live = model { renew in renew ? "new" : "old" }
        let following = Task { await live.follow() }
        defer { following.cancel() }
        try await eventually("followed with the new bearer") { live.phase == .live && live.chat.messages.count == 1 }
    }

    @Test func aBearerRefusedTwiceStops() async throws {
        await server.accept(bearer: "never")
        let live = model()
        await live.follow()
        #expect(live.phase == .stopped(.unauthorized))
    }

    @Test func anExpiredCursorGetsASnapshot() async throws {
        await server.put(message("m1"))
        await server.put(message("m2"))
        await server.forgetHistory()
        let kept = LiveChat(cursor: "c:1", seq: 1, messages: [LiveMessage(id: "old", seq: 1, role: .user, text: "x")])
        let live = LiveChatModel(
            endpoint: LiveEndpoint(chat: URL(string: "https://host.test/c")!, bearer: { _ in "t" }),
            http: server, streams: server, kept: kept
        )
        let following = Task { await live.follow() }
        defer { following.cancel() }
        try await eventually("replaced by the snapshot") { live.chat.messages.map(\.id) == ["m1", "m2"] }
    }

    @Test func aSendWhileTheAgentWaitsOnThePersonIsForced() async throws {
        await server.set(LiveState(seq: 0, working: true, waiting: LiveQuestion(
            id: "q1", question: "Merge now?", options: [.init(id: "yes", label: "Yes")]
        )))
        let live = model()
        let following = Task { await live.follow() }
        defer { following.cancel() }
        try await eventually("state") { live.chat.state?.waiting != nil }
        #expect(live.sendsForced)
        let forced = try await live.send("Also bump the version.", clientRef: "a")
        #expect(forced.status == .pending) // Forced: not queued behind the turn.

        let answered = try await live.answer("q1", options: ["yes"], clientRef: "b")
        #expect(answered.text == "Yes")
        try await eventually("waiting cleared") { live.chat.state?.waiting == nil }
        #expect(!live.sendsForced)
        let queued = try await live.send("And the changelog.", clientRef: "c")
        #expect(queued.status == .queued) // The agent still works: it waits for the turn.

        let again = try await live.send("And the changelog.", clientRef: "c")
        #expect(again.id == queued.id) // A repeat client_ref lands once.

        let moved = try await live.force(queued.id)
        #expect(moved.status == .delivering)
        await #expect(throws: LiveWriteError.self) { try await live.remove(queued.id) }
        try await eventually("each reply once") { live.chat.replies.count == 3 }
        #expect(live.chatMessages.filter { $0.role == .mine }.count == 3)
    }

    @Test func loadEarlierPutsOlderMessagesInFront() async throws {
        for index in 1...5 {
            await server.put(message("m\(index)"))
        }
        let live = model()
        let following = Task { await live.follow() }
        defer { following.cancel() }
        try await eventually("snapshot") { live.chat.messages.count == 5 }
        // A chat that only holds its newest two, as one kept from a short snapshot would.
        let short = LiveChatModel(
            endpoint: LiveEndpoint(chat: URL(string: "https://host.test/c")!, bearer: { _ in "t" }),
            http: server, streams: server,
            kept: LiveChat(cursor: "c:5", seq: 5, messages: Array(live.chat.messages.suffix(2)), moreBefore: true)
        )
        try await short.loadEarlier(limit: 2)
        #expect(short.chat.messages.map(\.id) == ["m2", "m3", "m4", "m5"])
        #expect(short.chat.moreBefore)
        #expect(short.chat.cursor == "c:5")
    }
}
