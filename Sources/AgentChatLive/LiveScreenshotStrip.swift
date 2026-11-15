import AgentChatKit
import SwiftUI

/// Loads one resource with the host's authentication/resolution policy. Never log its URI or use it as a UI ID.
/// Return image bytes (JPEG/PNG etc. supported by ImageIO), or a safe user-facing error. Unsupported MIME slots are
/// left empty so the generic strip/viewer retains the attachment's original index, even after a decode failure.
public typealias LiveAttachmentLoader = @Sendable (LiveAttachment) async -> Result<Data, ChatActionError>

public struct LiveScreenshotStrip: View {
    public let live: LiveChatModel
    public let messageID: String
    public var identifiers: SentScreenshotIdentifiers
    private let load: LiveAttachmentLoader

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
            SentScreenshotStrip(key: messageID, identifiers: identifiers) { _ in
                var bytes: [Data] = []
                for attachment in attachments {
                    guard !Task.isCancelled else { return .success([]) }
                    guard attachment.mimeType?.lowercased().hasPrefix("image/") == true else {
                        bytes.append(Data())
                        continue
                    }
                    switch await load(attachment) {
                    case let .success(data): bytes.append(data)
                    case let .failure(error): return .failure(error)
                    }
                }
                return .success(bytes)
            }
            // A streamed replacement of resources cancels/reloads presentation, even for the same message id.
            .id(attachments.map(AttachmentVersion.init))
        }
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
