@testable import AgentChatLive
import AgentChatLiveTesting
import Foundation
import Testing

/// `LiveChatModel` following the loopback host over the profile: initialize, the stream, resume (from start, from a
/// cursor, from start again when the cursor expired), reconnects, the writes, and a question answered on one of two
/// clients.
/// The suites that follow the server package's dev host. `AGENTCHAT_LIVE_TESTS=off` leaves them out, for a machine
/// with no dev host. (Their SIGBUS on the macOS 26 runtime came from awaiting a stored pause closure in
/// `LiveChatModel`, jai/agentchatkit#3; CI runs them with the rest.)
enum LiveHostSuites {
    static let run = ProcessInfo.processInfo.environment["AGENTCHAT_LIVE_TESTS"] != "off"
}

@Suite(.enabled(if: LiveHostSuites.run, "AGENTCHAT_LIVE_TESTS=off"))
@MainActor
struct FollowTests {
    private let server = LiveDevHost()

    private func model(
        kept: LiveChat = LiveChat(), bearer: @escaping @Sendable (Bool) async throws -> String = { _ in "token" }
    ) -> LiveChatModel {
        LiveChatModel(
            endpoint: LiveEndpoint(acp: server.acp, session: server.session, bearer: bearer),
            http: server, streams: server, kept: kept,
            timing: LiveTiming(backoff: [.milliseconds(1)], jitter: 0, backoffResetsAfter: .seconds(10),
                               answerLimit: .seconds(2))
        )
    }

    private func eventually(_ what: String, _ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("never: \(what)")
    }

    private func follow(_ live: LiveChatModel) -> Task<Void, Never> {
        Task { await live.follow() }
    }

    @Test func aFreshChatResumesFromStartThenTakesEachUpdateAsItComes() async throws {
        await server.agentSays("m1", "Hello.")
        await server.setState(.running, activity: "Reading")
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("live") { live.phase == .live }
        #expect(live.chat.messages.map(\.id) == ["m1"])
        #expect(live.chat.state?.activity == "Reading")
        await server.agentSays("m2", "Found it.")
        try await eventually("m2") { live.chat.messages.count == 2 }
        #expect(live.chat.cursor != nil) // The host's own; opaque here.
        #expect(live.timings.first?.fromStart == true)
        #expect(live.timings.first?.initialize != nil)
        let requests = await server.requests
        #expect(requests.prefix(3) == ["POST initialize", "GET stream", "POST session/resume"])
    }

    @Test func aDroppedStreamResumesFromItsCursorWithoutInitializingAgain() async throws {
        await server.agentSays("m1", "Hello.")
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("live") { live.phase == .live }
        await server.setDown(true)
        try await eventually("reconnecting") { live.phase == .reconnecting }
        await server.agentSays("m2", "Written while you were away.")
        await server.setDown(false)
        try await eventually("caught up") { live.chat.messages.map(\.id) == ["m1", "m2"] && live.phase == .live }
        #expect(live.streamsOpened >= 2)
        #expect(live.timings.last?.fromStart == false)
        #expect(live.timings.last?.initialize == nil)
        let requests = await server.requests
        #expect(requests.filter { $0 == "POST initialize" }.count == 1)
    }

    @Test func aRestartedHostIsInitializedAgain() async throws {
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("live") { live.phase == .live }
        await server.forgetConnections()
        await server.agentSays("m1", "After the restart.")
        try await eventually("back") { live.phase == .live && live.chat.messages.count == 1 }
        let requests = await server.requests
        #expect(requests.filter { $0 == "POST initialize" }.count == 2)
    }

    @Test func anExpiredCursorResumesFromStartAndReplacesWhatWasHeld() async throws {
        await server.agentSays("m1", "One.")
        await server.agentSays("m2", "Two.")
        await server.forgetHistory()
        var old = LiveMessage(id: "old", kind: .agent, text: "From another history.")
        old.at = "2026-01-01T00:00:00.000Z"
        let live = model(kept: LiveChat(cursor: "c:1", messages: [old]))
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("replaced") { live.chat.messages.map(\.id) == ["m1", "m2"] }
        try await eventually("timed from start") { live.timings.last?.fromStart == true }
    }

    @Test func aBearerRefusedTwiceStops() async throws {
        await server.accept(bearer: "never")
        let live = model()
        await live.follow()
        #expect(live.phase == .stopped(.unauthorized))
    }

    @Test func anExpiredBearerIsRenewedOnce() async throws {
        await server.accept(bearer: "new")
        let live = model { renew in renew ? "new" : "old" }
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("live") { live.phase == .live }
    }

    @Test func promptsQueueEditSendNowAndRemove() async throws {
        await server.setState(.running, activity: "Running tests")
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("live") { live.phase == .live }

        let queued = try await live.send("Merge it.", clientRef: "a")
        try await eventually("queued") { live.chat.message(queued)?.status == .queued }
        #expect(try await live.send("Merge it.", clientRef: "a") == queued) // A repeat lands once.

        try await live.edit(queued, text: "Merge it, then tag.")
        try await eventually("edited") { live.chat.message(queued)?.text == "Merge it, then tag." }
        try await live.sendNow(queued)
        try await eventually("sent now") { live.chat.message(queued)?.status == .pending }

        let other = try await live.send("Never mind.", clientRef: "b")
        try await live.remove(other)
        try await eventually("removed") { live.chat.message(other)?.status == .removed }
        do {
            try await live.remove(other)
            Issue.record("A second removal was taken")
        } catch let LiveRequestError.refused(code, _) {
            #expect(code == AcpError.conflict)
        }
        #expect(live.chatMessages.map(\.id) == [queued])

        await server.setStatus(queued, .delivered)
        try await eventually("two ticks") { live.chat.message(queued)?.ticks == .delivered }
    }

    @Test func aFailedMessageIsRetriedWithItsIdAndThenRemoved() async throws {
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("live") { live.phase == .live }
        let sent = try await live.send("Tag it.", clientRef: "t")
        await server.setStatus(sent, .failed)
        try await eventually("failed") { live.chat.message(sent)?.status == .failed }
        #expect(live.chat.message(sent)?.ticks == nil)
        #expect(try await live.retry(sent) == sent)
        try await eventually("pending again") { live.chat.message(sent)?.status == .pending }
        await server.setStatus(sent, .failed)
        try await eventually("failed again") { live.chat.message(sent)?.status == .failed }
        try await live.remove(sent)
        try await eventually("removed") { live.chat.message(sent)?.status == .removed }
    }

    // A loop, not @Test(arguments:): a parameterized test in a @MainActor suite aborted swift test on the macOS 26
    // runtime ("freed pointer was not the last allocation").
    @Test func aRefusedAnswerOrDeclineKeepsTheQuestionOpen() async throws {
        for status in [409, 500] {
            try await Self().aRefusedAnswerOrDeclineKeepsTheQuestionOpen(status) // A fresh session each time.
        }
    }

    private func aRefusedAnswerOrDeclineKeepsTheQuestionOpen(_ status: Int) async throws {
        await server.ask("Merge now?", options: [.init(id: "merge", label: "Merge now")])
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("asked") { live.chat.question != nil }
        let question = try #require(live.chat.question)

        await server.refuseNextRequest(status)
        await #expect(throws: LiveRequestError.http(status)) { try await live.decline(question) }
        #expect(live.chat.question == question)

        await server.refuseNextRequest(status)
        await #expect(throws: LiveRequestError.http(status)) {
            try await live.answer(question, options: ["merge"])
        }
        #expect(live.chat.question == question)
    }

    // A loop, not @Test(arguments:): a parameterized test in a @MainActor suite aborted swift test on the macOS 26
    // runtime ("freed pointer was not the last allocation").
    @Test func aRefusedEditRetryOrRemoveChangesNothing() async throws {
        for status in [409, 500] {
            try await Self().aRefusedEditRetryOrRemoveChangesNothing(status) // A fresh session each time.
        }
    }

    private func aRefusedEditRetryOrRemoveChangesNothing(_ status: Int) async throws {
        await server.setState(.running)
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("live") { live.phase == .live }
        let queued = try await live.send("Merge it.", clientRef: "q")
        try await eventually("queued") { live.chat.message(queued)?.status == .queued }

        await server.refuseNextRequest(status)
        await #expect(throws: LiveRequestError.http(status)) { try await live.edit(queued, text: "Changed.") }
        await server.refuseNextRequest(status)
        await #expect(throws: LiveRequestError.http(status)) { try await live.remove(queued) }
        await server.setStatus(queued, .failed)
        try await eventually("failed") { live.chat.message(queued)?.status == .failed }
        await server.refuseNextRequest(status)
        await #expect(throws: LiveRequestError.http(status)) { try await live.retry(queued) }

        try await Task.sleep(for: .milliseconds(50))
        #expect(live.chat.message(queued)?.text == "Merge it.")
        #expect(live.chat.message(queued)?.status == .failed)
    }

    @Test func aQuestionGoesToBothClientsAndTheFirstAnswerWins() async throws {
        let phone = model()
        let mac = model()
        let following = [follow(phone), follow(mac)]
        defer { following.forEach { $0.cancel() } }
        try await eventually("both live") { phone.phase == .live && mac.phase == .live }

        await server.ask("Merge now or wait?", options: [.init(id: "merge", label: "Merge now"),
                                                         .init(id: "wait", label: "Wait")])
        try await eventually("asked on both") { phone.chat.question != nil && mac.chat.question != nil }
        try await eventually("waits on the person") { phone.chat.state?.phase == .requiresAction }

        try await phone.answer(try #require(phone.chat.question), options: ["merge"], text: "and tag it")
        try await eventually("closed on the other") { mac.chat.question == nil }
        try await eventually("the answer shows") { mac.chat.messages.last?.text == "Merge now: and tag it" }
        try await eventually("running again") { phone.chat.state?.phase == .running }
    }

    @Test func aQuestionStillOpenIsAskedAgainAfterAResume() async throws {
        await server.ask("Which one?", options: [.init(id: "a", label: "A")])
        let live = model()
        let following = follow(live)
        defer { following.cancel() }
        try await eventually("asked") { live.chat.question?.message == "Which one?" }
    }
}
