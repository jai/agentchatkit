import AgentChatLive
import DurableNetworking
import Foundation

/// One session on the server package's real ACP host on localhost (`server/dev/host.ts`): the transport a
/// `LiveChatModel` follows it over, and the host's test knobs. Nothing of the host is re-implemented here: the knobs
/// are HTTP calls to it, and the only fault made on this side is the network's (`setDown`).
///
/// On the Mac, `LiveDevHost()` starts the host once per process with `node` (or uses `AGENTCHAT_DEV_HOST`, a host
/// already running). Elsewhere, as in the iPhone demo, pass the host's address.
public actor LiveDevHost: HTTPTransport, StreamingTransport {
    public nonisolated let base: URL
    public nonisolated let session: String
    public nonisolated var acp: URL { base.appending(path: "acp") }

    private let http = URLSessionTransport(policy: .quick)
    private let streams = URLSessionStreamingTransport(quietLimit: 40)
    private var down = false
    private var openStreams: [UUID: AsyncThrowingStream<String, any Error>.Continuation] = [:]
    /// What the client sent, as `POST <rpc method>` (`POST response` for an answer) or `GET stream`.
    public private(set) var requests: [String] = []

    public init(base: URL, session: String = "s-\(UUID().uuidString.prefix(8))") {
        self.base = base
        self.session = session
    }

    #if os(macOS)
    /// A new session on this process's local host.
    public init(session: String = "s-\(UUID().uuidString.prefix(8))") {
        self.init(base: LocalHost.base, session: session)
    }
    #endif

    // MARK: - Knobs (docs in server/dev/host.ts)

    public func publish(_ update: JSONValue) async { await knob("publish", ["update": update]) }

    public func agentSays(_ id: String, _ text: String, at: Date = .now) async {
        await publish(["sessionUpdate": "agent_message", "messageId": .string(id),
                       "content": [["type": "text", "text": .string(text)]],
                       "_meta": ["agentchatkit": ["at": .string(LiveDates.string(at))]]])
    }

    public func tool(_ id: String, _ title: String, name: String, at: Date = .now) async {
        await publish(["sessionUpdate": "tool_call_update", "toolCallId": .string(id), "title": .string(title),
                       "name": .string(name), "kind": "execute", "status": "completed",
                       "_meta": ["agentchatkit": ["at": .string(LiveDates.string(at))]]])
    }

    public func setStatus(_ message: String, _ status: LiveMessage.Status) async {
        await knob("status", ["messageId": .string(message), "status": .string(status.rawValue)])
    }

    public func setState(_ phase: LiveState.Phase, activity: String? = nil, problem: String? = nil) async {
        await knob("state", ["state": .string(phase.rawValue), "activity": JSONValue(activity),
                             "problem": JSONValue(problem)])
    }

    public func ask(_ message: String, options: [LiveQuestion.Option], multiple: Bool = false, freeText: Bool = true)
        async {
        await knob("ask", ["message": .string(message), "multiple": .bool(multiple), "freeText": .bool(freeText),
                           "options": .array(options.map { ["id": .string($0.id), "label": .string($0.label)] })])
    }

    /// Every cursor handed out so far can no longer be resumed.
    public func forgetHistory() async { await knob("expire") }
    /// The host forgets this session's connections, as a restart does: their next request gets `404`.
    public func forgetConnections() async { await knob("forget") }
    /// The host ends this session's open streams.
    public func dropStreams() async { await knob("drop") }
    /// The session's next request after `initialize` is refused with this HTTP status, untouched.
    public func refuseNextRequest(_ status: Int) async { await knob("refuse", ["status": .number(Double(status))]) }
    /// Only this bearer is let in from now; `nil` lets any in.
    public func accept(bearer: String?) async { await knob("accept", ["bearer": JSONValue(bearer)]) }

    /// The network goes: open streams drop and every request fails as with no connection, until `false`.
    public func setDown(_ down: Bool) {
        self.down = down
        guard down else {
            return
        }
        for stream in openStreams.values {
            stream.finish(throwing: URLError(.networkConnectionLost))
        }
        openStreams = [:]
    }

    private func knob(_ name: String, _ body: JSONValue = [:]) async {
        var request = URLRequest(url: base.appending(path: "control/\(session)/\(name)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? body.data()
        _ = try? await http.send(request)
    }

    // MARK: - The client's transport

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let message = request.httpBody.flatMap { try? JSONValue.decode($0) }
        requests.append("POST \(message?["method"]?.string ?? "response")")
        if down {
            throw URLError(.notConnectedToInternet)
        }
        return try await http.send(request)
    }

    public func open(_ request: URLRequest) async throws -> LineStream {
        requests.append("GET stream")
        if down {
            throw URLError(.notConnectedToInternet)
        }
        let stream = try await streams.open(request)
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let id = UUID()
        openStreams[id] = continuation
        let pump = Task {
            do {
                for try await line in stream.lines {
                    continuation.yield(line)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { [weak self] _ in
            pump.cancel()
            Task { await self?.closed(id) }
        }
        return LineStream(response: stream.response, lines: lines)
    }

    private func closed(_ id: UUID) {
        openStreams[id] = nil
    }
}

#if os(macOS)
/// The local host this process started, once: `node server/dev/host.ts --port 0`, ended when the process ends.
enum LocalHost {
    static let base: URL = {
        if let given = ProcessInfo.processInfo.environment["AGENTCHAT_DEV_HOST"], let url = URL(string: given) {
            return url
        }
        // Started on a thread of its own with a full stack, whichever thread first asks: a test's cooperative thread
        // has a small one, and a filtered run on GitHub's macOS 26 runner died with SIGBUS here.
        nonisolated(unsafe) var started: URL?
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            started = start()
            done.signal()
        }
        thread.stackSize = 8 << 20
        thread.start()
        done.wait()
        return started!
    }()

    private static func start() -> URL {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let node = Process()
        node.executableURL = URL(filePath: "/usr/bin/env")
        node.arguments = ["node", root.appending(path: "server/dev/host.ts").path(), "--port", "0", "--exit-with-stdin"]
        let output = Pipe()
        node.standardOutput = output
        node.standardInput = stdin
        do {
            try node.run()
        } catch {
            fatalError("LiveDevHost needs node 24 on PATH to start server/dev/host.ts: \(error)")
        }
        var seen = ""
        while !seen.contains("\n") {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                fatalError("server/dev/host.ts ended before it was ready: \(seen)")
            }
            seen += String(decoding: chunk, as: UTF8.self)
        }
        guard let port = seen.split(separator: "\n").first?.split(separator: " ").last.flatMap({ Int($0) }) else {
            fatalError("server/dev/host.ts said \(seen)")
        }
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    /// Held open while this process runs: the host exits when it closes.
    nonisolated(unsafe) static let stdin = Pipe()
}
#endif
