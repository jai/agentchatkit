import AgentChatKit
import Foundation
import Observation

/// One chat with the scripted agent, as a host holds a conversation: its messages, what the agent is doing, the reply
/// box's draft and screenshots, and the model it runs. A real host would fill these from its server; this one plays
/// `DemoScript` in-process.
@MainActor
@Observable
final class DemoChat: Identifiable {
    let id: String
    let title: String
    private(set) var messages: [ChatMessage]
    /// What the agent is doing, while it works: the footer's working line.
    private(set) var activity: String?
    /// A message of his on its way: no ticks yet, and the send button waits.
    private(set) var isSending = false
    /// One more with each message he sends: the chat goes to the end with it.
    private(set) var sentCount = 0
    /// The screenshots that went with each message of his, by its id: drawn under its bubble.
    private(set) var screenshots: [String: [Data]] = [:]
    private(set) var options = DemoChat.models

    var draft = ""
    let attachments = ComposerAttachments()

    private let pace: DemoPace
    private var lastReply: DemoReply?
    /// The agent answers one message at a time: a message sent while it works waits for the answer before it.
    private var work: Task<Void, Never>?

    init(id: String, title: String, messages: [ChatMessage], pace: DemoPace) {
        self.id = id
        self.title = title
        self.messages = messages
        self.pace = pace
    }

    /// The models the chip offers: Opus and Sonnet with reasoning levels, Haiku without.
    static let models = ModelReasoning(
        models: [
            .init(id: "opus", label: "Claude Opus 5.5", short: "Opus 5.5",
                  efforts: efforts(["low", "medium", "high", "max"])),
            .init(id: "sonnet", label: "Claude Sonnet 5.5", short: "Sonnet 5.5",
                  efforts: efforts(["low", "medium", "high"])),
            .init(id: "haiku", label: "Claude Haiku 5.5", short: "Haiku 5.5", efforts: []),
        ],
        model: "opus", effort: "high"
    )

    private static func efforts(_ ids: [String]) -> [ModelReasoning.Effort] {
        ids.map { .init(id: $0, label: $0.capitalized) }
    }

    var isWorking: Bool { activity != nil }

    /// Sends the draft and the tray's screenshots.
    func sendDraft() {
        let words = draft
        let pictures = attachments.take().map(\.jpeg)
        draft = ""
        send(words, screenshots: pictures)
    }

    /// Sends words of his, as the reply box or a quick reply does, and sets the agent answering.
    func send(_ words: String, screenshots pictures: [Data] = []) {
        let id = "me-\(sentCount)"
        let shown = ScreenshotLine.bubbleText(ChatQuickReply.shown(words), screenshots: pictures.count)
        messages.append(ChatMessage(id: id, role: .mine, text: shown, date: .now, hasExtras: !pictures.isEmpty))
        screenshots[id] = pictures.isEmpty ? nil : pictures
        sentCount += 1
        isSending = true
        let before = work
        work = Task {
            try? await pace.wait(pace.delivery)
            setTicks(.sent, on: id)
            isSending = false
            await before?.value
            setTicks(.delivered, on: id)
            await answer(words, screenshots: pictures.count)
        }
    }

    /// Asks the host to change the model or its reasoning; the chip shows the change once this returns.
    func pick(_ pick: ModelReasoning.Pick) async throws {
        try await pace.wait(pace.step)
        switch pick {
        case let .model(id):
            options.model = id
            let levels = options.efforts.map(\.id)
            if !levels.contains(options.effort ?? "") {
                options.effort = levels.contains("high") ? "high" : levels.last
            }
        case let .effort(id):
            options.effort = id
        }
    }

    private func setTicks(_ ticks: DeliveryTicks, on id: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].ticks = ticks
        }
    }

    private func answer(_ words: String, screenshots: Int) async {
        let reply: DemoReply
        if words == ChatQuickReply.waitWhat.text, let lastReply {
            let plain = lastReply.plain
            reply = DemoReply(steps: [.think("Saying that again, plainly"), .say(plain)], plain: plain)
        } else {
            reply = DemoScript.reply(to: words, screenshots: screenshots, model: options.current?.label ?? "Claude")
        }
        activity = "Thinking"
        for step in reply.steps {
            switch step {
            case let .think(doing):
                activity = doing
                try? await pace.wait(pace.step)
            case let .tool(name, summary, doing):
                activity = doing
                try? await pace.wait(pace.step)
                messages.append(ChatMessage(id: nextID("tool"), role: .tool(name: name), text: summary))
            case let .say(text):
                activity = "Writing"
                await stream(text)
            }
        }
        lastReply = reply
        activity = nil
    }

    /// Words arriving a few at a time, as an agent's do, into one bubble.
    private func stream(_ text: String) async {
        let id = nextID("them")
        messages.append(ChatMessage(id: id, role: .theirs, text: "", date: .now, footnote: options.chip))
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        for chunk in Self.chunks(of: text, size: pace.chunk) {
            try? await pace.wait(pace.word)
            messages[index].text += chunk
        }
    }

    /// The text in pieces of about `size` characters, each ending where a word does.
    nonisolated static func chunks(of text: String, size: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if current.count >= size, character.isWhitespace {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private var counter = 0

    private func nextID(_ kind: String) -> String {
        counter += 1
        return "\(kind)-\(counter)"
    }
}

/// How fast the agent goes: as a person would watch it, quickly for UI tests (`-DemoPace fast`), or slowly enough to
/// catch it at work in a screenshot (`-DemoPace slow`).
struct DemoPace: Sendable {
    var delivery: Duration
    var step: Duration
    var word: Duration
    var chunk: Int

    static let watched = DemoPace(
        delivery: .milliseconds(350), step: .milliseconds(900), word: .milliseconds(35), chunk: 10
    )
    static let fast = DemoPace(delivery: .milliseconds(60), step: .milliseconds(120), word: .milliseconds(4), chunk: 60)

    static let slow = DemoPace(delivery: .milliseconds(350), step: .seconds(3), word: .milliseconds(150), chunk: 10)

    static var current: DemoPace {
        switch UserDefaults.standard.string(forKey: "DemoPace") {
        case "fast": .fast
        case "slow": .slow
        default: .watched
        }
    }

    func wait(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
