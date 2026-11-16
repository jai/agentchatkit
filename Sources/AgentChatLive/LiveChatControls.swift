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
    private var failures: [String: RequestFailure] = [:]
    /// A failure belongs to the status at which it occurred, never to a later delivery or removal.
    public var errors: [String: ChatActionError] {
        failures.compactMapValues { failure in
            guard let status = live.chat.message(failure.id)?.status,
                  status == failure.status, status == .pending || status == .queued || status == .failed else {
                return nil
            }
            return failure.error
        }
    }
    public private(set) var answering = false
    public private(set) var questionError: ChatActionError?
    private var questionErrorID: JSONValue?

    public func error(for question: LiveQuestion) -> ChatActionError? {
        questionErrorID == question.requestID ? questionError : nil
    }

    public init(live: LiveChatModel) { self.live = live }

    /// Restore only an explicitly removed message's current words, even if its RPC reply was lost. The callback
    /// reads the host's current draft. Absence in a capped snapshot is not removal confirmation.
    @discardableResult
    public func edit(_ id: String, restore: @MainActor (String) -> Void) async -> Bool {
        guard editable(id) else { return false }
        guard await perform(id, action: .remove, operation: { _ = try await self.live.remove(id) }),
              let removed = live.chat.message(id), removed.status == .removed else { return false }
        restore(removed.text)
        return true
    }

    @discardableResult
    public func remove(_ id: String) async -> Bool {
        guard let status = live.chat.message(id)?.status,
              editable(id) || status == .failed else { return false }
        return await perform(id, action: .remove) { _ = try await self.live.remove(id) }
    }

    @discardableResult
    public func sendNow(_ id: String) async -> Bool {
        guard editable(id) else { return false }
        return await perform(id, action: .force) { _ = try await self.live.sendNow(id) }
    }

    /// Retries the failed message with the same id/clientRef. An optional host operation overrides the live RPC.
    @discardableResult
    public func retry(_ id: String, using hook: Retry? = nil) async -> Bool {
        guard live.chat.message(id)?.status == .failed else { return false }
        return await perform(id, action: .force) {
            if let hook, let message = self.live.chat.message(id) { try await hook(message) } else { _ = try await self.live.retry(id) }
        }
    }

    @discardableResult
    public func answer(_ question: LiveQuestion, options: [String], text: String? = nil) async -> Bool {
        await respond(to: question, with: .answer(options: options, text: text))
    }

    @discardableResult
    public func decline(_ question: LiveQuestion) async -> Bool {
        await respond(to: question, with: .decline)
    }

    private enum Response {
        case answer(options: [String], text: String?)
        case decline
    }

    private func respond(to question: LiveQuestion, with response: Response) async -> Bool {
        guard !answering, live.chat.question == question else { return false }
        answering = true
        questionError = nil
        questionErrorID = question.requestID
        defer { answering = false }
        do {
            switch response {
            case let .answer(options, text): try await live.answer(question, options: options, text: text)
            case .decline: try await live.decline(question)
            }
            return true
        } catch {
            if live.chat.question?.requestID == question.requestID {
                questionError = ChatActionError("Could not send your answer. Try again.")
            }
            return false
        }
    }

    private func editable(_ id: String) -> Bool {
        guard let message = live.chat.message(id), message.kind == .user else { return false }
        return message.status == .pending || message.status == .queued
    }

    private enum Action: Equatable { case remove, force }
    private struct RequestFailure: Equatable {
        let id: String
        let status: LiveMessage.Status
        let error: ChatActionError
    }

    private func perform(_ id: String, action: Action, operation: () async throws -> Void) async -> Bool {
        guard !busy.contains(id), live.chat.message(id)?.kind == .user,
              let initialStatus = live.chat.message(id)?.status else { return false }
        busy.insert(id)
        failures[id] = nil
        defer { busy.remove(id) }
        let accepted: Bool
        do {
            try await operation()
            accepted = true
        } catch {
            accepted = false
        }
        let status = live.chat.message(id)?.status
        // Read after suspension. Request completion never writes messages or invents removal from absence.
        if status == .removed { return action == .remove }
        if status == .delivering || status == .delivered { return action == .force }
        if action == .force, accepted || (status == .pending && initialStatus != .pending) { return true }
        if !accepted, status == initialStatus {
            failures[id] = RequestFailure(id: id, status: initialStatus,
                                          error: ChatActionError("Could not complete this action. Try again."))
        }
        return false
    }
}
