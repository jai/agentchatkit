@testable import AgentChatKit
import SwiftUI
import Testing

/// The second delivery tick is whole and tucked behind the first, with a clear cut where the first passes over it.
@MainActor
struct DeliveryTickMarksTests {
    private static let scale: CGFloat = 20
    /// Room around the ticks for their round ends.
    private static let room: CGFloat = 4

    /// How opaque the marks are at a point in their own 9 pt by 7 pt coordinates, 0 to 255.
    private static func alpha(count: Int, at points: [CGPoint]) throws -> [UInt8] {
        let renderer = ImageRenderer(content: DeliveryTickMarks(count: count).foregroundStyle(.black).padding(room)
            .dynamicTypeSize(.large))
        renderer.scale = scale
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return points.map { point in
            let row = Int((point.y + room) * scale), column = Int((point.x + room) * scale)
            return pixels[(row * image.width + column) * 4 + 3]
        }
    }

    @Test func theSecondTickIsCutWhereTheFirstPassesOverIt() throws {
        let alpha = try Self.alpha(count: 2, at: [
            CGPoint(x: 5.42, y: 4.15), // the first tick's long arm, over the second's short arm
            CGPoint(x: 6.33, y: 4.80), // the cut beside it, on the second's short arm
            CGPoint(x: 7.50, y: 5.63), // the stub of the second's short arm
            CGPoint(x: 11.0, y: 3.50), // the second's long arm
        ])
        #expect(alpha[0] > 240)
        #expect(alpha[1] < 15)
        #expect(alpha[2] > 240)
        #expect(alpha[3] > 240)
    }

    @Test func aSentMessageHasOneWholeTick() throws {
        let alpha = try Self.alpha(count: 1, at: [CGPoint(x: 1.6, y: 4.99), CGPoint(x: 6.1, y: 3.52)])
        #expect(alpha[0] > 240)
        #expect(alpha[1] > 240)
    }
}
