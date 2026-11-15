import Foundation

// The parts of ACP v2 our profile uses (docs/live-protocol.md), read from and written as JSON-RPC 2.0.

/// One JSON-RPC message on the session stream, from the host.
public enum AcpIncoming: Equatable, Sendable {
    /// `session/update`: the update, and the cursor it moves the chat to.
    case update(JSONValue, cursor: String?)
    /// `elicitation/create`: the agent asks, and waits on the answer.
    case question(LiveQuestion)
    /// `$/cancel_request`: a request of the host's that is no longer open (another client answered it).
    case cancel(requestID: JSONValue)
    /// The answer to one of the client's requests.
    case result(id: Int, JSONValue)
    case error(id: Int, code: Int, message: String)
    /// Anything else: ignored.
    case other

    public static func parse(_ message: JSONValue) -> AcpIncoming {
        if let method = message["method"]?.string {
            let params = message["params"] ?? .null
            switch method {
            case "session/update":
                guard let update = params["update"] else {
                    return .other
                }
                return .update(update, cursor: params.at("_meta", "agentchatkit", "cursor")?.string)
            case "elicitation/create":
                guard let id = message["id"], let question = LiveQuestion(requestID: id, params: params) else {
                    return .other
                }
                return .question(question)
            case "$/cancel_request":
                return params["requestId"].map { .cancel(requestID: $0) } ?? .other
            default:
                return .other
            }
        }
        guard let id = message["id"]?.int else {
            return .other
        }
        if let error = message["error"] {
            return .error(id: id, code: error["code"]?.int ?? 0, message: error["message"]?.string ?? "")
        }
        return .result(id: id, message["result"] ?? .null)
    }
}

/// The JSON-RPC errors the profile names.
public enum AcpError {
    /// `session/resume` with a cursor the host can't resume from.
    public static let invalidParams = -32602
    /// An edit or removal of a message no longer `pending` or `queued`.
    public static let conflict = -32009
    public static let methodNotFound = -32601
}

enum Acp {
    static let protocolVersion = 2

    static func request(_ id: Int, _ method: String, _ params: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params]
    }

    static func response(_ id: JSONValue, result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func initialize(_ id: Int, client: String, version: String) -> JSONValue {
        request(id, "initialize", [
            "protocolVersion": .number(Double(protocolVersion)),
            "clientCapabilities": ["elicitation": ["form": [:]]],
            "clientInfo": ["name": .string(client), "version": .string(version)],
        ])
    }

    static func resume(_ id: Int, session: String, cursor: String?) -> JSONValue {
        let replay: JSONValue = cursor.map { ["type": "_cursor", "cursor": .string($0)] } ?? ["type": "start"]
        return request(id, "session/resume", ["sessionId": .string(session), "cwd": "/", "replayFrom": replay])
    }

    /// A prompt's content: its words, then its screenshots inline.
    static func prompt(_ text: String, images: [Data]) -> JSONValue {
        var blocks: [JSONValue] = []
        if !text.isEmpty {
            blocks.append(["type": "text", "text": .string(text)])
        }
        for image in images {
            blocks.append(["type": "image", "mimeType": "image/jpeg", "data": .string(image.base64EncodedString())])
        }
        return .array(blocks)
    }
}

public extension LiveQuestion {
    /// From `elicitation/create` form params: `choice` (one of an enum) or `choices` (several), and `text`.
    init?(requestID: JSONValue, params: JSONValue) {
        guard let message = params["message"]?.string else {
            return nil
        }
        let properties = params.at("requestedSchema", "properties")
        let single = properties?["choice"]
        let several = properties?.at("choices", "items")
        let schema = single ?? several
        let ids = schema?["enum"]?.array?.compactMap(\.string) ?? []
        let names = schema?["enumNames"]?.array?.compactMap(\.string) ?? []
        self.init(
            requestID: requestID, message: message,
            options: ids.enumerated().map { index, id in
                Option(id: id, label: index < names.count ? names[index] : id)
            },
            multiple: single == nil && several != nil, freeText: properties?["text"] != nil
        )
    }
}

/// When a message was written, as the wire writes it.
public enum LiveDates {
    public static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }

    public static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
