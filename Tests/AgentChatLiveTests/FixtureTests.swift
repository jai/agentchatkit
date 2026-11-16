@testable import AgentChatLive
import Foundation
import Testing

/// The profile's golden fixtures (protocol/fixtures, docs/live-protocol.md): the same files the server's conformance
/// suite runs. Here, each scenario's `client` half.
enum Fixtures {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "protocol/fixtures")

    static func load(_ name: String) throws -> JSONValue {
        try JSONValue.decode(Data(contentsOf: directory.appending(path: name)))
    }

    static let scenarios = [
        "resume-start.json", "resume-cursor.json", "display-order.json", "prompt-lifecycle.json", "question.json",
    ]
}

struct FixtureTests {
    @Test(arguments: Fixtures.scenarios)
    func theClientEndsWhereTheFixtureSays(_ name: String) throws {
        let client = try #require(try Fixtures.load(name)["client"])
        var chat = Self.start(client["start"])
        for message in client["messages"]?.array ?? [] {
            chat.take(AcpIncoming.parse(message))
        }
        try Self.check(chat, client["expect"], name)
        if let then = client["then"]?.array {
            for message in then {
                chat.take(AcpIncoming.parse(message))
            }
            try Self.check(chat, client["expect_then"], name + " then")
        }
        if let bubbles = client["bubbles"]?.array {
            #expect(chat.chatMessages.map(\.id) == bubbles.compactMap(\.string), "\(name): bubbles")
        }
        for (id, count) in client["ticks"]?.object ?? [:] {
            #expect(chat.message(id)?.ticks?.rawValue == count.int, "\(name): ticks of \(id)")
        }
    }

    @Test func anExpiredCursorsReplayReplacesEverything() throws {
        let client = try #require(try Fixtures.load("resume-expired.json")["client"])
        let held = Self.start(client["start"])
        #expect(!held.messages.isEmpty)
        // The resume answered -32602; the client resumed from start into a fresh chat, which replaces the held one.
        var replay = LiveChat()
        for message in client["replay"]?.array ?? [] {
            replay.take(AcpIncoming.parse(message))
        }
        try Self.check(replay, client["expect"], "resume-expired")
    }

    @Test func everyHostMessageIsReadAndEveryRequestIsWrittenAsTheFixtureSays() throws {
        let fixture = try Fixtures.load("messages.json")
        for entry in fixture["host_to_client"]?.array ?? [] {
            let parsed = AcpIncoming.parse(try #require(entry["message"]))
            #expect(parsed != .other, "\(entry["name"]?.string ?? ""): not read")
        }
        let requests = Dictionary(uniqueKeysWithValues: (fixture["client_to_host"]?.array ?? []).compactMap { entry in
            entry["name"]?.string.map { ($0, entry["message"] ?? .null) }
        })
        let initialize = Acp.initialize(1, client: "AgentChatLive", version: "0.3.0")
        #expect(initialize.at("params", "clientCapabilities") == requests["initialize"]?.at("params", "clientCapabilities"))
        #expect(initialize.at("params", "protocolVersion") == requests["initialize"]?.at("params", "protocolVersion"))
        #expect(Acp.resume(2, session: "chat-1", cursor: nil) == requests["resume from start"])
        #expect(Acp.resume(3, session: "chat-1", cursor: "c:2") == requests["resume from a cursor"])
        let words = Acp.prompt("Merge it.", images: [])
        #expect(words.array?.first == requests["prompt"]?.at("params", "prompt")?.array?.first)
    }

    @Test func theQuestionReadsItsOptionsAndWhatItTakes() throws {
        let entry = try #require(try Fixtures.load("messages.json")["host_to_client"]?.array?.first {
            $0["name"]?.string == "question"
        })
        guard case let .question(question) = AcpIncoming.parse(try #require(entry["message"])) else {
            Issue.record("not a question")
            return
        }
        #expect(question.message == "Merge now or wait for review?")
        #expect(question.options.map(\.label) == ["Merge now", "Wait for review"])
        #expect(!question.multiple)
        #expect(question.freeText)
    }

    @Test func theTransportFixtureIsTheModelsTiming() throws {
        let transport = try Fixtures.load("transport.json")
        for (attempt, ms) in (transport["backoff_ms"]?.array ?? []).compactMap(\.int).enumerated() {
            #expect(LiveTiming.standard.backoff(attempt: attempt) == .milliseconds(ms))
        }
        #expect(LiveTiming.standard.backoffResetsAfter == .milliseconds(transport["backoff_resets_after_ms"]?.int ?? 0))
    }

    // MARK: -

    static func start(_ value: JSONValue?) -> LiveChat {
        guard let value, !value.isNull else {
            return LiveChat()
        }
        var chat = LiveChat()
        for update in value["messages"]?.array ?? [] {
            chat.take(.update(update, cursor: nil))
        }
        if let state = value["state"], !state.isNull {
            chat.take(.update(state, cursor: nil))
        }
        chat.take(.update(.null, cursor: value["cursor"]?.string))
        return chat
    }

    static func check(_ chat: LiveChat, _ expect: JSONValue?, _ name: String) throws {
        let expect = try #require(expect)
        #expect(chat.cursor == expect["cursor"]?.string, "\(name): cursor")
        let messages = expect["messages"]?.array ?? []
        #expect(chat.messages.map(\.id) == messages.compactMap { $0["id"]?.string }, "\(name): order")
        for (held, want) in zip(chat.messages, messages) {
            #expect(held.kind.rawValue == want["kind"]?.string, "\(name): \(held.id) kind")
            #expect(held.text == want["text"]?.string, "\(name): \(held.id) text")
            #expect(held.status?.rawValue == want["status"]?.string, "\(name): \(held.id) status")
        }
        if let state = expect["state"], !state.isNull {
            #expect(chat.state?.phase.rawValue == state["state"]?.string, "\(name): state")
            #expect(chat.state?.activity == state["activity"]?.string, "\(name): activity")
        } else {
            #expect(chat.state == nil, "\(name): no state")
        }
        let question: JSONValue? = expect["question"]?.isNull == false ? expect["question"] : Optional.none
        #expect(chat.question?.requestID == question, "\(name): question")
    }
}
