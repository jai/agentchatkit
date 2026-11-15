import Foundation
import Observation

/// Shared queue behavior. Hooks return the authoritative updated reply, or nil if it left the queue.
/// A successful Remove hook must mean that taking its words back is safe (including host-accepted removal).
@MainActor
@Observable
public final class ReplyQueueController<ID: Hashable & Sendable> {
    public typealias Reply = QueuedReply<ID>
    public typealias Action = @MainActor (Reply) async -> Result<Reply?, ChatActionError>

    public private(set) var replies: [Reply]
    public var draft: String
    public private(set) var asking: Set<ID> = []
    public private(set) var errors: [ID: ChatActionError] = [:]
    public var canSendNow: Bool { sendNowHook != nil }

    private let removeHook: Action
    private let sendNowHook: Action?
    @ObservationIgnored private var sendNowIntents: Set<String> = []
    @ObservationIgnored private var consumedIntents: Set<String> = []
    @ObservationIgnored private var revisions: [ID: UInt64] = [:]

    public init(replies: [Reply] = [], draft: String = "", remove: @escaping Action, sendNow: Action? = nil) {
        self.replies = replies
        self.draft = draft
        removeHook = remove
        sendNowHook = sendNow
    }

    /// Stable oldest-first ordering; equal timestamps retain the host's order.
    public var queued: [Reply] {
        replies.enumerated().filter { $0.element.state == .inThreadQueue }.sorted {
            $0.element.createdAt == $1.element.createdAt
                ? $0.offset < $1.offset : $0.element.createdAt < $1.element.createdAt
        }.map(\.element)
    }

    public func isBusy(_ reply: Reply) -> Bool {
        asking.contains(reply.id) || reply.actionPending
    }

    /// Publish fresh host snapshots, then call sendNowWhereQueued(). No polling or transport is owned here.
    public func replaceReplies(_ replies: [Reply]) {
        let previous = Dictionary(self.replies.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let next = Dictionary(replies.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for id in Set(previous.keys).union(next.keys) where previous[id] != next[id] {
            revisions[id, default: 0] &+= 1
        }
        self.replies = replies
    }

    /// Call when the composer requests Send now before the reply has reached the thread's queue.
    public func sendNowWhenQueued(clientRef: String) {
        guard canSendNow, !consumedIntents.contains(clientRef) else { return }
        sendNowIntents.insert(clientRef)
    }

    public func sendNowWhereQueued() async {
        for reply in queued where !isBusy(reply) && sendNowIntents.contains(reply.clientRef) {
            _ = await sendNow(reply)
        }
    }

    @discardableResult
    public func remove(_ reply: Reply) async -> Result<Void, ChatActionError> {
        await perform(reply, hook: removeHook, action: .remove)
    }

    @discardableResult
    public func sendNow(_ reply: Reply) async -> Result<Void, ChatActionError> {
        guard let sendNowHook else { return .failure(.unavailable) }
        return await perform(reply, hook: sendNowHook, action: .sendNow)
    }

    @discardableResult
    public func edit(_ reply: Reply) async -> Result<Void, ChatActionError> {
        let words = replies.first(where: { $0.id == reply.id })?.text ?? reply.text
        let result = await remove(reply)
        if case .success = result {
            // Read the draft after the network returns: words typed while waiting must survive.
            draft = draft.isEmpty ? words : words + "\n\n" + draft
        }
        return result
    }

    private enum Mutation { case remove, sendNow }

    private func perform(_ reply: Reply, hook: Action, action: Mutation) async -> Result<Void, ChatActionError> {
        guard let current = replies.first(where: { $0.id == reply.id }), current.state == .inThreadQueue else {
            return .failure(.unavailable)
        }
        guard !isBusy(current) else { return .failure(.busy) }
        let revision = revisions[current.id, default: 0]
        asking.insert(current.id)
        errors[current.id] = nil
        if case .sendNow = action {
            sendNowIntents.remove(current.clientRef)
            consumedIntents.insert(current.clientRef)
        }
        defer { asking.remove(current.id) }
        switch await hook(current) {
        case let .success(updated):
            // A host snapshot published during suspension is authoritative. Never resurrect an older queue row.
            guard revisions[current.id, default: 0] == revision else {
                if case .remove = action, let latest = replies.first(where: { $0.id == current.id }),
                   latest.state != .inThreadQueue, latest.state != .removed {
                    errors[current.id] = .unavailable
                    return .failure(.unavailable)
                }
                return .success(())
            }
            if let index = replies.firstIndex(where: { $0.id == current.id }) {
                if let updated { replies[index] = updated } else { replies.remove(at: index) }
            }
            return .success(())
        case let .failure(error):
            errors[current.id] = error
            return .failure(error)
        }
    }
}
