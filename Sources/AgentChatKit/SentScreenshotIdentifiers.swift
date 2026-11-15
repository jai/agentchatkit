import Foundation

public struct SentScreenshotIdentifiers {
    /// Original JPEG index, even when an earlier unreadable image was skipped.
    public var thumbnail: (String, Int) -> String?
    public var viewer: String?
    public var close: String?

    public init(thumbnail: @escaping (String, Int) -> String? = { _, _ in "sent-screenshot" },
                viewer: String? = "sent-screenshot-viewer", close: String? = "sent-screenshot-viewer-close") {
        self.thumbnail = thumbnail
        self.viewer = viewer
        self.close = close
    }
}
