import Foundation

// The live chat protocol's items and frames, as docs/live-protocol.md defines them (v1). Field names are the wire's.

/// Any JSON: a host's `extra`, passed through untouched.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// Who wrote a message of the person's side: a chat can have several people.
public struct LiveSender: Codable, Equatable, Sendable {
    public var login: String
    public var name: String?

    public init(login: String, name: String? = nil) {
        self.login = login
        self.name = name
    }
}

/// A screenshot on a message. The host makes `url`: absolute and signed, or relative to the chat's `live/`.
public struct LiveImage: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var url: String
    public var mediaType: String
    public var width: Int?
    public var height: Int?

    public init(id: String, url: String, mediaType: String = "image/jpeg", width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.url = url
        self.mediaType = mediaType
        self.width = width
        self.height = height
    }

    enum CodingKeys: String, CodingKey {
        case id, url, width, height
        case mediaType = "media_type"
    }
}

public struct LiveMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case user, assistant, tool
    }

    public var id: String
    public var seq: Int
    public var role: Role
    public var text: String
    public var at: String?
    public var tool: String?
    public var partial: Bool
    public var replyID: String?
    public var sender: LiveSender?
    public var images: [LiveImage]
    public var extra: JSONValue?

    public init(
        id: String, seq: Int, role: Role, text: String, at: String? = nil, tool: String? = nil, partial: Bool = false,
        replyID: String? = nil, sender: LiveSender? = nil, images: [LiveImage] = [], extra: JSONValue? = nil
    ) {
        self.id = id
        self.seq = seq
        self.role = role
        self.text = text
        self.at = at
        self.tool = tool
        self.partial = partial
        self.replyID = replyID
        self.sender = sender
        self.images = images
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey {
        case id, seq, role, text, at, tool, partial, sender, images, extra
        case replyID = "reply_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        seq = try container.decode(Int.self, forKey: .seq)
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        at = try container.decodeIfPresent(String.self, forKey: .at)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        partial = try container.decodeIfPresent(Bool.self, forKey: .partial) ?? false
        replyID = try container.decodeIfPresent(String.self, forKey: .replyID)
        sender = try container.decodeIfPresent(LiveSender.self, forKey: .sender)
        images = try container.decodeIfPresent([LiveImage].self, forKey: .images) ?? []
        extra = try container.decodeIfPresent(JSONValue.self, forKey: .extra)
    }

    /// `at` as a date; `nil` without one, or one that is not ISO 8601.
    public var date: Date? { at.flatMap(LiveDates.parse) }
}

/// One of the person's replies: a message they sent, and how far it got.
public struct LiveReply: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case pending, queued, delivering, delivered, failed, removed
    }

    public var id: String
    public var seq: Int
    public var clientRef: String?
    public var status: Status
    public var text: String
    public var at: String?
    public var detail: String?
    public var messageID: String?
    public var sender: LiveSender?
    public var images: [LiveImage]
    public var extra: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, seq, status, text, at, detail, sender, images, extra
        case clientRef = "client_ref"
        case messageID = "message_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        seq = try container.decode(Int.self, forKey: .seq)
        clientRef = try container.decodeIfPresent(String.self, forKey: .clientRef)
        status = try container.decode(Status.self, forKey: .status)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        at = try container.decodeIfPresent(String.self, forKey: .at)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        messageID = try container.decodeIfPresent(String.self, forKey: .messageID)
        sender = try container.decodeIfPresent(LiveSender.self, forKey: .sender)
        images = try container.decodeIfPresent([LiveImage].self, forKey: .images) ?? []
        extra = try container.decodeIfPresent(JSONValue.self, forKey: .extra)
    }
}

/// The agent's open question: it waits on the person.
public struct LiveQuestion: Codable, Equatable, Sendable, Identifiable {
    public struct Option: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    public var id: String
    public var question: String
    public var options: [Option]
    public var multiple: Bool
    public var freeText: Bool

    enum CodingKeys: String, CodingKey {
        case id, question, options, multiple
        case freeText = "free_text"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        options = try container.decodeIfPresent([Option].self, forKey: .options) ?? []
        multiple = try container.decodeIfPresent(Bool.self, forKey: .multiple) ?? false
        freeText = try container.decodeIfPresent(Bool.self, forKey: .freeText) ?? true
    }
}

/// The chat as a whole: whether the agent works, on what, and whether it waits on the person.
public struct LiveState: Codable, Equatable, Sendable {
    public var seq: Int
    public var working: Bool
    public var activity: String?
    public var problem: String?
    public var model: String?
    public var effort: String?
    public var waiting: LiveQuestion?
    public var extra: JSONValue?

    public init(
        seq: Int, working: Bool, activity: String? = nil, problem: String? = nil, model: String? = nil,
        effort: String? = nil, waiting: LiveQuestion? = nil, extra: JSONValue? = nil
    ) {
        self.seq = seq
        self.working = working
        self.activity = activity
        self.problem = problem
        self.model = model
        self.effort = effort
        self.waiting = waiting
        self.extra = extra
    }
}

/// What the server sends: one SSE event on the stream, one element of a read's `frames`.
public enum LiveFrame: Equatable, Sendable {
    case hello(v: Int, chat: String, cursor: String, seq: Int, resumed: Bool)
    case snapshot(LiveSnapshot)
    case message(LiveMessage, cursor: String, seq: Int)
    case reply(LiveReply, cursor: String, seq: Int)
    case state(LiveState, cursor: String, seq: Int)
    case ping
    case close(LiveClose)
    case earlier(messages: [LiveMessage], moreBefore: Bool)
    /// A type this client does not know: ignored.
    case unknown(String)

    /// Decodes one frame's JSON.
    public static func decode(_ data: Data) throws -> LiveFrame {
        try JSONDecoder().decode(Wire.self, from: data).frame
    }

    private struct Wire: Decodable {
        let frame: LiveFrame

        enum Keys: String, CodingKey {
            case type, v, chat, cursor, seq, resumed, message, reply, state, messages, replies, code, reason
            case moreBefore = "more_before"
            case retryAfterMs = "retry_after_ms"
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "hello":
                frame = .hello(
                    v: try c.decode(Int.self, forKey: .v), chat: try c.decode(String.self, forKey: .chat),
                    cursor: try c.decode(String.self, forKey: .cursor), seq: try c.decode(Int.self, forKey: .seq),
                    resumed: try c.decode(Bool.self, forKey: .resumed)
                )
            case "snapshot":
                frame = .snapshot(LiveSnapshot(
                    cursor: try c.decode(String.self, forKey: .cursor), seq: try c.decode(Int.self, forKey: .seq),
                    messages: try c.decode([LiveMessage].self, forKey: .messages),
                    replies: try c.decodeIfPresent([LiveReply].self, forKey: .replies) ?? [],
                    state: try c.decodeIfPresent(LiveState.self, forKey: .state),
                    moreBefore: try c.decodeIfPresent(Bool.self, forKey: .moreBefore) ?? false
                ))
            case "message":
                frame = .message(
                    try c.decode(LiveMessage.self, forKey: .message),
                    cursor: try c.decode(String.self, forKey: .cursor), seq: try c.decode(Int.self, forKey: .seq)
                )
            case "reply":
                frame = .reply(
                    try c.decode(LiveReply.self, forKey: .reply),
                    cursor: try c.decode(String.self, forKey: .cursor), seq: try c.decode(Int.self, forKey: .seq)
                )
            case "state":
                frame = .state(
                    try c.decode(LiveState.self, forKey: .state),
                    cursor: try c.decode(String.self, forKey: .cursor), seq: try c.decode(Int.self, forKey: .seq)
                )
            case "ping":
                frame = .ping
            case "close":
                frame = .close(LiveClose(
                    code: try c.decode(Int.self, forKey: .code),
                    reason: try c.decodeIfPresent(String.self, forKey: .reason) ?? "",
                    retryAfterMs: try c.decodeIfPresent(Int.self, forKey: .retryAfterMs) ?? 0
                ))
            case "earlier":
                frame = .earlier(
                    messages: try c.decode([LiveMessage].self, forKey: .messages),
                    moreBefore: try c.decodeIfPresent(Bool.self, forKey: .moreBefore) ?? false
                )
            default:
                frame = .unknown(type)
            }
        }
    }
}

public struct LiveSnapshot: Equatable, Sendable {
    public var cursor: String
    public var seq: Int
    public var messages: [LiveMessage]
    public var replies: [LiveReply]
    public var state: LiveState?
    public var moreBefore: Bool

    public init(cursor: String, seq: Int, messages: [LiveMessage], replies: [LiveReply], state: LiveState?, moreBefore: Bool) {
        self.cursor = cursor
        self.seq = seq
        self.messages = messages
        self.replies = replies
        self.state = state
        self.moreBefore = moreBefore
    }
}

/// The server's last frame when it ends a stream itself.
public struct LiveClose: Equatable, Sendable {
    public var code: Int
    public var reason: String
    public var retryAfterMs: Int

    public init(code: Int, reason: String, retryAfterMs: Int = 0) {
        self.code = code
        self.reason = reason
        self.retryAfterMs = retryAfterMs
    }
}

/// A read's answer: `{"v": 1, "frames": [Frame]}`.
struct LiveReadAnswer: Decodable {
    let frames: [LiveFrame]

    enum Keys: String, CodingKey { case frames }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var list = try c.nestedUnkeyedContainer(forKey: .frames)
        var frames: [LiveFrame] = []
        while !list.isAtEnd {
            let raw = try list.decode(JSONValue.self)
            frames.append(try LiveFrame.decode(JSONEncoder().encode(raw)))
        }
        self.frames = frames
    }
}

public enum LiveDates {
    public static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}

extension LiveFrame: Encodable {
    private enum Keys: String, CodingKey {
        case type, v, chat, cursor, seq, resumed, message, reply, state, messages, replies, code, reason
        case moreBefore = "more_before"
        case retryAfterMs = "retry_after_ms"
    }

    /// The frame's type, as `event:` names it.
    public var type: String {
        switch self {
        case .hello: "hello"
        case .snapshot: "snapshot"
        case .message: "message"
        case .reply: "reply"
        case .state: "state"
        case .ping: "ping"
        case .close: "close"
        case .earlier: "earlier"
        case let .unknown(type): type
        }
    }

    /// The cursor it moves the chat to, when it has one.
    public var cursor: String? {
        switch self {
        case let .hello(_, _, cursor, _, _), let .message(_, cursor, _), let .reply(_, cursor, _),
             let .state(_, cursor, _):
            cursor
        case let .snapshot(snapshot):
            snapshot.cursor
        case .ping, .close, .earlier, .unknown:
            nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(type, forKey: .type)
        switch self {
        case let .hello(v, chat, cursor, seq, resumed):
            try c.encode(v, forKey: .v)
            try c.encode(chat, forKey: .chat)
            try c.encode(cursor, forKey: .cursor)
            try c.encode(seq, forKey: .seq)
            try c.encode(resumed, forKey: .resumed)
        case let .snapshot(snapshot):
            try c.encode(snapshot.cursor, forKey: .cursor)
            try c.encode(snapshot.seq, forKey: .seq)
            try c.encode(snapshot.messages, forKey: .messages)
            try c.encode(snapshot.replies, forKey: .replies)
            try c.encode(snapshot.state, forKey: .state)
            try c.encode(snapshot.moreBefore, forKey: .moreBefore)
        case let .message(message, cursor, seq):
            try c.encode(cursor, forKey: .cursor)
            try c.encode(seq, forKey: .seq)
            try c.encode(message, forKey: .message)
        case let .reply(reply, cursor, seq):
            try c.encode(cursor, forKey: .cursor)
            try c.encode(seq, forKey: .seq)
            try c.encode(reply, forKey: .reply)
        case let .state(state, cursor, seq):
            try c.encode(cursor, forKey: .cursor)
            try c.encode(seq, forKey: .seq)
            try c.encode(state, forKey: .state)
        case .ping, .unknown:
            break
        case let .close(close):
            try c.encode(close.code, forKey: .code)
            try c.encode(close.reason, forKey: .reason)
            try c.encode(close.retryAfterMs, forKey: .retryAfterMs)
        case let .earlier(messages, moreBefore):
            try c.encode(messages, forKey: .messages)
            try c.encode(moreBefore, forKey: .moreBefore)
        }
    }

    /// The frame as the stream sends it: `event:`, `id:` when it has a cursor, and one `data:` line.
    public func sse() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(self), as: UTF8.self)
        return "event: \(type)\n" + (cursor.map { "id: \($0)\n" } ?? "") + "data: \(json)\n\n"
    }
}

public extension LiveReply {
    init(
        id: String, seq: Int, clientRef: String?, status: Status, text: String, at: String?, detail: String? = nil,
        messageID: String? = nil, sender: LiveSender? = nil, images: [LiveImage] = [], extra: JSONValue? = nil
    ) {
        self.id = id
        self.seq = seq
        self.clientRef = clientRef
        self.status = status
        self.text = text
        self.at = at
        self.detail = detail
        self.messageID = messageID
        self.sender = sender
        self.images = images
        self.extra = extra
    }
}

public extension LiveQuestion {
    init(id: String, question: String, options: [Option], multiple: Bool = false, freeText: Bool = true) {
        self.id = id
        self.question = question
        self.options = options
        self.multiple = multiple
        self.freeText = freeText
    }
}

public extension LiveDates {
    /// `at` as the wire writes it.
    static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
