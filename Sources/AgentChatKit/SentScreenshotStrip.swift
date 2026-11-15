import AgentChatCore
import Observation
import SwiftUI

/// Host supplies ordered JPEGs asynchronously. The kit owns no disk paths, persistence or reply-ID aliases.
public struct SentScreenshotStrip: View {
    public typealias Loader = @Sendable (String) async -> Result<[Data], ChatActionError>
    @Environment(\.chatTheme) private var theme
    @Environment(SentScreenshotViewing.self) private var viewing: SentScreenshotViewing?
    public let key: String
    private let load: Loader
    @State private var pictures: [SentPicture] = []
    @State private var total = 0
    @State private var problem: ChatActionError?
    @State private var localViewing = SentScreenshotViewing()

    public init(key: String, load: @escaping Loader) {
        self.key = key
        self.load = load
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ChatSpace.xs) {
            if !pictures.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: ChatSpace.xs) {
                        ForEach(pictures) { picture in
                            Button { (viewing ?? localViewing).picture = picture } label: {
                                picture.image
                                    .resizable().scaledToFill()
                                    .frame(width: ChatStyle.attachmentSize, height: ChatStyle.attachmentSize)
                                    .clipShape(.rect(cornerRadius: ChatRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: ChatRadius.md).strokeBorder(theme.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Screenshot \(picture.index + 1) of \(total)")
                            .accessibilityIdentifier("sent-screenshot")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: ChatStyle.attachmentSize)
            }
            if let problem {
                Text(problem.message).font(theme.font(.caption)).foregroundStyle(theme.toneBad)
            }
        }
        // A strip works alone too; a conversation may supply one shared viewer for all its strips.
        .modifier(SentScreenshotPresentation(viewing: localViewing))
        .task(id: key) {
            pictures = []
            total = 0
            problem = nil
            let loaded = await load(key)
            guard !Task.isCancelled else { return }
            switch loaded {
            case let .success(jpegs):
                let key = key
                let decoded = await Task.detached(priority: .userInitiated) {
                    SentPicture.decode(jpegs, key: key)
                }.value
                guard !Task.isCancelled else { return }
                total = jpegs.count
                withAnimation(ChatMotion.swap) { pictures = decoded }
            case let .failure(error): problem = error
            }
        }
    }
}

@MainActor
@Observable
public final class SentScreenshotViewing {
    public var picture: SentPicture?
    public init() {}
}

extension View {
    /// A single viewer shared by all of a conversation's strips. Selection is presentation only.
    public func presentsSentScreenshots(_ viewing: SentScreenshotViewing) -> some View {
        environment(viewing).modifier(SentScreenshotPresentation(viewing: viewing))
    }
}

struct SentScreenshotPresentation: ViewModifier {
    @Bindable var viewing: SentScreenshotViewing

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $viewing.picture) { picture in
            SentScreenshotViewer(picture: picture) { viewing.picture = nil }
        }
        #else
        content.sheet(item: $viewing.picture) { picture in
            SentScreenshotViewer(picture: picture) { viewing.picture = nil }
        }
        #endif
    }
}
