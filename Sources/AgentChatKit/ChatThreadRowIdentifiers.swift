import Foundation

public struct ChatThreadRowIdentifiers {
    public var row: String?
    public var context: String?
    public var title: String?
    public var titleMark: String?
    public var about: String?
    public var status: String?
    public var chips: String?

    public init(row: String? = nil, context: String? = nil, title: String? = nil,
                titleMark: String? = nil, about: String? = nil, status: String? = nil, chips: String? = nil) {
        self.row = row
        self.context = context
        self.title = title
        self.titleMark = titleMark
        self.about = about
        self.status = status
        self.chips = chips
    }
}
