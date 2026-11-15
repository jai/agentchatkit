import Foundation
import Testing
@testable import AgentChatLive

/// The golden fixtures (protocol/fixtures, docs/live-protocol.md): the same files the server's conformance suite runs.
enum Fixtures {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "protocol/fixtures")

    static func load(_ name: String) throws -> [String: JSONValue] {
        let data = try Data(contentsOf: directory.appending(path: name))
        guard case let .object(fields) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return fields
    }

    static func data(_ value: JSONValue) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue) throws -> T {
        try JSONDecoder().decode(type, from: data(value))
    }

    /// The scenarios with a `client` section that runs frames.
    static let clientScenarios = [
        "connect-fresh.json", "reconnect-resume.json", "cursor-expired.json", "duplicate.json", "out-of-order.json",
        "snapshot-reset.json", "message-update.json", "reply-lifecycle.json", "earlier.json", "display-order.json",
    ]
}

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        if case let .object(fields) = self { fields[key] } else { nil }
    }

    var array: [JSONValue] {
        if case let .array(list) = self { list } else { [] }
    }

    var string: String? {
        if case let .string(text) = self { text } else { nil }
    }

    var int: Int? {
        if case let .number(number) = self { Int(number) } else { nil }
    }

    var isNull: Bool { self == .null }
}

struct FixtureTests {
    @Test(arguments: Fixtures.clientScenarios)
    func theClientEndsWhereTheFixtureSays(_ name: String) throws {
        let client = try #require(Fixtures.load(name)["client"])
        var chat = try Self.start(client["start"])
        for input in client["inputs"]?.array ?? [] {
            chat.take(try LiveFrame.decode(Fixtures.data(try #require(input["frame"]))))
        }
        try Self.expect(chat, matches: try #require(client["expect"]), name)
        if case let .object(ticks)? = client["ticks"] {
            for (id, count) in ticks {
                #expect(chat.reply(id)?.ticks?.rawValue == count.int, "\(name): ticks of \(id)")
            }
        }
    }

    @Test func everyFrameDecodesAndEncodesToItsSSEText() throws {
        let frames = try #require(Fixtures.load("frames.json")["frames"]).array
        #expect(frames.count >= 8)
        let parser = LiveEventParser()
        for entry in frames {
            let json = try #require(entry["json"])
            let frame = try LiveFrame.decode(Fixtures.data(json))
            #expect(frame.type == json["type"]?.string)
            let sse = try #require(entry["sse"]?.string)
            // Parsed from its SSE text, it is the same frame.
            let parsed = sse.split(separator: "\n").compactMap { parser.frame(from: String($0)) }
            #expect(parsed == [frame])
            // Encoded again, it reads back the same.
            let again = try LiveFrame.decode(JSONEncoder().encode(frame))
            #expect(again == frame)
            // And its SSE lines are the fixture's, but for key order inside the JSON.
            let ours = try frame.sse().split(separator: "\n")
            let theirs = sse.split(separator: "\n")
            #expect(ours.count == theirs.count)
            #expect(ours.first == theirs.first)
        }
    }

    @Test func framesAndFieldsItDoesNotKnowAreIgnored() throws {
        let unknown = try #require(Fixtures.load("frames.json")["unknown"])
        var chat = LiveChat()
        let parser = LiveEventParser()
        for line in try #require(unknown["sse"]?.string).split(separator: "\n") {
            if let frame = parser.frame(from: String(line)) {
                chat.take(frame)
            }
        }
        try Self.expect(chat, matches: try #require(unknown["expect"]), "unknown")
    }

    @Test func refusalsAndClosesTellTheClientWhatToDo() throws {
        let fixture = try Fixtures.load("refusals.json")
        for entry in fixture["http"]?.array ?? [] {
            let action = LiveAction.forStatus(
                try #require(entry["status"]?.int), error: entry["error"]?.string,
                retryAfterSeconds: entry["retry_after"]?.int
            )
            #expect(Self.name(action) == entry["action"]?.string, "HTTP \(entry["status"]?.int ?? 0)")
        }
        for entry in fixture["close"]?.array ?? [] {
            let close = LiveClose(
                code: try #require(entry["code"]?.int), reason: entry["reason"]?.string ?? "",
                retryAfterMs: entry["retry_after_ms"]?.int ?? 0
            )
            #expect(Self.name(LiveAction.forClose(close)) == entry["action"]?.string, "close \(close.code)")
        }
        let backoff = (fixture["backoff_ms"]?.array ?? []).compactMap(\.int)
        for (attempt, ms) in backoff.enumerated() {
            #expect(LiveTiming.standard.backoff(attempt: attempt) == .milliseconds(ms))
        }
        #expect(LiveTiming.standard.readInterval == .milliseconds(fixture["read_interval_ms"]?.int ?? 0))
        #expect(LiveTiming.standard.backoffResetsAfter == .milliseconds(fixture["backoff_resets_after_ms"]?.int ?? 0))
    }

    @Test func aWriteAnswerIsTakenByItsSeqLikeAFrame() throws {
        let writes = try #require(Fixtures.load("writes.json")["writes"]).array
        for write in writes {
            var answer = try #require(write["answer"])
            if case var .object(fields) = answer {
                fields["seq"] = .number(1)
                answer = .object(fields)
            }
            let reply = try Fixtures.decode(LiveReply.self, answer)
            var chat = LiveChat()
            chat.take(reply)
            #expect(chat.reply(reply.id)?.status == reply.status)
        }
    }

    // MARK: -

    static func start(_ value: JSONValue?) throws -> LiveChat {
        guard let value, !value.isNull else {
            return LiveChat()
        }
        return LiveChat(
            cursor: value["cursor"]?.string, seq: value["seq"]?.int ?? 0,
            messages: try Fixtures.decode([LiveMessage].self, value["messages"] ?? .array([])),
            replies: try Fixtures.decode([LiveReply].self, value["replies"] ?? .array([])),
            state: try value["state"].flatMap { $0.isNull ? nil : try Fixtures.decode(LiveState.self, $0) },
            moreBefore: value["more_before"] == .bool(true)
        )
    }

    static func expect(_ chat: LiveChat, matches expect: JSONValue, _ name: String) throws {
        #expect(chat.cursor == expect["cursor"]?.string, "\(name): cursor")
        #expect(chat.seq == expect["seq"]?.int, "\(name): seq")
        #expect(chat.moreBefore == (expect["more_before"] == .bool(true)), "\(name): more_before")
        let messages = expect["messages"]?.array ?? []
        #expect(chat.messages.map(\.id) == messages.compactMap { $0["id"]?.string }, "\(name): message order")
        for (held, want) in zip(chat.messages, messages) {
            #expect(held.seq == want["seq"]?.int, "\(name): \(held.id) seq")
            #expect(held.text == want["text"]?.string, "\(name): \(held.id) text")
            #expect(held.partial == (want["partial"] == .bool(true)), "\(name): \(held.id) partial")
        }
        let replies = expect["replies"]?.array ?? []
        #expect(chat.replies.map(\.id) == replies.compactMap { $0["id"]?.string }, "\(name): replies")
        for (held, want) in zip(chat.replies, replies) {
            #expect(held.seq == want["seq"]?.int, "\(name): \(held.id) seq")
            #expect(held.status.rawValue == want["status"]?.string, "\(name): \(held.id) status")
            #expect(held.messageID == want["message_id"]?.string, "\(name): \(held.id) message_id")
        }
        if let state = expect["state"], !state.isNull {
            #expect(chat.state?.seq == state["seq"]?.int, "\(name): state seq")
            #expect(chat.state?.working == (state["working"] == .bool(true)), "\(name): working")
            #expect(chat.state?.activity == state["activity"]?.string, "\(name): activity")
            #expect(chat.state?.waiting?.id == state["waiting"]?.string, "\(name): waiting")
        } else {
            #expect(chat.state == nil, "\(name): no state")
        }
    }

    static func name(_ action: LiveAction) -> String {
        switch action {
        case .stop: "stop"
        case .reauth: "reauth"
        case .read: "read"
        case .backoff: "backoff"
        case .now: "now"
        case .after: "after"
        }
    }
}
