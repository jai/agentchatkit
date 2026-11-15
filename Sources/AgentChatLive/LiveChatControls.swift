import AgentChatKit
import Foundation
import Observation

/// Request state only. The stream remains the sole owner of messages, queue membership and delivery status.
/// Share one instance between a conversation's adapters to serialize actions on the same message.
@MainActor
@Observable
public final class LiveChatControls {
    public typealias Retry = @MainActor (LiveMessage) async throws -> Void
    public let live: LiveChatModel
    public private(set) var busy: Set<String> = []
    public private(set) var errors: [String: ChatActionError] = [:]
    public private(set) var answering = false
    public private(set) var questionError: ChatActionError?
    private var questionErrorID: JSONValue?

    public func error(for question: LiveQuestion) -> ChatActionError? {
        questionErrorID == question.requestID ? questionError : nil
    }

    public init(live: LiveChatModel) { self.live = live }

    /// Remove before restoring words. The callback runs after the request and must read the host's current draft.
    @discardableResult
    public func edit(_ id: String, restore: @MainActor (String) -> Void) async -> Bool {
        guard let message = editable(id) else { return false }
        let succeeded = await perform(id) { _ = try await self.live.remove(id) }
        guard succeeded else { return false }
        // A newer snapshot can have replaced this message while the request was in flight.
        if let latest = live.chat.message(id),
           latest.status != .pending && latest.status != .queued && latest.status != .removed {
            errors[id] = .unavailable
            return false
        }
        restore(message.text)
        return true
    }

    @discardableResult
    public func remove(_ id: String) async -> Bool {
        guard editable(id) != nil else { return false }
        return await perform(id) { _ = try await self.live.remove(id) }
    }

    @discardableResult
    public func sendNow(_ id: String) async -> Bool {
        guard editable(id) != nil else { return false }
        return await perform(id) { _ = try await self.live.sendNow(id) }
    }

    /// There is no failed-message retry RPC in the profile. The host supplies its authorized retry operation.
    @discardableResult
    public func retry(_ id: String, using hook: Retry) async -> Bool {
        guard let message = live.chat.message(id), message.kind == .user, message.status == .failed else {
            return false
        }
        return await perform(id) { try await hook(message) }
    }

    @discardableResult
    public func answer(_ question: LiveQuestion, options: [String], text: String? = nil,
                       decline: Bool = false) async -> Bool {
        guard !answering, live.chat.question == question else { return false }
        answering = true
        questionError = nil
        questionErrorID = question.requestID
        defer { answering = false }
        do {
            if decline { try await live.decline(question) }
            else { try await live.answer(question, options: options, text: text) }
            return true
        } catch {
            if live.chat.question?.requestID == question.requestID {
                questionError = ChatActionError("Could not send your answer. Try again.")
            }
            return false
        }
    }

    private func editable(_ id: String) -> LiveMessage? {
        guard let message = live.chat.message(id), message.kind == .user,
              message.status == .pending || message.status == .queued else { return nil }
        return message
    }

    private func perform(_ id: String, operation: () async throws -> Void) async -> Bool {
        guard !busy.contains(id) else { return false }
        busy.insert(id)
        errors[id] = nil
        defer { busy.remove(id) }
        do {
            try await operation()
            return true
        } catch {
            // Do not display transport errors: they may contain signed URLs or credentials.
            errors[id] = ChatActionError("Could not complete this action. Try again.")
            return false
        }
    }
}
