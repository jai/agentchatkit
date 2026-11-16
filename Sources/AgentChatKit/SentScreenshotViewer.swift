import SwiftUI

public struct SentScreenshotViewer: View {
    @Environment(\.chatTheme) private var theme
    public let picture: SentPicture
    public let close: () -> Void
    public var identifiers: SentScreenshotIdentifiers

    public init(picture: SentPicture, identifiers: SentScreenshotIdentifiers = .init(), close: @escaping () -> Void) {
        self.picture = picture
        self.close = close
        self.identifiers = identifiers
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.pictureGround.ignoresSafeArea()
            Group {
                if let video = picture.video {
                    ChatVideoPlayer(clip: video)
                } else {
                    picture.image
                        .resizable().scaledToFit()
                        .accessibilityLabel("Screenshot")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .chatIdentifier(identifiers.viewer)
            Button("Close", systemImage: theme.symbols.close, action: close)
                .chatTextStyle(.control)
                .controlSize(theme.controlSize)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(theme.spacing.lg)
                .chatIdentifier(identifiers.close)
        }
        #if os(macOS)
        .frame(minWidth: ChatStyle.screenshotViewerMinWidth, minHeight: ChatStyle.screenshotViewerMinHeight)
        #endif
        .environment(\.colorScheme, .dark)
        .gesture(DragGesture().onEnded { drag in
            if drag.translation.height > ChatStyle.viewerDismissDrag { close() }
        })
    }
}
