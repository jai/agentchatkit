import AgentChatCore
import DurableNetworking
import Foundation
import Observation

/// Where a chat lives: the host's ACP endpoint, the chat's session id, and the host's bearer.
public struct LiveEndpoint: Sendable {
    /// `<base>/acp`.
    public var acp: URL
    public var session: String
    /// The bearer. `renew` true: the last one was refused; get a new one.
    public var bearer: @Sendable (_ renew: Bool) async throws -> String

    public init(acp: URL, session: String, bearer: @escaping @Sendable (_ renew: Bool) async throws -> String) {
        self.acp = acp
        self.session = session
        self.bearer = bearer
    }
}

/// Why a chat stopped following.
public enum LiveStop: Equatable, Sendable {
    case unauthorized, forbidden, notFound
}

/// A request the host refused, or whose answer never came.
public enum LiveRequestError: Error, Equatable, Sendable {
    /// A JSON-RPC error: `AcpError.conflict` for an edit of a message already on its way.
    case refused(code: Int, message: String)
    case http(Int)
    /// The stream the answer would have come on is down, or the answer took too long. A send with the same
    /// `clientRef` is safe to repeat.
    case noAnswer
}

/// How long one (re)connect took, step by step: the profile's reconnect costs four requests where plain SSE costs one,
/// so hosts report these from real phones (docs/live-protocol.md, "To measure").
public struct LiveConnectTiming: Equatable, Sendable {
    /// `initialize`; `nil` when the connection id was still good.
    public var initialize: Duration?
    public var stream: Duration
    /// `session/resume` until its answer, replay included.
    public var resume: Duration
    public var fromStart: Bool

    public var total: Duration { (initialize ?? .zero) + stream + resume }
}

/// The protocol's timings. `standard` is the profile's; tests shorten them.
public struct LiveTiming: Sendable {
    public var backoff: [Duration]
    public var jitter: Double
    /// A stream open this long starts the back-off again from the first step.
    public var backoffResetsAfter: Duration
    /// How long a request waits for its answer on the stream.
    public var answerLimit: Duration

    public init(backoff: [Duration], jitter: Double, backoffResetsAfter: Duration, answerLimit: Duration) {
        self.backoff = backoff
        self.jitter = jitter
        self.backoffResetsAfter = backoffResetsAfter
        self.answerLimit = answerLimit
    }

    public static let standard = LiveTiming(
        backoff: [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)], jitter: 0.2,
        backoffResetsAfter: .seconds(10), answerLimit: .seconds(20)
    )

    public func backoff(attempt: Int) -> Duration {
        backoff[min(attempt, backoff.count - 1)]
    }
}

/// Follows one chat over the profile (docs/live-protocol.md): initializes, holds the session stream, resumes from its
/// cursor (or from start, replacing what it held), reconnects with back-off, and sends the person's writes as
/// JSON-RPC requests whose answers come on the stream. AgentChatKit's views read `chatMessages`, `chat` and `phase`.
/// The host runs `follow()` while the chat is on screen and the app is in front, and keeps `chat` to open on next time.
@MainActor
@Observable
public final class LiveChatModel {
    public enum Phase: Equatable, Sendable {
        case idle, connecting, live, reconnecting
        case stopped(LiveStop)
    }

    public private(set) var chat: LiveChat
    public private(set) var phase: Phase = .idle
    /// Session streams opened since this model was made.
    public private(set) var streamsOpened = 0
    /// The newest (re)connects, newest last, at most 20.
    public private(set) var timings: [LiveConnectTiming] = []
    /// Told of each (re)connect's timing, for the host to log or report.
    @ObservationIgnored public var onTiming: (@MainActor (LiveConnectTiming) -> Void)?

    @ObservationIgnored let endpoint: LiveEndpoint
    @ObservationIgnored let http: any HTTPTransport
    @ObservationIgnored private let streams: any StreamingTransport
    @ObservationIgnored private let timing: LiveTiming
    @ObservationIgnored private let random: @Sendable () -> Double
    @ObservationIgnored private let parser = LiveEventParser()
    @ObservationIgnored private var bearer: String?
    @ObservationIgnored private var connection: String?
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var waiting: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    /// While a resume from start replays: the chat it builds, which replaces `chat` once the resume answers.
    @ObservationIgnored private var replacing: (id: Int, chat: LiveChat)?

    public init(
        endpoint: LiveEndpoint, http: any HTTPTransport, streams: any StreamingTransport, kept: LiveChat = LiveChat(),
        timing: LiveTiming = .standard,
        // Not used: the model pauses with `Task.sleep(for:)` called directly. Awaiting a stored pause closure from a
        // main-actor task crashed the macOS 26.5 runtime's task allocator (SIGBUS, jai/agentchatkit#3). Kept so hosts
        // still build.
        sleep: @escaping @Sendable (Duration) async throws -> Void = Outbox.pause,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.endpoint = endpoint
        self.http = http
        self.streams = streams
        chat = kept
        self.timing = timing
        self.random = random
    }

    // MARK: - Following

    private enum Outcome {
        case stop(LiveStop)
        case reauth
        case reinitialize
        case dropped(after: Duration)
    }

    /// Follows the chat until the calling task is cancelled or the host says to stop.
    public func follow() async {
        phase = .connecting
        var attempt = 0
        var reauthed = false
        var reinitialized = false
        while !Task.isCancelled {
            let outcome = await connectOnce()
            if Task.isCancelled {
                break
            }
            switch outcome {
            case let .stop(reason):
                phase = .stopped(reason)
                failWaiting()
                return
            case .reauth:
                guard !reauthed else {
                    phase = .stopped(.unauthorized)
                    return
                }
                reauthed = true
                bearer = try? await endpoint.bearer(true)
            case .reinitialize:
                guard !reinitialized else {
                    phase = .stopped(.notFound)
                    return
                }
                reinitialized = true
                connection = nil
            case let .dropped(open):
                if open > .zero {
                    reauthed = false
                    reinitialized = false
                }
                if open >= timing.backoffResetsAfter {
                    attempt = 0
                }
                phase = .reconnecting
                let base = timing.backoff(attempt: attempt)
                attempt += 1
                try? await Task.sleep(for: base * (1 + timing.jitter * (random() * 2 - 1)))
            }
        }
        failWaiting()
        if case .stopped = phase {} else {
            phase = .idle
        }
    }

    private func connectOnce() async -> Outcome {
        let clock = ContinuousClock()
        var initialized: Duration?
        do {
            if connection == nil {
                let started = clock.now
                let (_, response) = try await post(Acp.initialize(take(), client: "AgentChatLive", version: "1"))
                switch response.statusCode {
                case 200: break
                case 401: return .reauth
                case 403: return .stop(.forbidden)
                case 404: return .stop(.notFound)
                default: return .dropped(after: .zero)
                }
                guard let id = response.value(forHTTPHeaderField: "Acp-Connection-Id") else {
                    return .dropped(after: .zero)
                }
                connection = id
                initialized = clock.now - started
            }
            let opening = clock.now
            let stream = try await streams.open(request(method: "GET", accept: "text/event-stream"))
            switch stream.status {
            case 200: break
            case 401: return .reauth
            case 403: return .stop(.forbidden)
            case 404: return .reinitialize
            default: return .dropped(after: .zero)
            }
            let opened = clock.now
            streamsOpened += 1
            // The lines reach this task through a stream of the model's own: a pump copies them from the connection,
            // and a resume that gets no answer ends it. Reading inline means cancelling `follow()` ends the reading.
            // (No `withTaskCancellationHandler` around an awaited reader: on the macOS 26 runtime that pattern
            // aborted the test process with "freed pointer was not the last allocation".)
            let (lines, feed) = AsyncStream<String>.makeStream()
            let pump = Task {
                do {
                    for try await line in stream.lines {
                        feed.yield(line)
                    }
                } catch {}
                feed.finish()
            }
            defer { pump.cancel() }
            let since = opened - opening
            let resumer = Task { @MainActor [weak self] () -> Bool in
                guard let self else {
                    return false
                }
                let resumed = await self.resume(clock: clock, initialized: initialized, stream: since)
                if !resumed {
                    feed.finish() // No answer to the resume: this stream will never carry the chat. Start again.
                }
                return resumed
            }
            for await line in lines {
                if let message = parser.message(from: line) {
                    receive(message)
                }
            }
            failWaiting()
            let resumed = await resumer.value
            return .dropped(after: resumed ? clock.now - opened : .zero)
        } catch {
            failWaiting()
            return .dropped(after: .zero)
        }
    }

    /// `session/resume` from the held cursor; from start when there is none or the host can't resume from it. False
    /// when it got no answer.
    private func resume(clock: ContinuousClock, initialized: Duration?, stream: Duration) async -> Bool {
        let started = clock.now
        var fromStart = chat.cursor == nil
        do {
            _ = try await resumeCall()
        } catch LiveRequestError.refused(AcpError.invalidParams, _) {
            fromStart = true
            guard (try? await resumeCall(fromStart: true)) != nil else {
                return false
            }
        } catch {
            return false
        }
        phase = .live
        let measured = LiveConnectTiming(
            initialize: initialized, stream: stream, resume: clock.now - started, fromStart: fromStart
        )
        timings = Array((timings + [measured]).suffix(20))
        onTiming?(measured)
        return true
    }

    private func resumeCall(fromStart: Bool = false) async throws -> JSONValue {
        let id = take()
        let cursor = fromStart ? nil : chat.cursor
        if cursor == nil {
            replacing = (id, LiveChat())
        }
        return try await send(Acp.resume(id, session: endpoint.session, cursor: cursor), id: id)
    }

    private func receive(_ message: JSONValue) {
        let incoming = AcpIncoming.parse(message)
        switch incoming {
        case let .result(id, result):
            if let replacing, replacing.id == id {
                chat = replacing.chat
                self.replacing = nil
            }
            waiting.removeValue(forKey: id)?.resume(returning: result)
        case let .error(id, code, text):
            if replacing?.id == id {
                replacing = nil
            }
            waiting.removeValue(forKey: id)?.resume(throwing: LiveRequestError.refused(code: code, message: text))
        default:
            if replacing != nil {
                replacing?.chat.take(incoming)
            } else {
                chat.take(incoming)
            }
        }
    }

    // MARK: - Writes

    /// Sends a message. Its `user_message` comes on the stream at once (`pending`, or `queued` behind the agent's
    /// turn); the answer is its id. `force`: go now instead of after the turn. Repeat with the same `clientRef` after a
    /// failure: the host answers the first message's id.
    @discardableResult
    public func send(
        _ text: String, images: [MessageImage] = [], force: Bool = false, clientRef: String = UUID().uuidString
    ) async throws -> String {
        let pictures = images.compactMap { Data(base64Encoded: $0.data) }
        let result = try await call("session/prompt", [
            "sessionId": .string(endpoint.session), "prompt": Acp.prompt(text, images: pictures),
            "_meta": ["agentchatkit": ["clientRef": .string(clientRef), "force": .bool(force)]],
        ])
        return result["messageId"]?.string ?? ""
    }

    /// Sends a queued message now: it goes to the agent instead of waiting for the turn to end.
    @discardableResult
    public func sendNow(_ message: String) async throws -> String {
        try await edit(message, force: true)
    }

    /// Sends a failed message again: it becomes `pending`, with the same id and `clientRef`.
    @discardableResult
    public func retry(_ message: String) async throws -> String {
        try await edit(message, force: true)
    }

    /// Changes a message still `pending`, `queued` or `failed`. `LiveRequestError.refused(AcpError.conflict)` once it is on its way.
    @discardableResult
    public func edit(_ message: String, text: String? = nil, force: Bool? = nil) async throws -> String {
        var params: [String: JSONValue] = ["sessionId": .string(endpoint.session), "messageId": .string(message)]
        if let text {
            params["prompt"] = Acp.prompt(text, images: [])
        }
        if let force {
            params["force"] = .bool(force)
        }
        return try await call("_agentchatkit/edit", .object(params))["messageId"]?.string ?? message
    }

    /// Takes back a message still `pending` or `queued`.
    @discardableResult
    public func remove(_ message: String) async throws -> String {
        try await call("_agentchatkit/remove", [
            "sessionId": .string(endpoint.session), "messageId": .string(message),
        ])["messageId"]?.string ?? message
    }

    /// Answers the agent's open question: the chosen options' ids, and words when it takes them. A refusal keeps the
    /// question open and throws.
    public func answer(_ question: LiveQuestion, options: [String], text: String? = nil) async throws {
        var content: [String: JSONValue] = [:]
        if question.multiple {
            content["choices"] = .array(options.map(JSONValue.string))
        } else if let first = options.first {
            content["choice"] = .string(first)
        }
        if let text, !text.isEmpty {
            content["text"] = .string(text)
        }
        let (_, response) = try await post(Acp.response(
            question.requestID, result: ["action": "accept", "content": .object(content)]
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw LiveRequestError.http(response.statusCode)
        }
        chat.answered(question.requestID)
    }

    /// Declines the agent's open question. A refusal keeps the question open and throws.
    public func decline(_ question: LiveQuestion) async throws {
        let (_, response) = try await post(Acp.response(question.requestID, result: ["action": "decline"]))
        guard (200..<300).contains(response.statusCode) else {
            throw LiveRequestError.http(response.statusCode)
        }
        chat.answered(question.requestID)
    }

    private func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        let id = take()
        return try await send(Acp.request(id, method, params), id: id)
    }

    /// `call`, for `LiveUpload.swift`'s writes.
    func callForUpload(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        try await call(method, params)
    }

    /// The bearer, asked for once.
    func currentBearer() async throws -> String {
        if bearer == nil {
            bearer = try await endpoint.bearer(false)
        }
        return bearer ?? ""
    }

    /// Posts a request and waits for its answer on the stream.
    private func send(_ message: JSONValue, id: Int) async throws -> JSONValue {
        guard connection != nil else {
            throw LiveRequestError.noAnswer
        }
        let limit = timing.answerLimit
        let timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: limit)
            self?.waiting.removeValue(forKey: id)?.resume(throwing: LiveRequestError.noAnswer)
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id] = continuation
            Task { @MainActor in
                do {
                    let (data, response) = try await post(message)
                    if response.statusCode == 200, let answer = try? JSONValue.decode(data), answer["id"] != nil {
                        receive(answer) // A host may answer in the POST itself.
                    } else if response.statusCode != 202, response.statusCode != 200 {
                        waiting.removeValue(forKey: id)?.resume(throwing: LiveRequestError.http(response.statusCode))
                    }
                } catch {
                    waiting.removeValue(forKey: id)?.resume(throwing: LiveRequestError.noAnswer)
                }
            }
        }
    }

    private func failWaiting() {
        let lost = waiting
        waiting = [:]
        replacing = nil
        for continuation in lost.values {
            continuation.resume(throwing: LiveRequestError.noAnswer)
        }
    }

    // MARK: - HTTP

    private func take() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func post(_ message: JSONValue, renewed: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var request = try await request(method: "POST", accept: "application/json, text/event-stream")
        request.httpBody = try message.data()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await http.send(request)
        if response.statusCode == 401, !renewed {
            bearer = try await endpoint.bearer(true)
            return try await post(message, renewed: true)
        }
        return (data, response)
    }

    private func request(method: String, accept: String) async throws -> URLRequest {
        if bearer == nil {
            bearer = try await endpoint.bearer(false)
        }
        var request = URLRequest(url: endpoint.acp)
        request.httpMethod = method
        request.setValue("Bearer \(bearer ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let connection {
            // Everything after `initialize` is the session's: the stream, and every request on it.
            request.setValue(connection, forHTTPHeaderField: "Acp-Connection-Id")
            request.setValue(endpoint.session, forHTTPHeaderField: "Acp-Session-Id")
        }
        return request
    }
}
