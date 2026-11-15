import Foundation

/// A host's user-facing failure. Transport codes and retry policy remain with the host.
public struct ChatActionError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }

    public static let busy = ChatActionError("An action is already in progress.")
    public static let unavailable = ChatActionError("That action is no longer available.")
}
