import AgentChatKit
import SwiftUI

/// Loads one resource with the host's authentication/resolution policy. Never log its URI or use it as a UI ID.
/// Return image bytes (JPEG/PNG etc. supported by ImageIO), or a safe user-facing error. Unsupported MIME slots are
/// left empty so the generic strip/viewer retains the attachment's original index, even after a decode failure.
public typealias LiveAttachmentLoader = @Sendable (LiveAttachment) async -> Result<Data, ChatActionError>
/// Fetches a video attachment, with the host's authentication, to a file it can play, and returns the file's URL
/// (`LiveScreenshotStrip.loadsVideos`).
public typealias LiveVideoLoader = @Sendable (LiveAttachment) async -> Result<URL, ChatActionError>

public struct LiveScreenshotStrip: View {
    public let live: LiveChatModel
    public let messageID: String
    public var identifiers: SentScreenshotIdentifiers
    private let load: LiveAttachmentLoader
    private var loadVideo: LiveVideoLoader?

    public init(live: LiveChatModel, messageID: String, identifiers: SentScreenshotIdentifiers = .init(),
                load: @escaping LiveAttachmentLoader) {
        self.live = live
        self.messageID = messageID
        self.identifiers = identifiers
        self.load = load
    }

    public var body: some View {
        if let message = live.chat.message(messageID), message.status != .removed, !message.attachments.isEmpty {
            let attachments = message.attachments
            let load = load
            let loadVideo = loadVideo
            SentScreenshotStrip(key: messageID, identifiers: identifiers) { _ in
                await Self.media(for: attachments, load: load, loadVideo: loadVideo)
            }
            // A streamed replacement of resources cancels/reloads presentation, even for the same message id.
            .id(attachments.map(AttachmentVersion.init))
        }
    }
}

extension LiveScreenshotStrip {
    /// Videos shown and played too: each `video/` attachment is fetched with `load` to a file, shown by its poster
    /// frame with its length, and played in the viewer (jai/agentchatkit#4). Without it a video keeps an empty slot.
    public func loadsVideos(_ load: @escaping LiveVideoLoader) -> Self {
        var strip = self
        strip.loadVideo = load
        return strip
    }

    /// The strip's pictures and videos, in the attachments' order. An attachment that can't be shown keeps an empty
    /// slot, so the others keep their indexes.
    static func media(for attachments: [LiveAttachment], load: LiveAttachmentLoader,
                      loadVideo: LiveVideoLoader?) async -> Result<[SentMedia], ChatActionError> {
        var media: [SentMedia] = []
        for attachment in attachments {
            guard !Task.isCancelled else {
                return .success([])
            }
            let mime = attachment.mimeType?.lowercased() ?? ""
            if mime.hasPrefix("image/") {
                switch await load(attachment) {
                case let .success(data): media.append(.picture(data))
                case let .failure(error): return .failure(error)
                }
            } else if mime.hasPrefix("video/"), let loadVideo, case let .success(url) = await loadVideo(attachment),
                      let poster = await ComposerVideo.stills(of: url, count: 1).first {
                let length: Duration? = if let ms = attachment.durationMs { .milliseconds(ms) } else { nil }
                let duration = if let length { length } else { await ComposerVideo.duration(of: url) ?? .zero }
                media.append(.video(poster: poster, clip: ChatVideoClip(url: url, duration: duration)))
            } else {
                media.append(.picture(Data()))
            }
        }
        return .success(media)
    }
}

private struct AttachmentVersion: Hashable {
    let name: String
    let uri: String
    let mime: String?
    let width: Int?
    let height: Int?
    let duration: Int?
    init(_ attachment: LiveAttachment) {
        name = attachment.name
        uri = attachment.uri
        mime = attachment.mimeType
        width = attachment.width
        height = attachment.height
        duration = attachment.durationMs
    }
}
