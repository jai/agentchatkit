import SwiftUI

public struct SentScreenshotViewer: View {
    @Environment(\.chatTheme) private var theme
    public let picture: SentPicture
    public let close: () -> Void

    public init(picture: SentPicture, close: @escaping () -> Void) {
        self.picture = picture
        self.close = close
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.pictureGround.ignoresSafeArea()
            picture.image
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Screenshot")
                .accessibilityIdentifier("sent-screenshot-viewer")
            Button("Close", systemImage: theme.symbols.close, action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(ChatSpace.lg)
                .accessibilityIdentifier("sent-screenshot-viewer-close")
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
