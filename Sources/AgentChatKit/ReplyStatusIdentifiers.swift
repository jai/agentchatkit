import Foundation

public struct ReplyStatusIdentifiers {
    public var status: String?
    public var sentTicks: String?
    public var deliveredTicks: String?
    public var retry: String?
    public var cancel: String?
    public var error: String?

    public init(status: String? = "reply-status", sentTicks: String? = "reply-ticks-1",
                deliveredTicks: String? = "reply-ticks-2", retry: String? = nil, cancel: String? = nil,
                error: String? = nil) {
        self.status = status
        self.sentTicks = sentTicks
        self.deliveredTicks = deliveredTicks
        self.retry = retry
        self.cancel = cancel
        self.error = error
    }
}
