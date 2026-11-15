import AgentChatKit
import AgentChatLive
import AgentChatLiveTesting
import Foundation
import Observation

/// The Live chat: the server package's real ACP host on this Mac (`node server/dev/host.ts`, session "live", whose
/// scripted agent answers, writes as it goes and asks before it merges), followed with AgentChatLive as an app follows
/// its host's. The toolbar drops the stream, restarts the host's connections or takes the network away, so the chat
/// can be watched reconnecting and catching up.
@MainActor
@Observable
final class DemoLiveChat {
    /// The host's address: `-DemoServer`, else the dev host's default port.
    static var hostBase: URL {
        let given = UserDefaults.standard.string(forKey: "DemoServer") ?? "http://127.0.0.1:8788"
        let url = URL(string: given) ?? URL(string: "http://127.0.0.1:8788")!
        return url.lastPathComponent == "acp" ? url.deletingLastPathComponent() : url
    }

    /// `-DemoSession`, else "live": the dev host scripts every session named "live…" (UI tests take a fresh one).
    let host = LiveDevHost(base: DemoLiveChat.hostBase,
                           session: UserDefaults.standard.string(forKey: "DemoSession") ?? "live")
    let model: LiveChatModel
    var draft = ""
    /// The network, as the toolbar switches it.
    private(set) var isOnline = true
    /// One more with each message he sends: the chat goes to the end with it.
    private(set) var sentCount = 0
    private(set) var isSending = false

    init() {
        model = LiveChatModel(
            endpoint: LiveEndpoint(acp: host.acp, session: host.session, bearer: { _ in "token-jai" }),
            http: host, streams: host
        )
    }

    /// Where the stream stands, in words, for the header.
    var status: String {
        switch model.phase {
        case .idle, .connecting: "Connecting…"
        case .live:
            "Live · stream \(model.streamsOpened)"
                + (model.timings.last.map { " · \($0.total.formatted(.units(allowed: [.milliseconds])))" } ?? "")
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

    /// The host ends the stream, as a dropped connection does: the chat reconnects and resumes from its cursor.
    func dropStream() {
        Task { await host.dropStreams() }
    }

    /// The host forgets the chat's connection, as a restart does: the chat initializes again.
    func restartHost() {
        Task { await host.forgetConnections() }
    }

    /// The network goes or comes back, on this side.
    func setOnline(_ online: Bool) {
        isOnline = online
        Task { await host.setDown(!online) }
    }
}
