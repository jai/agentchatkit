import Foundation

/// A snapshot of one reply. Create a controller per conversation; routing and persistence belong to the host.
public struct QueuedReply<ID: Hashable & Sendable>: Identifiable, Equatable, Sendable {
    public let id: ID
    public var clientRef: String
    public var text: String
    public var createdAt: Date
    public var state: ReplyDeliveryState
    public var statusText: String
    /// An action accepted by the host but still pending at the destination.
    public var actionPending: Bool

    public init(
        id: ID, clientRef: String, text: String, createdAt: Date, state: ReplyDeliveryState = .inThreadQueue,
        statusText: String, actionPending: Bool = false
    ) {
        self.id = id
        self.clientRef = clientRef
        self.text = text
        self.createdAt = createdAt
        self.state = state
        self.statusText = statusText
        self.actionPending = actionPending
    }
}
