import Foundation

/// One chat as the live protocol builds it: what the views show, and the one cursor it resumes from. A value: frames
/// from the stream and from reads go through `take`, in whatever order they arrive, and the rules of
/// docs/live-protocol.md ("The client's rules", "Display order") keep it right.
public struct LiveChat: Equatable, Sendable {
    /// In display order: by `at`, not by arrival.
    public private(set) var messages: [LiveMessage] = []
    /// In the order first taken. A `removed` one stays, so its status is known; views leave it out.
    public private(set) var replies: [LiveReply] = []
    public private(set) var state: LiveState?
    /// What the next stream or read resumes from. `nil`: nothing taken yet, so the server starts with a snapshot.
    public private(set) var cursor: String?
    public private(set) var seq = 0
    /// Older messages exist: a read with `before` fetches them.
    public private(set) var moreBefore = false
    /// Where each message sorts: its `at`, or the `at` of the message before it when it was first taken.
    private var sortDates: [String: Date] = [:]

    public init() {}

    /// A chat as kept from before: what a host stored with its cursor, shown at once and resumed from.
    public init(
        cursor: String?, seq: Int, messages: [LiveMessage], replies: [LiveReply] = [], state: LiveState? = nil,
        moreBefore: Bool = false
    ) {
        reset(to: LiveSnapshot(
            cursor: cursor ?? "", seq: seq, messages: messages, replies: replies, state: state, moreBefore: moreBefore
        ))
        self.cursor = cursor
    }

    public mutating func take(_ frame: LiveFrame) {
        switch frame {
        case let .snapshot(snapshot):
            reset(to: snapshot)
        case let .message(message, cursor, seq):
            take(message)
            advance(cursor, seq)
        case let .reply(reply, cursor, seq):
            take(reply)
            advance(cursor, seq)
        case let .state(state, cursor, seq):
            if state.seq > (self.state?.seq ?? Int.min) {
                self.state = state
            }
            advance(cursor, seq)
        case let .earlier(messages, moreBefore):
            prepend(messages)
            self.moreBefore = moreBefore
        case .hello, .ping, .close, .unknown:
            break
        }
    }

    /// A reply, from a frame or a write's answer: kept only if newer than the one held.
    public mutating func take(_ reply: LiveReply) {
        if let index = replies.firstIndex(where: { $0.id == reply.id }) {
            if reply.seq > replies[index].seq {
                replies[index] = reply
            }
        } else {
            replies.append(reply)
        }
    }

    public func reply(_ id: String) -> LiveReply? {
        replies.first { $0.id == id }
    }

    /// The reply a message of the person's is.
    public func reply(for message: LiveMessage) -> LiveReply? {
        message.replyID.flatMap(reply) ?? replies.first { $0.messageID == message.id }
    }

    /// Replies not yet in the chat as a message, and not taken back: the host draws them after the messages.
    public var outstanding: [LiveReply] {
        replies.filter { reply in
            reply.status != .removed && reply.messageID.map { id in !messages.contains { $0.id == id } } ?? true
                && !messages.contains { $0.replyID == reply.id }
        }
    }

    // MARK: - Rules

    private mutating func advance(_ cursor: String, _ seq: Int) {
        if seq > self.seq || self.cursor == nil {
            self.cursor = cursor
            self.seq = seq
        }
    }

    private mutating func take(_ message: LiveMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            if message.seq > messages[index].seq {
                messages[index] = message
            }
            return
        }
        let date = message.date ?? messages.last.flatMap { sortDates[$0.id] } ?? .distantPast
        sortDates[message.id] = date
        // After every message that sorts at or before it: equal `at` keeps the order taken.
        var index = messages.endIndex
        while index > messages.startIndex, (sortDates[messages[index - 1].id] ?? .distantPast) > date {
            index -= 1
        }
        messages.insert(message, at: index)
    }

    private mutating func reset(to snapshot: LiveSnapshot) {
        messages = []
        sortDates = [:]
        for message in snapshot.messages where !messages.contains(where: { $0.id == message.id }) {
            sortDates[message.id] = message.date ?? messages.last.flatMap { sortDates[$0.id] } ?? .distantPast
            messages.append(message)
        }
        replies = []
        snapshot.replies.forEach { take($0) }
        state = snapshot.state
        cursor = snapshot.cursor
        seq = snapshot.seq
        moreBefore = snapshot.moreBefore
    }

    private mutating func prepend(_ earlier: [LiveMessage]) {
        var front: [LiveMessage] = []
        for message in earlier where !messages.contains(where: { $0.id == message.id })
            && !front.contains(where: { $0.id == message.id }) {
            sortDates[message.id] = message.date ?? front.last.flatMap { sortDates[$0.id] } ?? .distantPast
            front.append(message)
        }
        messages.insert(contentsOf: front, at: 0)
    }
}

/// Turns a stream's lines into frames. A frame's `data` is one line of JSON (the protocol says so), so each `data:`
/// line is a whole frame: the blank line between events is not needed, which matters because a line stream drops it.
public struct LiveEventParser: Sendable {
    public init() {}

    /// The frame a line completes, if any. Comments, `event:`, `id:` and blank lines complete none.
    public func frame(from line: String) -> LiveFrame? {
        guard line.hasPrefix("data:") else {
            return nil
        }
        var payload = line.dropFirst(5)
        if payload.first == " " {
            payload = payload.dropFirst()
        }
        return try? LiveFrame.decode(Data(payload.utf8))
    }
}
