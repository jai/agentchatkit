import Foundation

public struct SentScreenshotIdentifiers {
    /// Original JPEG index, even when an earlier unreadable image was skipped.
    public var thumbnail: (String, Int) -> String?
    public var viewer: String?
    public var close: String?
    /// Which of the message's attachments the viewer shows ("2 of 4"), and its buttons to the one before and the next.
    /// There only when the message has more than one.
    public var position: String? = "sent-screenshot-viewer-position"
    public var previous: String? = "sent-screenshot-viewer-previous"
    public var next: String? = "sent-screenshot-viewer-next"

    public init(thumbnail: @escaping (String, Int) -> String? = { _, _ in "sent-screenshot" },
                viewer: String? = "sent-screenshot-viewer", close: String? = "sent-screenshot-viewer-close") {
        self.thumbnail = thumbnail
        self.viewer = viewer
        self.close = close
    }
}
