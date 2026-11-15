import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AgentChatKit

struct SentPictureTests {
    private func jpeg(width: Int, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: 8))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    @Test func decodeKeepsNumericOrderAndOriginalPositionsAcrossUnreadableImages() throws {
        let images = try (1...11).map { try jpeg(width: $0 + 8) }
        var input = images
        input[3] = Data("invalid JPEG".utf8)
        let decoded = SentPicture.decode(input, key: "reply-a")
        #expect(decoded.map(\.index) == [0, 1, 2, 4, 5, 6, 7, 8, 9, 10])
        #expect(decoded.map { $0.preview.width } == [9, 10, 11, 13, 14, 15, 16, 17, 18, 19])
        #expect(decoded.map(\.id) == SentPicture.decode(input, key: "reply-a").map(\.id), "stable on reload")
        #expect(decoded.first?.id != SentPicture.decode(input, key: "reply-b").first?.id)
    }

    @Test func absentOrInvalidPicturesProduceNoThumbnails() {
        #expect(SentPicture.decode([], key: "empty").isEmpty)
        #expect(SentPicture(key: "bad", index: 0, jpeg: Data()) == nil)
    }

    @Test func aRotatedJPEGIsDecodedUpright() throws {
        let picture = try #require(SentPicture(key: "rotated", index: 0, jpeg: jpeg(width: 13, orientation: 6)))
        #expect(picture.preview.width == 8)
        #expect(picture.preview.height == 13)
    }
}
