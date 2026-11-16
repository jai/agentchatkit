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
    /// Set when this is a video's poster frame: the viewer plays it.
    public internal(set) var video: ChatVideoClip?

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

    /// Pictures and videos' posters, in order, each keeping its index even if another could not be read.
    public static func decode(media: [SentMedia], key: String) -> [SentPicture] {
        media.enumerated().compactMap { index, item in
            switch item {
            case let .picture(jpeg):
                return SentPicture(key: key, index: index, jpeg: jpeg)
            case let .video(poster, clip):
                var picture = SentPicture(key: key, index: index, jpeg: poster)
                picture?.video = clip
                return picture
            }
        }
    }

    public var image: Image { Image(preview, scale: 1, label: Text("Screenshot")) }
}
