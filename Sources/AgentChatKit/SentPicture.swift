import Foundation
import ImageIO
import SwiftUI

/// Decoded once, with the original index even if another attachment was unreadable.
public struct SentPicture: Identifiable, Sendable {
    public struct ID: Hashable, Sendable {
        public let key: String
        public let index: Int
    }

    public let id: ID
    public let index: Int
    public let preview: CGImage

    public init?(key: String, index: Int, jpeg: Data) {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }
        id = ID(key: key, index: index)
        self.index = index
        self.preview = preview
    }

    public static func decode(_ jpegs: [Data], key: String) -> [SentPicture] {
        jpegs.enumerated().compactMap { SentPicture(key: key, index: $0.offset, jpeg: $0.element) }
    }

    public var image: Image { Image(preview, scale: 1, label: Text("Screenshot")) }
}
