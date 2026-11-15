import AgentChatLive
import DurableNetworking
import Foundation

/// One chat's live server, in memory: the protocol's server side (docs/live-protocol.md) as an `HTTPTransport` and a
/// `StreamingTransport`, so a `LiveChatModel` follows it with no network. Tests, previews and the demo script the
/// agent's side through it, and take the network away with `setDown(true)` to watch a client reconnect.
public actor LiveLoopbackServer: HTTPTransport, StreamingTransport {
    public let chatID: String
    /// What a write to `messages` or `answer` made: the demo's agent answers it.
    public typealias Sent = @Sendable (LiveReply) async -> Void

    private var order: [String] = []
    private var messages: [String: LiveMessage] = [:]
    private var replies: [String: LiveReply] = [:]
    private var replyOrder: [String] = []
    private var state: LiveState
    private var seq = 0
    /// Each change's frame, oldest first: what a cursor resumes from.
    private var changes: [LiveFrame] = []
    /// A cursor before this `seq` can no longer be resumed: the client gets a snapshot.
    private var forgottenBefore = 0
    private var streams: [UUID: AsyncThrowingStream<String, any Error>.Continuation] = [:]
    private var down = false
    private var bearer: String?
    private var sent: Sent?
    private var lastSendingReply = 0

    /// Every request, as `METHOD path?query`: what tests count.
    public private(set) var requests: [String] = []

    public init(chatID: String = "chat-1", bearer: String? = nil) {
        self.chatID = chatID
        self.bearer = bearer
        state = LiveState(seq: 0, working: false)
    }

    // MARK: - The host's side

    public func onSent(_ sent: Sent?) {
        self.sent = sent
    }

    /// Only this bearer is let in from now; `nil` lets any in.
    public func accept(bearer: String?) {
        self.bearer = bearer
    }

    /// Adds a message, or a new version of one with the same id.
    @discardableResult
    public func put(_ message: LiveMessage) -> LiveMessage {
        var message = message
        message.seq = next()
        if messages[message.id] == nil {
            order.append(message.id)
        }
        messages[message.id] = message
        publish(.message(message, cursor: cursor(seq), seq: seq))
        return message
    }

    @discardableResult
    public func put(_ reply: LiveReply) -> LiveReply {
        var reply = reply
        reply.seq = next()
        if replies[reply.id] == nil {
            replyOrder.append(reply.id)
        }
        replies[reply.id] = reply
        publish(.reply(reply, cursor: cursor(seq), seq: seq))
        return reply
    }

    public func set(_ state: LiveState) {
        var state = state
        state.seq = next()
        self.state = state
        publish(.state(state, cursor: cursor(seq), seq: seq))
    }

    public var currentState: LiveState { state }

    public func reply(_ id: String) -> LiveReply? { replies[id] }

    /// Takes the network away: open streams drop, and every request fails as with no connection. `false` brings it
    /// back.
    public func setDown(_ down: Bool) {
        self.down = down
        if down {
            dropStreams()
        }
    }

    /// Ends every open stream without a `close` frame, as a dropped connection does.
    public func dropStreams() {
        for stream in streams.values {
            stream.finish(throwing: URLError(.networkConnectionLost))
        }
        streams = [:]
    }

    /// Ends every open stream with a `close` frame.
    public func close(_ close: LiveClose) {
        for stream in streams.values {
            stream.yield(contentsOf: Self.lines(.close(close)))
            stream.finish()
        }
        streams = [:]
    }

    /// Forgets history: a cursor from before now gets a snapshot.
    public func forgetHistory() {
        forgottenBefore = seq + 1
        changes = []
    }

    public var openStreams: Int { streams.count }

    // MARK: - StreamingTransport

    public func open(_ request: URLRequest) async throws -> LineStream {
        let route = try route(request)
        guard route.path == "live" else {
            return LineStream(response: response(request, 404), lines: Self.body(Self.refusal("not_found")))
        }
        if let refusal = refuse(request, route) {
            return LineStream(response: response(request, refusal.status), lines: Self.body(refusal.body))
        }
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let id = UUID()
        let after = route.query["after"] ?? request.value(forHTTPHeaderField: "Last-Event-ID")
        let resumable = after.flatMap(resumeSeq)
        continuation.yield(contentsOf: Self.lines(.hello(
            v: 1, chat: chatID, cursor: cursor(seq), seq: seq, resumed: resumable != nil
        )))
        for frame in frames(after: resumable, limit: 100) {
            continuation.yield(contentsOf: Self.lines(frame))
        }
        streams[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.ended(id) }
        }
        return LineStream(response: response(request, 200), lines: lines)
    }

    private func ended(_ id: UUID) {
        streams[id] = nil
    }

    // MARK: - HTTPTransport

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let route = try route(request)
        if let refusal = refuse(request, route) {
            return (Data(refusal.body.utf8), response(request, refusal.status))
        }
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let parts = route.path.split(separator: "/").map(String.init)
        let replyID = parts.count >= 3 && parts[1] == "replies" ? parts[2] : nil
        switch (method, parts.dropFirst().first ?? "", parts.count) {
        case ("GET", "read", 2):
            return try json(request, 200, ReadAnswer(frames: read(route.query)))
        case ("POST", "messages", 2):
            return try await sendMessage(request, body)
        case ("POST", "replies", 4) where parts[3] == "force":
            guard let reply = replyID.flatMap({ replies[$0] }), reply.status == LiveReply.Status.queued else {
                return refusal(request, 409, "conflict")
            }
            return try json(request, 200, move(reply, to: .delivering))
        case ("DELETE", "replies", 3):
            guard let reply = replyID.flatMap({ replies[$0] }),
                  reply.status == .pending || reply.status == .queued else {
                return refusal(request, 409, "conflict")
            }
            return try json(request, 200, move(reply, to: .removed))
        case ("POST", "answer", 2):
            return try await answer(request, body)
        default:
            return refusal(request, 404, "not_found")
        }
    }

    // MARK: - Routes

    private func sendMessage(_ request: URLRequest, _ body: JSONValue?) async throws -> (Data, HTTPURLResponse) {
        guard case let .object(fields) = body, case let .string(clientRef)? = fields["client_ref"] else {
            return refusal(request, 400, "bad_request")
        }
        if let repeated = replies.values.first(where: { $0.clientRef == clientRef }) {
            return try json(request, 200, repeated)
        }
        let text = fields["text"].flatMap { if case let .string(text) = $0 { text } else { nil } } ?? ""
        let images = fields["images"].flatMap { if case let .array(list) = $0 { list.count } else { nil } } ?? 0
        guard !text.isEmpty || images > 0 else {
            return refusal(request, 400, "bad_request")
        }
        let force = fields["force"] == .bool(true)
        let reply = put(LiveReply(
            id: "rpl_\(replyOrder.count + 1)", seq: 0, clientRef: clientRef,
            status: state.working && !force ? .queued : .pending, text: text,
            at: LiveDates.string(.now), sender: LiveSender(login: "jai", name: "Jai"),
            images: (0..<images).map { LiveImage(id: "img\($0)", url: "images/img\($0)") }
        ))
        await sent?(reply)
        return try json(request, 201, replies[reply.id] ?? reply)
    }

    private func answer(_ request: URLRequest, _ body: JSONValue?) async throws -> (Data, HTTPURLResponse) {
        guard case let .object(fields) = body, case let .string(question)? = fields["question_id"],
              case let .string(clientRef)? = fields["client_ref"] else {
            return refusal(request, 400, "bad_request")
        }
        guard let waiting = state.waiting, waiting.id == question else {
            return refusal(request, 409, "conflict")
        }
        var chosen: [String] = []
        if case let .array(ids)? = fields["option_ids"] {
            chosen = ids.compactMap { if case let .string(id) = $0 { id } else { nil } }
        }
        var words = waiting.options.filter { chosen.contains($0.id) }.map(\.label).joined(separator: ", ")
        if case let .string(text)? = fields["text"], !text.isEmpty {
            words = words.isEmpty ? text : "\(words): \(text)"
        }
        let reply = put(LiveReply(
            id: "rpl_\(replyOrder.count + 1)", seq: 0, clientRef: clientRef, status: .pending, text: words,
            at: LiveDates.string(.now), sender: LiveSender(login: "jai", name: "Jai")
        ))
        var cleared = state
        cleared.waiting = nil
        set(cleared)
        await sent?(reply)
        return try json(request, 201, replies[reply.id] ?? reply)
    }

    private func move(_ reply: LiveReply, to status: LiveReply.Status) -> LiveReply {
        var reply = reply
        reply.status = status
        return put(reply)
    }

    private func read(_ query: [String: String]) -> [LiveFrame] {
        let limit = query["limit"].flatMap(Int.init) ?? 100
        if let before = query["before"], let index = order.firstIndex(of: before) {
            let start = max(0, index - limit)
            return [.earlier(messages: order[start..<index].compactMap { messages[$0] }, moreBefore: start > 0)]
        }
        return frames(after: query["after"].flatMap(resumeSeq), limit: limit)
    }

    /// The frames after a resumable `seq`, or a snapshot.
    private func frames(after resumed: Int?, limit: Int) -> [LiveFrame] {
        if let resumed {
            return changes.filter { Self.seq(of: $0) > resumed }
        }
        let held = order.compactMap { messages[$0] }
        return [.snapshot(LiveSnapshot(
            cursor: cursor(seq), seq: seq, messages: Array(held.suffix(limit)),
            replies: replyOrder.compactMap { replies[$0] }.filter { $0.status != .delivered },
            state: state, moreBefore: held.count > limit
        ))]
    }

    private func refuse(_ request: URLRequest, _ route: Route) -> (status: Int, body: String)? {
        if let bearer, request.value(forHTTPHeaderField: "Authorization") != "Bearer \(bearer)" {
            return (401, Self.refusal("unauthorized"))
        }
        if route.query["v"] != "1" {
            return (400, Self.refusal("unsupported_version"))
        }
        if route.query["after"] != nil, route.query["before"] != nil {
            return (400, Self.refusal("bad_request"))
        }
        return nil
    }

    // MARK: - Plumbing

    private struct Route {
        var path: String
        var query: [String: String]
    }

    private func route(_ request: URLRequest) throws -> Route {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        requests.append("\(request.httpMethod ?? "GET") \(url.path())\(url.query().map { "?\($0)" } ?? "")")
        if down {
            throw URLError(.notConnectedToInternet)
        }
        let path = url.path()
        let path0 = path.range(of: "/live").map { String(path[$0.lowerBound...].dropFirst()) } ?? path
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Route(path: path0, query: Dictionary(items.map { ($0.name, $0.value ?? "") }) { _, last in last })
    }

    private func next() -> Int {
        seq += 1
        return seq
    }

    private func cursor(_ seq: Int) -> String { "c:\(seq)" }

    private func resumeSeq(_ cursor: String) -> Int? {
        guard cursor.hasPrefix("c:"), let seq = Int(cursor.dropFirst(2)), seq <= self.seq,
              seq >= forgottenBefore - 1 || forgottenBefore == 0 else {
            return nil
        }
        return seq
    }

    private func publish(_ frame: LiveFrame) {
        changes.append(frame)
        let lines = Self.lines(frame)
        for stream in streams.values {
            stream.yield(contentsOf: lines)
        }
    }

    private static func seq(of frame: LiveFrame) -> Int {
        switch frame {
        case let .message(_, _, seq), let .reply(_, _, seq), let .state(_, _, seq): seq
        default: 0
        }
    }

    /// A frame's SSE text as a line stream hands it over: without the blank line.
    private static func lines(_ frame: LiveFrame) -> [String] {
        ((try? frame.sse()) ?? "").split(separator: "\n").map(String.init)
    }

    private static func body(_ text: String) -> LineStream.Lines {
        AsyncThrowingStream { continuation in
            continuation.yield(text)
            continuation.finish()
        }
    }

    private static func refusal(_ error: String) -> String {
        #"{"error":"\#(error)","message":"\#(error)"}"#
    }

    private func refusal(_ request: URLRequest, _ status: Int, _ error: String) -> (Data, HTTPURLResponse) {
        (Data(Self.refusal(error).utf8), response(request, status))
    }

    private func json(_ request: URLRequest, _ status: Int, _ value: some Encodable) throws -> (Data, HTTPURLResponse) {
        (try JSONEncoder().encode(value), response(request, status))
    }

    private func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url ?? URL(filePath: "/"), statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: [:]) ?? HTTPURLResponse()
    }

    private struct ReadAnswer: Encodable {
        let v = 1
        let frames: [LiveFrame]
    }
}

private extension AsyncThrowingStream.Continuation where Element == String {
    func yield(contentsOf lines: [String]) {
        for line in lines {
            yield(line)
        }
    }
}
