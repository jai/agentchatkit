import Foundation

public struct QueuedReplyIdentifiers {
    public var row: String?
    public var text: String?
    public var status: String?
    public var edit: String?
    public var remove: String?
    public var sendNow: String?

    public init(row: String? = "queued-reply", text: String? = nil, status: String? = nil,
                edit: String? = nil, remove: String? = nil, sendNow: String? = nil) {
        self.row = row
        self.text = text
        self.status = status
        self.edit = edit
        self.remove = remove
        self.sendNow = sendNow
    }
}
