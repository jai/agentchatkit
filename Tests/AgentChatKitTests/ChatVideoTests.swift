@testable import AgentChatKit
import CoreGraphics
import Foundation
import Testing

/// Videos kept as videos: their length on a thumbnail, and a sent strip's pictures and videos in order
/// (jai/agentchatkit#4).
struct ChatVideoTests {
    @Test func aVideosLengthReadsAsMinutesAndSeconds() {
        #expect(ChatVideoClip.durationText(.seconds(7)) == "0:07")
        #expect(ChatVideoClip.durationText(.seconds(65)) == "1:05")
        #expect(ChatVideoClip.durationText(.seconds(3723)) == "1:02:03")
    }

    @Test func aStripsVideosKeepTheirClipAndEveryItemItsIndex() throws {
        let jpeg = try #require(Self.jpeg())
        let clip = ChatVideoClip(url: URL(fileURLWithPath: "/tmp/clip.mov"), duration: .seconds(12))
        let pictures = SentPicture.decode(
            media: [.picture(jpeg), .picture(Data()), .video(poster: jpeg, clip: clip)], key: "m1"
        )
        #expect(pictures.map(\.index) == [0, 2])
        #expect(pictures[0].video == nil)
        #expect(pictures[1].video == clip)
    }

    private static func jpeg() -> Data? {
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context?.makeImage().flatMap(ComposerVideo.jpeg)
    }
}
