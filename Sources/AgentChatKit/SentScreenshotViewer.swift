import SwiftUI

/// A sent message's attachments on the whole screen. Given all of a message's pictures it pages through them, opening
/// on the one tapped, and says which it shows ("2 of 4"); given one, it shows that one.
public struct SentScreenshotViewer: View {
    /// The picture it opens on.
    public let picture: SentPicture
    public let close: () -> Void
    public var identifiers: SentScreenshotIdentifiers
    private let pictures: [SentPicture]

    public init(picture: SentPicture, identifiers: SentScreenshotIdentifiers = .init(), close: @escaping () -> Void) {
        self.init(pictures: [picture], starting: picture, identifiers: identifiers, close: close)
    }

    /// `pictures` are the message's, in its order; `starting` is the one tapped. One that is not among them is shown
    /// alone.
    public init(
        pictures: [SentPicture], starting: SentPicture, identifiers: SentScreenshotIdentifiers = .init(),
        close: @escaping () -> Void
    ) {
        picture = starting
        self.pictures = pictures.contains { $0.id == starting.id } ? pictures : [starting]
        self.close = close
        self.identifiers = identifiers
    }

    public var body: some View {
        ChatMediaPager(
            pages: pictures.map { ChatMediaPage(id: $0.id, image: $0.preview, video: $0.video) },
            start: pictures.firstIndex { $0.id == picture.id } ?? 0,
            identifiers: .init(media: identifiers.viewer, close: identifiers.close, position: identifiers.position,
                               previous: identifiers.previous, next: identifiers.next),
            close: close
        )
        // Another picture opened while the viewer is up starts it again there.
        .id(picture.id)
    }
}
