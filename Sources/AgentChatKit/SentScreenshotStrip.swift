import AgentChatCore
import Observation
import SwiftUI

/// Host supplies ordered JPEGs asynchronously. The kit owns no disk paths, persistence or reply-ID aliases.
public struct SentScreenshotStrip: View {
    public typealias Loader = @Sendable (String) async -> Result<[Data], ChatActionError>
    /// Pictures and videos (`SentMedia`), for a host that sends videos.
    public typealias MediaLoader = @Sendable (String) async -> Result<[SentMedia], ChatActionError>
    @Environment(\.chatTheme) private var theme
    @Environment(SentScreenshotViewing.self) private var viewing: SentScreenshotViewing?
    public let key: String
    public var identifiers: SentScreenshotIdentifiers
    private let load: MediaLoader
    @State private var pictures: [SentPicture] = []
    @State private var total = 0
    @State private var problem: ChatActionError?
    @State private var isLoading = true
    @State private var localViewing = SentScreenshotViewing()

    public init(key: String, identifiers: SentScreenshotIdentifiers = .init(), load: @escaping Loader) {
        self.key = key
        self.identifiers = identifiers
        self.load = { key in await load(key).map { $0.map(SentMedia.picture) } }
    }

    /// A strip of pictures and videos: a video shows its poster with a play badge and its length, and plays in the
    /// viewer (jai/agentchatkit#4).
    public init(key: String, identifiers: SentScreenshotIdentifiers = .init(), loadMedia: @escaping MediaLoader) {
        self.key = key
        self.identifiers = identifiers
        load = loadMedia
    }

    private var thumbnails: some View {
        HStack(spacing: theme.spacing.xs) {
            ForEach(pictures) { picture in
                Button {
                    let target = viewing ?? localViewing
                    target.identifiers = identifiers
                    // All of the message's, so the viewer pages through them from the one tapped.
                    target.pictures = pictures
                    target.picture = picture
                } label: {
                    thumbnail(picture)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(picture.video.map { "\($0.spokenLabel), \(picture.index + 1) of \(total)" }
                    ?? "Screenshot \(picture.index + 1) of \(total)")
                .chatIdentifier(identifiers.thumbnail(key, picture.index))
            }
        }
    }

    /// The picture fills a fixed square drawn behind it. Filled directly, a phone's screenshot is 64 × 140 before
    /// its clip, and that whole height became the button's accessibility frame.
    private func thumbnail(_ picture: SentPicture) -> some View {
        let shape = RoundedRectangle(cornerRadius: ChatRadius.md)
        return Color.clear
            .frame(width: ChatStyle.attachmentSize, height: ChatStyle.attachmentSize)
            .background {
                picture.image.resizable().scaledToFill().accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                if let video = picture.video { ChatVideoBadge(duration: video.duration) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.line))
            .contentShape(shape)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if !pictures.isEmpty {
                // The thumbnails sit in a plain row when they fit. A horizontal scroll view inside the
                // conversation's vertical one left the Mac's accessibility frames behind as the conversation
                // scrolled to its end, so clicks and VoiceOver missed the thumbnail (jai/agentchatkit#6).
                ViewThatFits(in: .horizontal) {
                    thumbnails
                    ScrollView(.horizontal) { thumbnails }
                        .scrollIndicators(.hidden)
                }
                .frame(height: ChatStyle.attachmentSize)
            } else if isLoading {
                // The row is there while the pictures load, so the message does not grow under a reader at the
                // chat's end once they come: it grew past the end, under the reply bar (jai/agentchatkit#7).
                RoundedRectangle(cornerRadius: ChatRadius.md)
                    .fill(theme.groundCard)
                    .overlay(RoundedRectangle(cornerRadius: ChatRadius.md).strokeBorder(theme.line))
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(width: ChatStyle.attachmentSize, height: ChatStyle.attachmentSize)
                    .accessibilityElement()
                    .accessibilityLabel("Loading screenshots")
            }
            if let problem {
                Text(problem.message).chatTextStyle(.meta).foregroundStyle(theme.toneBad)
            }
        }
        // A strip works alone too; a conversation may supply one shared viewer for all its strips.
        .modifier(SentScreenshotPresentation(viewing: localViewing))
        .task(id: key) {
            pictures = []
            total = 0
            problem = nil
            isLoading = true
            let loaded = await load(key)
            guard !Task.isCancelled else { return }
            defer { isLoading = false }
            switch loaded {
            case let .success(media):
                let key = key
                let decoded = await Task.detached(priority: .userInitiated) {
                    SentPicture.decode(media: media, key: key)
                }.value
                guard !Task.isCancelled else { return }
                total = media.count
                withAnimation(ChatMotion.swap) { pictures = decoded }
            case let .failure(error): problem = error
            }
        }
    }
}

@MainActor
@Observable
public final class SentScreenshotViewing {
    /// The picture the viewer opens on; nil closes it.
    public var picture: SentPicture?
    /// The pictures of the message `picture` is from, in order: the viewer pages through them. Empty shows `picture`
    /// alone, as a host that sets only `picture` always has.
    public var pictures: [SentPicture] = []
    var identifiers: SentScreenshotIdentifiers = .init()

    public init() {}
}

extension View {
    /// A single viewer shared by all of a conversation's strips. Selection is presentation only.
    public func presentsSentScreenshots(_ viewing: SentScreenshotViewing,
                                        identifiers: SentScreenshotIdentifiers? = nil) -> some View {
        environment(viewing).modifier(SentScreenshotPresentation(viewing: viewing, identifiers: identifiers))
    }
}

struct SentScreenshotPresentation: ViewModifier {
    @Bindable var viewing: SentScreenshotViewing
    var identifiers: SentScreenshotIdentifiers?

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $viewing.picture) { viewer($0) }
        #else
        content.sheet(item: $viewing.picture) { viewer($0) }
        #endif
    }

    private func viewer(_ picture: SentPicture) -> some View {
        SentScreenshotViewer(pictures: viewing.pictures, starting: picture,
                             identifiers: identifiers ?? viewing.identifiers) { viewing.picture = nil }
    }
}
