import AgentChatKit
import DurableNetworking
import Foundation
import Observation

/// Where a chat lives, and the host's bearer for it. The live routes are under `chat`: `chat/live`, `chat/live/read`.
public struct LiveEndpoint: Sendable {
    public var chat: URL
    /// The bearer. `renew` true: the last one was refused; get a new one.
    public var bearer: @Sendable (_ renew: Bool) async throws -> String

    public init(chat: URL, bearer: @escaping @Sendable (_ renew: Bool) async throws -> String) {
        self.chat = chat
        self.bearer = bearer
    }
}

/// A refused write.
public struct LiveWriteError: Error, Equatable, Sendable {
    public var status: Int
    public var error: String
    public var message: String
}

/// Follows one chat live (docs/live-protocol.md): holds its stream while `follow()` runs, reconnects with back-off,
/// reads every 2 s while the stream is down, and takes every frame once into `chat`. AgentChatKit's views read
/// `chatMessages`, `chat.state` and `phase`. The host runs `follow()` while the chat is on screen and the app is in
/// front, and keeps `chat` (its cursor with it) where it likes, to open on it next time.
@MainActor
@Observable
public final class LiveChatModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case connecting
        /// The stream is open.
        case live
        /// The stream is down; reads every 2 s keep the chat fresh until it is back.
        case reading
        case stopped(LiveStop)
    }

    public private(set) var chat: LiveChat
    public private(set) var phase: Phase = .idle
    /// Streams opened since `follow()` began: the demo and the tests count reconnects with it.
    public private(set) var streamsOpened = 0

    @ObservationIgnored private let endpoint: LiveEndpoint
    @ObservationIgnored private let http: any HTTPTransport
    @ObservationIgnored private let streams: any StreamingTransport
    @ObservationIgnored private let timing: LiveTiming
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let random: @Sendable () -> Double
    @ObservationIgnored private let parser = LiveEventParser()
    @ObservationIgnored private var bearer: String?

    public init(
        endpoint: LiveEndpoint, http: any HTTPTransport, streams: any StreamingTransport, kept: LiveChat = LiveChat(),
        timing: LiveTiming = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.endpoint = endpoint
        self.http = http
        self.streams = streams
        chat = kept
        self.timing = timing
        self.sleep = sleep
        self.random = random
    }

    // MARK: - Following

    /// Follows the chat until the calling task is cancelled or the server says to stop.
    public func follow() async {
        if case .stopped = phase {
            phase = .idle
        }
        var attempt = 0
        var reauthed = false
        while !Task.isCancelled {
            let opened = ContinuousClock.now
            let streamsBefore = streamsOpened
            let action = await streamOnce()
            if ContinuousClock.now - opened >= timing.backoffResetsAfter {
                attempt = 0
            }
            if streamsOpened > streamsBefore {
                reauthed = false
            }
            if Task.isCancelled {
                break
            }
            switch action {
            case let .stop(reason):
                phase = .stopped(reason)
                return
            case .reauth:
                if reauthed {
                    phase = .stopped(.unauthorized)
                    return
                }
                reauthed = true
                bearer = try? await endpoint.bearer(true)
                continue
            case .now:
                break
            case let .after(wait):
                phase = .connecting
                try? await sleep(wait)
            case let .read(after: wait):
                await readWhileDown(for: wait)
            case .backoff:
                let base = timing.backoff(attempt: attempt)
                attempt += 1
                await readWhileDown(for: base * (1 + timing.jitter * (random() * 2 - 1)))
            }
        }
        if case .stopped = phase {} else {
            phase = .idle
        }
    }

    /// One stream, from open to end: what to do next.
    private func streamOnce() async -> LiveAction {
        phase = .connecting
        do {
            let stream = try await streams.open(request(path: "live", query: query(after: chat.cursor)))
            guard stream.status == 200 else {
                var body = ""
                for try await line in stream.lines {
                    body += line
                }
                return LiveAction.forStatus(
                    stream.status, error: Self.errorCode(Data(body.utf8)),
                    retryAfterSeconds: stream.response.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
                )
            }
            streamsOpened += 1
            phase = .live
            for try await line in stream.lines {
                guard let frame = parser.frame(from: line) else {
                    continue
                }
                if case let .close(close) = frame {
                    return LiveAction.forClose(close)
                }
                chat.take(frame)
            }
            return .backoff
        } catch {
            return .backoff
        }
    }

    /// Reads every `readInterval` for `wait`, then returns to stream again.
    private func readWhileDown(for wait: Duration) async {
        phase = .reading
        var left = wait
        while !Task.isCancelled {
            if case .stop = await read() {
                return
            }
            if left <= .zero {
                return
            }
            let pause = min(left, timing.readInterval)
            do {
                try await sleep(pause)
            } catch {
                return
            }
            left -= pause
        }
    }

    private enum ReadOutcome { case read, failed, stop }

    /// One read after the held cursor. A `401` gets a new bearer and is tried once more.
    @discardableResult
    private func read(renewed: Bool = false) async -> ReadOutcome {
        do {
            let (data, response) = try await http.send(request(path: "live/read", query: query(after: chat.cursor)))
            switch response.statusCode {
            case 200:
                for frame in try JSONDecoder().decode(LiveReadAnswer.self, from: data).frames {
                    chat.take(frame)
                }
                return .read
            case 401 where !renewed:
                bearer = try? await endpoint.bearer(true)
                return await read(renewed: true)
            case 403, 404:
                return .stop
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Fetches the messages before the oldest held ("Load earlier").
    public func loadEarlier(limit: Int = 100) async throws {
        guard let first = chat.messages.first else {
            return
        }
        var items = query(after: nil)
        items.append(URLQueryItem(name: "before", value: first.id))
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        let data = try await write(request(path: "live/read", query: items), expect: [200])
        for frame in try JSONDecoder().decode(LiveReadAnswer.self, from: data).frames {
            chat.take(frame)
        }
    }

    // MARK: - Writes

    /// Sends a message. `force` nil: forced while the chat waits on the person, since a queued reply would wait for
    /// good. `clientRef` is the idempotency key: send again with the same one after a failure.
    @discardableResult
    public func send(
        _ text: String, images: [MessageImage] = [], force: Bool? = nil, clientRef: String = UUID().uuidString
    ) async throws -> LiveReply {
        let body = SendBody(
            text: text, clientRef: clientRef, force: force ?? (chat.state?.waiting != nil), images: images
        )
        return try await reply(request(path: "live/messages", method: "POST", body: body, key: clientRef))
    }

    /// Whether a send now would be forced: the chat waits on the person.
    public var sendsForced: Bool { chat.state?.waiting != nil }

    /// A queued reply goes now.
    @discardableResult
    public func force(_ reply: String) async throws -> LiveReply {
        try await self.reply(request(path: "live/replies/\(reply)/force", method: "POST"))
    }

    /// Takes back a reply not yet passed on.
    @discardableResult
    public func remove(_ reply: String) async throws -> LiveReply {
        try await self.reply(request(path: "live/replies/\(reply)", method: "DELETE"))
    }

    /// Answers the agent's open question.
    @discardableResult
    public func answer(
        _ question: String, options: [String], text: String? = nil, clientRef: String = UUID().uuidString
    ) async throws -> LiveReply {
        let body = AnswerBody(questionID: question, optionIDs: options, text: text, clientRef: clientRef)
        return try await reply(request(path: "live/answer", method: "POST", body: body, key: clientRef))
    }

    private func reply(_ request: URLRequest) async throws -> LiveReply {
        let data = try await write(request, expect: [200, 201])
        let reply = try JSONDecoder().decode(LiveReply.self, from: data)
        chat.take(reply)
        return reply
    }

    private func write(_ request: URLRequest, expect: Set<Int>, renewed: Bool = false) async throws -> Data {
        let (data, response) = try await http.send(request)
        if response.statusCode == 401, !renewed {
            bearer = try await endpoint.bearer(true)
            var again = request
            again.setValue("Bearer \(bearer ?? "")", forHTTPHeaderField: "Authorization")
            return try await write(again, expect: expect, renewed: true)
        }
        guard expect.contains(response.statusCode) else {
            let refusal = try? JSONDecoder().decode([String: String].self, from: data)
            throw LiveWriteError(
                status: response.statusCode, error: refusal?["error"] ?? "internal", message: refusal?["message"] ?? ""
            )
        }
        return data
    }

    // MARK: - Requests

    private func query(after cursor: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "v", value: "1")]
        if let cursor {
            items.append(URLQueryItem(name: "after", value: cursor))
        }
        return items
    }

    private func request(
        path: String, method: String = "GET", query: [URLQueryItem]? = nil, body: (any Encodable)? = nil,
        key: String? = nil
    ) async throws -> URLRequest {
        if bearer == nil {
            bearer = try await endpoint.bearer(false)
        }
        var url = endpoint.chat.appending(path: path)
        url.append(queryItems: query ?? self.query(after: nil))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearer ?? "")", forHTTPHeaderField: "Authorization")
        if path == "live" {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    private static func errorCode(_ data: Data) -> String? {
        (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
    }
}

struct SendBody: Encodable {
    let text: String
    let clientRef: String
    let force: Bool
    let images: [MessageImage]

    enum CodingKeys: String, CodingKey {
        case text, force, images
        case clientRef = "client_ref"
    }
}

struct AnswerBody: Encodable {
    let questionID: String
    let optionIDs: [String]
    let text: String?
    let clientRef: String

    enum CodingKeys: String, CodingKey {
        case text
        case questionID = "question_id"
        case optionIDs = "option_ids"
        case clientRef = "client_ref"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(questionID, forKey: .questionID)
        try container.encode(optionIDs, forKey: .optionIDs)
        try container.encode(text, forKey: .text) // `null`, not left out
        try container.encode(clientRef, forKey: .clientRef)
    }
}
