import AgentChatKit
import AgentChatLive
import AgentChatLiveTesting
import Foundation
import Observation

/// The Live chat: the scripted agent behind an ACP host (our profile, docs/live-protocol.md), followed with
/// AgentChatLive as an app follows its host's. The host is `LiveLoopbackServer`, in memory: the toolbar drops its
/// stream or takes its network away, so the chat can be watched reconnecting and catching up.
@MainActor
@Observable
final class DemoLiveChat {
    let server = LiveLoopbackServer(session: "live")
    let model: LiveChatModel
    var draft = ""
    /// The network, as the toolbar switches it.
    private(set) var isOnline = true
    /// One more with each message he sends: the chat goes to the end with it.
    private(set) var sentCount = 0
    private(set) var isSending = false
    private let agent: DemoLiveAgent

    init(pace: DemoPace) {
        model = LiveChatModel(
            endpoint: LiveEndpoint(acp: URL(string: "https://demo.invalid/acp")!, session: "live",
                                   bearer: { _ in "demo" }),
            http: server, streams: server
        )
        agent = DemoLiveAgent(server: server, pace: pace)
        let agent = agent
        let server = server
        Task {
            await server.agentSays("greeting", DemoScript.liveGreeting)
            await server.onPrompt { message, text, _ in
                Task { await agent.answer(message, text) }
            }
            await server.onAnswer { _, _ in
                Task { await agent.afterAnswer() }
            }
        }
    }

    /// Where the stream stands, in words, for the header.
    var status: String {
        switch model.phase {
        case .idle, .connecting: "Connecting…"
        case .live: "Live · stream \(model.streamsOpened)"
        case .reconnecting: isOnline ? "Reconnecting…" : "Offline… reconnecting"
        case let .stopped(reason): "Stopped: \(reason)"
        }
    }

    func sendDraft() {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            return
        }
        draft = ""
        sentCount += 1
        isSending = true
        Task {
            defer { isSending = false }
            try? await model.send(words)
        }
    }

    func answer(_ option: LiveQuestion.Option) {
        guard let question = model.chat.question else {
            return
        }
        sentCount += 1
        Task { try? await model.answer(question, options: [option.id]) }
    }

    /// Ends the stream as a dropped connection does: the chat reconnects and resumes from its cursor.
    func dropStream() {
        Task { await server.dropStreams() }
    }

    func setOnline(_ online: Bool) {
        isOnline = online
        Task { await server.setDown(!online) }
    }
}

/// The scripted agent on the host's side: it takes each message, says it is working, calls its tools and writes its
/// answer a few words at a time (each a new version of one message), then goes idle. Asked to merge, it asks first.
actor DemoLiveAgent {
    private let server: LiveLoopbackServer
    private let pace: DemoPace
    private var counter = 0
    private var last: Task<Void, Never>?

    init(server: LiveLoopbackServer, pace: DemoPace) {
        self.server = server
        self.pace = pace
    }

    /// One message at a time: one sent while it works waits for the answer before it.
    func answer(_ message: String, _ text: String) {
        let before = last
        last = Task {
            await before?.value
            await run(message, text)
        }
    }

    func afterAnswer() {
        let before = last
        last = Task {
            await before?.value
            await server.setState(.running, activity: "Merging")
            try? await pace.wait(pace.step)
            await write("Merged, and tagged. CI is running on main.")
            await server.setState(.idle)
        }
    }

    private func run(_ message: String, _ text: String) async {
        await server.setStatus(message, .delivering)
        try? await pace.wait(pace.delivery)
        await server.setStatus(message, .delivered)
        if text.lowercased().contains("merge") {
            await server.setState(.running, activity: "Checking CI")
            try? await pace.wait(pace.step)
            await server.ask("CI is green. Merge now, or wait for review?", options: [
                .init(id: "merge", label: "Merge now"), .init(id: "wait", label: "Wait for review"),
            ])
            return
        }
        let script = DemoScript.reply(to: text, screenshots: 0, model: "Claude Opus 5.5")
        await server.setState(.running, activity: "Thinking")
        for step in script.steps {
            switch step {
            case let .think(doing):
                await server.setState(.running, activity: doing)
                try? await pace.wait(pace.step)
            case let .tool(name, summary, doing):
                await server.setState(.running, activity: doing)
                try? await pace.wait(pace.step)
                await server.tool(next("tool"), summary, name: name)
            case let .say(words):
                await server.setState(.running, activity: "Writing")
                await write(words)
            }
        }
        await server.setState(.idle)
    }

    private func write(_ text: String) async {
        let id = next("them")
        let at = Date.now
        var written = ""
        for chunk in DemoChat.chunks(of: text, size: pace.chunk * 4) {
            try? await pace.wait(pace.word * 4)
            written += chunk
            await server.agentSays(id, written, at: at)
        }
        await server.agentSays(id, text, at: at)
    }

    private func next(_ kind: String) -> String {
        counter += 1
        return "\(kind)-\(counter)"
    }
}
