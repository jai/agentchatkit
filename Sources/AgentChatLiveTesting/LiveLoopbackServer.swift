import AgentChatLive
import DurableNetworking
import Foundation

/// One chat's host, in memory: the profile's agent side (docs/live-protocol.md) as an `HTTPTransport` and a
/// `StreamingTransport`, so a `LiveChatModel` follows it with no network. Tests, previews and the demo script the
/// agent through it, and take the network away with `setDown(true)` to watch a client reconnect.
public actor LiveLoopbackServer: HTTPTransport, StreamingTransport {
    public let session: String
    /// A prompt the person sent: its message id, words and whether they asked for it now.
    public typealias Prompted = @Sendable (_ message: String, _ text: String, _ force: Bool) async -> Void
    /// The answer to the open question: the chosen option ids and the words.
    public typealias Answered = @Sendable (_ options: [String], _ text: String?) async -> Void

    struct Connection {
        var stream: AsyncThrowingStream<String, any Error>.Continuation?
    }

    var log: [(seq: Int, update: JSONValue)] = []
    var order: [String] = []
    var current: [String: JSONValue] = [:]
    var state: JSONValue = ["sessionUpdate": "state_update", "state": "idle"]
    var seq = 0
    var forgottenBefore = 0
    var connections: [String: Connection] = [:]
    var question: (id: JSONValue, params: JSONValue)?
    var questions = 0
    var down = false
    var bearer: String?
    var prompted: Prompted?
    var answered: Answered?
    var userMessages = 0
    var refuseNext: Int?

    /// Every request, as `POST <rpc method>` or `GET stream`: what tests count.
    public private(set) var requests: [String] = []

    public init(session: String = "chat-1", bearer: String? = nil) {
        self.session = session
        self.bearer = bearer
    }

    // MARK: - The agent's side

    public func onPrompt(_ prompted: Prompted?) { self.prompted = prompted }
    public func onAnswer(_ answered: Answered?) { self.answered = answered }

    /// The next request after `initialize` is refused with this HTTP status, untouched: what a client does with a
    /// refusal.
    public func refuseNextRequest(_ status: Int) { refuseNext = status }

    /// Only this bearer is let in from now; `nil` lets any in.
    public func accept(bearer: String?) { self.bearer = bearer }

    /// Adds or changes a message: a `user_message`, `agent_message` or `tool_call_update` update.
    public func publish(_ update: JSONValue) {
        guard let id = update["messageId"]?.string ?? update["toolCallId"]?.string else {
            return
        }
        var merged = current[id]?.object ?? [:]
        for (key, value) in update.object ?? [:] {
            if key == "_meta", let patch = value.object, let held = merged["_meta"]?.object {
                merged["_meta"] = .object(held.merging(patch) { _, new in new })
            } else {
                merged[key] = value
            }
        }
        if current[id] == nil {
            order.append(id)
        }
        current[id] = .object(merged)
        record(update)
    }

    public func agentSays(_ id: String, _ text: String, at: Date = .now) {
        publish(Self.agentMessage(id, text, at: at))
    }

    public func tool(_ id: String, _ title: String, name: String, at: Date = .now) {
        publish([
            "sessionUpdate": "tool_call_update", "toolCallId": .string(id), "title": .string(title),
            "name": .string(name), "kind": "execute", "status": "completed",
            "_meta": ["agentchatkit": ["at": .string(LiveDates.string(at))]],
        ])
    }

    /// Moves one of the person's messages on: `delivering`, `delivered`, `failed`.
    public func setStatus(_ message: String, _ status: LiveMessage.Status) {
        guard var ours = current[message]?.at("_meta", "agentchatkit")?.object else {
            return
        }
        ours["status"] = .string(status.rawValue)
        publish(["sessionUpdate": "user_message", "messageId": .string(message),
                 "_meta": ["agentchatkit": .object(ours)], ])
    }

    public func setState(_ phase: LiveState.Phase, activity: String? = nil, problem: String? = nil) {
        var update: [String: JSONValue] = [
            "sessionUpdate": "state_update", "state": .string(phase.rawValue),
            "_meta": ["agentchatkit": ["activity": JSONValue(activity), "problem": JSONValue(problem)]],
        ]
        if phase == .idle {
            update["stopReason"] = "end_turn"
        }
        state = .object(update)
        record(state)
    }

    public var phase: LiveState.Phase {
        LiveState.Phase(rawValue: state["state"]?.string ?? "") ?? .unknown
    }

    /// The agent asks: `elicitation/create` to every connection, and the state waits on the person.
    public func ask(_ message: String, options: [LiveQuestion.Option], multiple: Bool = false, freeText: Bool = true) {
        questions += 1
        let ids = JSONValue.array(options.map { .string($0.id) })
        let names = JSONValue.array(options.map { .string($0.label) })
        var properties: [String: JSONValue] = [:]
        let choice: JSONValue = ["type": "string", "enum": ids, "enumNames": names]
        if multiple {
            properties["choices"] = ["type": "array", "items": choice]
        } else if !options.isEmpty {
            properties["choice"] = choice
        }
        if freeText {
            properties["text"] = ["type": "string"]
        }
        let id = JSONValue.string("q\(questions)")
        let params: JSONValue = [
            "sessionId": .string(session), "mode": "form", "message": .string(message),
            "requestedSchema": ["type": "object", "properties": .object(properties)],
        ]
        question = (id, params)
        for name in connections.keys {
            send(Self.questionMessage(id, params), to: name)
        }
        setState(.requiresAction)
    }

    /// Takes the network away: open streams drop, and every request fails as with no connection.
    public func setDown(_ down: Bool) {
        self.down = down
        if down {
            dropStreams()
        }
    }

    /// Ends every open stream, as a dropped connection does.
    public func dropStreams() {
        for name in connections.keys {
            connections[name]?.stream?.finish(throwing: URLError(.networkConnectionLost))
            connections[name]?.stream = nil
        }
    }

    /// Forgets every connection, as a restarted host does: the next stream gets `404`.
    public func forgetConnections() {
        dropStreams()
        connections = [:]
    }

    /// Forgets history: a cursor from before now gets `-32602`.
    public func forgetHistory() {
        forgottenBefore = seq
        log = []
    }

    public var openStreams: Int { connections.values.filter { $0.stream != nil }.count }

    // MARK: - StreamingTransport

    public func open(_ request: URLRequest) async throws -> LineStream {
        requests.append("GET stream")
        if down {
            throw URLError(.notConnectedToInternet)
        }
        if let refusal = refused(request) {
            return LineStream(response: response(request, refusal), lines: Self.empty())
        }
        guard let name = request.value(forHTTPHeaderField: "Acp-Connection-Id"), connections[name] != nil,
              request.value(forHTTPHeaderField: "Acp-Session-Id") == session else {
            return LineStream(response: response(request, 404), lines: Self.empty())
        }
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        connections[name]?.stream?.finish()
        connections[name]?.stream = continuation
        return LineStream(response: response(request, 200), lines: lines)
    }

    // MARK: - HTTPTransport

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let body = request.httpBody, let message = try? JSONValue.decode(body) else {
            return (Data(), response(request, 400))
        }
        requests.append("POST \(message["method"]?.string ?? "response")")
        if down {
            throw URLError(.notConnectedToInternet)
        }
        if let refusal = refused(request) {
            return (Data(), response(request, refusal))
        }
        if message["method"]?.string == "initialize" {
            let name = UUID().uuidString
            connections[name] = Connection()
            let answer: JSONValue = ["jsonrpc": "2.0", "id": message["id"] ?? .null, "result": [
                "protocolVersion": 2, "agentInfo": ["name": "LiveLoopbackServer", "version": "1"],
            ], ]
            return (try answer.data(), response(request, 200, ["Acp-Connection-Id": name]))
        }
        guard let name = request.value(forHTTPHeaderField: "Acp-Connection-Id"), connections[name] != nil else {
            return (Data(), response(request, 404))
        }
        guard request.value(forHTTPHeaderField: "Acp-Session-Id") == session else {
            return (Data(), response(request, 400)) // As the server package: a session's requests name it.
        }
        if let status = refuseNext {
            refuseNext = nil
            return (Data(), response(request, status))
        }
        if message["method"] == nil {
            await take(answer: message, from: name)
        } else {
            await handle(message, from: name)
        }
        return (Data(), response(request, 202))
    }

    // MARK: - Plumbing

    func record(_ update: JSONValue) {
        seq += 1
        log.append((seq, update))
        for name in connections.keys {
            send(Self.note(update, cursor: seq, session: session), to: name)
        }
    }

    func send(_ message: JSONValue, to name: String) {
        guard let data = try? message.data() else {
            return
        }
        connections[name]?.stream?.yield("data: " + String(decoding: data, as: UTF8.self))
    }

    func refused(_ request: URLRequest) -> Int? {
        guard let bearer else {
            return nil
        }
        return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(bearer)" ? nil : 401
    }

    func response(_ request: URLRequest, _ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url ?? URL(filePath: "/"), statusCode: status, httpVersion: "HTTP/2",
                        headerFields: headers) ?? HTTPURLResponse()
    }

    static func empty() -> LineStream.Lines {
        AsyncThrowingStream { $0.finish() }
    }

    public static func agentMessage(_ id: String, _ text: String, at: Date = .now) -> JSONValue {
        ["sessionUpdate": "agent_message", "messageId": .string(id),
         "content": [["type": "text", "text": .string(text)]],
         "_meta": ["agentchatkit": ["at": .string(LiveDates.string(at))]], ]
    }

    static func note(_ update: JSONValue, cursor: Int, session: String) -> JSONValue {
        ["jsonrpc": "2.0", "method": "session/update", "params": [
            "sessionId": .string(session), "update": update,
            "_meta": ["agentchatkit": ["cursor": .string("c:\(cursor)")]],
        ], ]
    }

    static func questionMessage(_ id: JSONValue, _ params: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "method": "elicitation/create", "params": params]
    }

    static func result(_ id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(_ id: JSONValue, _ code: Int, _ message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }
}
