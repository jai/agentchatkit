import AgentChatKit
import AgentChatLive
import AgentChatLiveTesting
import Foundation
import Observation

/// The Live chat: the scripted agent behind a live chat server, followed with AgentChatLive as an app follows its
/// host's (docs/live-protocol.md). The server is `LiveLoopbackServer`, in memory: the toolbar drops its stream or takes
/// its network away, so the chat can be watched reconnecting and catching up.
@MainActor
@Observable
final class DemoLiveChat {
    let server = LiveLoopbackServer(chatID: "live")
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
            endpoint: LiveEndpoint(chat: URL(string: "https://demo.invalid/chats/live")!, bearer: { _ in "demo" }),
            http: server, streams: server
        )
        agent = DemoLiveAgent(server: server, pace: pace)
        let agent = agent
        let server = server
        Task {
            await server.put(LiveMessage(
                id: "greeting", seq: 0, role: .assistant, text: DemoScript.liveGreeting, at: LiveDates.string(.now)
            ))
            await server.onSent { reply in
                Task { await agent.answer(reply) }
            }
        }
    }

    /// Where the stream stands, in words, for the header.
    var status: String {
        switch model.phase {
        case .idle, .connecting: "Connecting…"
        case .live: "Live · stream \(model.streamsOpened)"
        case .reading: isOnline ? "Reconnecting… reading every 2 s" : "Offline… reading every 2 s"
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

    /// Ends the stream as a dropped connection does: the chat reads while it reconnects.
    func dropStream() {
        Task { await server.dropStreams() }
    }

    func setOnline(_ online: Bool) {
        isOnline = online
        Task { await server.setDown(!online) }
    }
}

/// The scripted agent on the server's side: it takes each reply, says it is working, calls its tools and writes its
/// answer a few words at a time, as partial versions of one message, then the final one.
actor DemoLiveAgent {
    private let server: LiveLoopbackServer
    private let pace: DemoPace
    private var counter = 0
    private var last: Task<Void, Never>?

    init(server: LiveLoopbackServer, pace: DemoPace) {
        self.server = server
        self.pace = pace
    }

    /// One reply at a time: one sent while it works waits for the answer before it.
    func answer(_ reply: LiveReply) {
        let before = last
        last = Task {
            await before?.value
            await run(reply)
        }
    }

    private func run(_ reply: LiveReply) async {
        try? await pace.wait(pace.delivery)
        let message = await server.put(LiveMessage(
            id: "you-\(reply.id)", seq: 0, role: .user, text: reply.text, at: reply.at, replyID: reply.id,
            sender: reply.sender
        ))
        var delivered = reply
        delivered.status = .delivered
        delivered.messageID = message.id
        await server.put(delivered)

        let script = DemoScript.reply(to: reply.text, screenshots: 0, model: "Claude Opus 5.5")
        await working("Thinking")
        for step in script.steps {
            switch step {
            case let .think(doing):
                await working(doing)
                try? await pace.wait(pace.step)
            case let .tool(name, summary, doing):
                await working(doing)
                try? await pace.wait(pace.step)
                await server.put(LiveMessage(
                    id: next("tool"), seq: 0, role: .tool, text: summary, at: LiveDates.string(.now), tool: name
                ))
            case let .say(text):
                await working("Writing")
                await write(text)
            }
        }
        await server.set(LiveState(seq: 0, working: false))
    }

    private func working(_ activity: String) async {
        await server.set(LiveState(seq: 0, working: true, activity: activity))
    }

    private func write(_ text: String) async {
        let id = next("them")
        let at = LiveDates.string(.now)
        var written = ""
        for chunk in DemoChat.chunks(of: text, size: pace.chunk * 4) {
            try? await pace.wait(pace.word * 4)
            written += chunk
            await server.put(LiveMessage(id: id, seq: 0, role: .assistant, text: written, at: at, partial: true))
        }
        await server.put(LiveMessage(id: id, seq: 0, role: .assistant, text: text, at: at))
    }

    private func next(_ kind: String) -> String {
        counter += 1
        return "\(kind)-\(counter)"
    }
}
