import Foundation

/// Who wrote one of the people's messages: a chat can have several people.
public struct LiveSender: Equatable, Sendable {
    public var login: String
    public var name: String?

    public init(login: String, name: String? = nil) {
        self.login = login
        self.name = name
    }
}

/// A file on a message: a screenshot, a video. The host signs `uri`, or makes it relative to its `/acp`.
public struct LiveAttachment: Equatable, Sendable {
    public var name: String
    public var uri: String
    public var mimeType: String?
    public var width: Int?
    public var height: Int?
    public var durationMs: Int?
}

public struct LiveMessage: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        /// A person's words: `user_message`.
        case user
        /// The agent's words: `agent_message`.
        case agent
        /// A tool the agent called: `tool_call_update`.
        case tool
    }

    /// How far one of the person's messages got, as the host reports it.
    public enum Status: String, Sendable {
        case pending, queued, delivering, delivered, failed, removed
    }

    public let id: String
    public var kind: Kind
    public var text: String
    public var at: String?
    public var toolName: String?
    public var status: Status?
    public var sender: LiveSender?
    public var clientRef: String?
    public var detail: String?
    public var attachments: [LiveAttachment] = []
    public var extra: JSONValue?

    public init(id: String, kind: Kind, text: String = "", at: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.at = at
    }

    public var date: Date? { at.flatMap(LiveDates.parse) }
}

/// The agent's turn, as `state_update` reports it.
public struct LiveState: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case running, idle
        case requiresAction = "requires_action"
        case unknown
    }

    public var phase: Phase
    public var stopReason: String?
    /// What it is doing now, in a few words.
    public var activity: String?
    /// Why it stopped short of an answer.
    public var problem: String?
    public var extra: JSONValue?

    public init(phase: Phase, stopReason: String? = nil, activity: String? = nil, problem: String? = nil) {
        self.phase = phase
        self.stopReason = stopReason
        self.activity = activity
        self.problem = problem
    }

    public var working: Bool { phase == .running }
}

/// The agent's open question (`elicitation/create`): it waits on the person.
public struct LiveQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    /// The JSON-RPC id of the request: the answer is its response.
    public var requestID: JSONValue
    public var message: String
    public var options: [Option]
    /// More than one option may be chosen.
    public var multiple: Bool
    /// Words may be sent instead of, or with, options.
    public var freeText: Bool

    public init(requestID: JSONValue, message: String, options: [Option], multiple: Bool, freeText: Bool) {
        self.requestID = requestID
        self.message = message
        self.options = options
        self.multiple = multiple
        self.freeText = freeText
    }
}

/// One chat as the profile builds it from ACP updates: what the views show, and the cursor it resumes from. A value:
/// every message from the session stream goes through `take`.
public struct LiveChat: Equatable, Sendable {
    /// In display order: by `at`, not by arrival (docs/live-protocol.md, "Display order").
    public private(set) var messages: [LiveMessage] = []
    public private(set) var state: LiveState?
    public private(set) var question: LiveQuestion?
    /// The session's config options by id, as `config_option_update` sets them: `model`, `effort`.
    public private(set) var options: [String: String] = [:]
    /// What the next resume continues from; `nil`: resume from start.
    public private(set) var cursor: String?
    private var sortDates: [String: Date] = [:]

    public init() {}

    /// A chat as kept from before, resumed from `cursor`.
    public init(cursor: String?, messages: [LiveMessage], state: LiveState? = nil) {
        self.cursor = cursor
        self.state = state
        for message in messages {
            insert(message)
        }
    }

    public var model: String? { options["model"] }
    public var effort: String? { options["effort"] ?? options["reasoning"] }

    public func message(_ id: String) -> LiveMessage? {
        messages.first { $0.id == id }
    }

    /// Takes one message from the session stream.
    public mutating func take(_ incoming: AcpIncoming) {
        switch incoming {
        case let .update(update, cursor):
            apply(update)
            if let cursor {
                self.cursor = cursor
            }
        case let .question(question):
            self.question = question
        case let .cancel(id):
            if question?.requestID == id {
                question = nil
            }
        case .result, .error, .other:
            break
        }
    }

    /// The question was answered here.
    mutating func answered(_ requestID: JSONValue) {
        if question?.requestID == requestID {
            question = nil
        }
    }

    // MARK: - Updates

    private mutating func apply(_ update: JSONValue) {
        let ours = update.at("_meta", "agentchatkit")
        switch update["sessionUpdate"]?.string {
        case "user_message", "agent_message":
            guard let id = update["messageId"]?.string else {
                return
            }
            let kind: LiveMessage.Kind = update["sessionUpdate"]?.string == "user_message" ? .user : .agent
            upsert(id, kind) { message in
                if let content = update["content"] {
                    message.text = Self.text(content)
                    message.attachments = Self.attachments(content)
                }
                if let ours {
                    Self.patch(&message, with: ours)
                }
            }
        case "user_message_chunk", "agent_message_chunk":
            guard let id = update["messageId"]?.string, let block = update["content"] else {
                return
            }
            let kind: LiveMessage.Kind = update["sessionUpdate"]?.string == "user_message_chunk" ? .user : .agent
            upsert(id, kind) { message in
                message.text += block["text"]?.string ?? ""
            }
        case "tool_call_update":
            guard let id = update["toolCallId"]?.string else {
                return
            }
            upsert(id, .tool) { message in
                if let title = update["title"]?.string {
                    message.text = title
                }
                if let name = update["name"]?.string {
                    message.toolName = name
                }
                if let ours {
                    Self.patch(&message, with: ours)
                }
            }
        case "state_update":
            var state = LiveState(
                phase: LiveState.Phase(rawValue: update["state"]?.string ?? "") ?? .unknown,
                stopReason: update["stopReason"]?.string, activity: ours?["activity"]?.string,
                problem: ours?["problem"]?.string
            )
            state.extra = ours?["extra"]
            self.state = state
        case "config_option_update":
            for option in update["configOptions"]?.array ?? [] {
                if let id = option["id"]?.string {
                    options[id] = option["currentValue"]?.string
                }
            }
        default:
            break
        }
    }

    private mutating func upsert(_ id: String, _ kind: LiveMessage.Kind, _ change: (inout LiveMessage) -> Void) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            change(&messages[index])
        } else {
            var message = LiveMessage(id: id, kind: kind)
            change(&message)
            insert(message)
        }
    }

    /// A message first taken: after every message that sorts at or before it, so equal `at` keeps the order taken.
    private mutating func insert(_ message: LiveMessage) {
        let date = message.date ?? messages.last.flatMap { sortDates[$0.id] } ?? .distantPast
        sortDates[message.id] = date
        var index = messages.endIndex
        while index > messages.startIndex, (sortDates[messages[index - 1].id] ?? .distantPast) > date {
            index -= 1
        }
        messages.insert(message, at: index)
    }

    /// `_meta.agentchatkit` replaces ours whole: `_meta` patches by top-level key, and ours is one key.
    private static func patch(_ message: inout LiveMessage, with ours: JSONValue) {
        message.at = ours["at"]?.string ?? message.at
        message.status = ours["status"]?.string.flatMap(LiveMessage.Status.init)
        message.clientRef = ours["clientRef"]?.string
        message.detail = ours["detail"]?.string
        message.extra = ours["extra"]
        if let sender = ours["sender"], let login = sender["login"]?.string {
            message.sender = LiveSender(login: login, name: sender["name"]?.string)
        } else {
            message.sender = nil
        }
    }

    private static func text(_ content: JSONValue) -> String {
        (content.array ?? []).compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }
            .joined(separator: "\n\n")
    }

    private static func attachments(_ content: JSONValue) -> [LiveAttachment] {
        (content.array ?? []).compactMap { block in
            guard block["type"]?.string == "resource_link", let uri = block["uri"]?.string else {
                return nil
            }
            let ours = block.at("_meta", "agentchatkit")
            return LiveAttachment(
                name: block["name"]?.string ?? "", uri: uri, mimeType: block["mimeType"]?.string,
                width: ours?["width"]?.int, height: ours?["height"]?.int, durationMs: ours?["durationMs"]?.int
            )
        }
    }
}

/// Splits a stream's lines into JSON-RPC messages: each `data:` line is one (the profile keeps them on one line, and a
/// line stream drops the blank line between events). Comments, `event:` and `id:` lines carry none.
public struct LiveEventParser: Sendable {
    public init() {}

    public func message(from line: String) -> JSONValue? {
        guard line.hasPrefix("data:") else {
            return nil
        }
        var payload = line.dropFirst(5)
        if payload.first == " " {
            payload = payload.dropFirst()
        }
        return try? JSONValue.decode(Data(payload.utf8))
    }
}
