import AgentChatKit
@testable import AgentChatLive
import Foundation
import Testing

/// A live message's attachments as a strip's pictures and videos (jai/agentchatkit#4). Each keeps its slot, so the
/// ones after an attachment that can't be shown keep their indexes.
struct LiveScreenshotMediaTests {
    private func attachment(_ name: String, _ mime: String?, duration: Int? = nil) -> LiveAttachment {
        LiveAttachment(name: name, uri: "files/\(name)", mimeType: mime, width: nil, height: nil, durationMs: duration)
    }

    private let picture = Data([0xFF, 0xD8, 0xFF])

    @Test func picturesLoadAndAVideoWithNoLoaderKeepsAnEmptySlot() async throws {
        let attachments = [attachment("a.jpg", "image/jpeg"), attachment("b.mov", "video/quicktime", duration: 12000),
                           attachment("c.txt", "text/plain"), attachment("d.png", "image/png")]
        let bytes = picture
        let media = try await LiveScreenshotStrip.media(for: attachments, load: { _ in .success(bytes) },
                                                        loadVideo: nil).get()
        #expect(media.count == 4)
        #expect(media.map(Self.kind) == ["picture", "empty", "empty", "picture"])
    }

    @Test func aVideoThatCannotBeFetchedKeepsAnEmptySlot() async throws {
        let attachments = [attachment("b.mov", "video/mp4")]
        let media = try await LiveScreenshotStrip.media(
            for: attachments, load: { _ in .success(Data()) },
            loadVideo: { _ in .failure(ChatActionError("No network.")) }
        ).get()
        #expect(media.map(Self.kind) == ["empty"])
    }

    private static func kind(_ media: SentMedia) -> String {
        switch media {
        case let .picture(data): data.isEmpty ? "empty" : "picture"
        case .video: "video"
        }
    }
}
