import SwiftUI

/// Where a viewer stands among a message's attachments, and what a finished drag across it does. One attachment has
/// nowhere to go: it only closes.
struct ChatMediaPaging: Equatable {
    enum Outcome: Equatable {
        case stays
        case paged
        case closes
    }

    private(set) var index: Int
    let count: Int

    init(count: Int, index: Int) {
        self.count = max(count, 0)
        self.index = min(max(index, 0), max(count - 1, 0))
    }

    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index < count - 1 }

    /// "2 of 4"; nil for one attachment, which has no place to say.
    var position: String? { count > 1 ? "\(index + 1) of \(count)" : nil }

    mutating func previous() {
        if hasPrevious { index -= 1 }
    }

    mutating func next() {
        if hasNext { index += 1 }
    }

    /// A drag mostly down past `ChatStyle.viewerDismissDrag` closes the viewer, as before. One mostly sideways past
    /// `ChatStyle.viewerPageDrag` goes to the next attachment (towards the leading edge) or the one before, and stays
    /// at either end.
    mutating func settle(_ translation: CGSize) -> Outcome {
        let across = abs(translation.width)
        if translation.height > ChatStyle.viewerDismissDrag, translation.height >= across {
            return .closes
        }
        guard across > abs(translation.height), across > ChatStyle.viewerPageDrag else {
            return .stays
        }
        let before = index
        if translation.width < 0 { next() } else { previous() }
        return index == before ? .stays : .paged
    }

    /// How far the pages follow a finger moving sideways: all the way between pages, a third of it past either end.
    func travel(_ translation: CGSize) -> CGFloat {
        guard count > 1, abs(translation.width) > abs(translation.height) else {
            return 0
        }
        let pullsPastEnd = translation.width > 0 ? !hasPrevious : !hasNext
        return pullsPastEnd ? translation.width / 3 : translation.width
    }
}

/// One attachment in a viewer: its picture, and its video when it is one.
struct ChatMediaPage: Identifiable {
    let id: AnyHashable
    let image: CGImage
    var video: ChatVideoClip?
}

/// A message's attachments on the whole screen, as Photos shows them: one fitted on the picture ground, the others a
/// swipe away, with which of them this is ("2 of 4") between a button back and a button on. Closed by its button or a
/// swipe down. A video plays only while it is the one shown.
struct ChatMediaPager: View {
    struct Identifiers {
        /// The whole viewer, as a container.
        var container: String?
        /// The attachment shown.
        var media: String?
        var close: String?
        var position: String?
        var previous: String?
        var next: String?
    }

    @Environment(\.chatTheme) private var theme
    let pages: [ChatMediaPage]
    let identifiers: Identifiers
    let close: () -> Void
    @State private var paging: ChatMediaPaging
    @GestureState private var travel: CGFloat = 0

    init(pages: [ChatMediaPage], start: Int, identifiers: Identifiers, close: @escaping () -> Void) {
        self.pages = pages
        self.identifiers = identifiers
        self.close = close
        _paging = State(initialValue: ChatMediaPaging(count: pages.count, index: start))
    }

    var body: some View {
        ZStack {
            theme.pictureGround.ignoresSafeArea()
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                        media(page, isShown: offset == paging.index)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .offset(x: -CGFloat(paging.index) * proxy.size.width + travel)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .clipped()
                .contentShape(.rect)
                .gesture(drag)
            }
        }
        .overlay(alignment: .top) { stepper }
        .overlay(alignment: .topTrailing) { closeButton }
        .accessibilityElement(children: .contain)
        .chatIdentifier(identifiers.container)
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading: step { $0.previous() }
            case .trailing: step { $0.next() }
            default: break
            }
        }
        #if os(macOS)
        // A video player has no size of its own: without this the Mac's sheet was only as tall as its Close button.
        .frame(minWidth: ChatStyle.screenshotViewerMinWidth, minHeight: ChatStyle.screenshotViewerMinHeight)
        #endif
        .environment(\.colorScheme, .dark)
    }

    private var drag: some Gesture {
        DragGesture()
            .updating($travel) { drag, travel, _ in travel = paging.travel(drag.translation) }
            .onEnded { drag in
                var settled = paging
                switch settled.settle(drag.translation) {
                case .closes: close()
                case .paged: withAnimation(ChatMotion.fold) { paging = settled }
                case .stays: break
                }
            }
    }

    private func step(_ change: (inout ChatMediaPaging) -> Void) {
        var changed = paging
        change(&changed)
        withAnimation(ChatMotion.fold) { paging = changed }
    }

    /// Only the attachment shown is there for VoiceOver and a test, and only its video has a player: one a swipe away
    /// would play unseen.
    @ViewBuilder private func media(_ page: ChatMediaPage, isShown: Bool) -> some View {
        if isShown, let video = page.video {
            ChatVideoPlayer(clip: video)
                .chatIdentifier(identifiers.media)
        } else {
            Image(page.image, scale: 1, label: Text("Screenshot"))
                .resizable()
                .scaledToFit()
                .accessibilityLabel(page.video?.spokenLabel ?? "Screenshot")
                .accessibilityValue(paging.position ?? "")
                .chatIdentifier(isShown ? identifiers.media : nil)
                .accessibilityHidden(!isShown)
        }
    }

    /// Which attachment this is, between the buttons to the one before and the next (the arrow keys press them). A
    /// video's player takes a drag across it for itself, so the buttons are how to leave one.
    @ViewBuilder private var stepper: some View {
        if let position = paging.position {
            HStack(spacing: theme.spacing.sm) {
                stepButton("Previous", symbol: theme.symbols.back, identifier: identifiers.previous,
                           isOn: paging.hasPrevious) { $0.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Text(position)
                    .chatTextStyle(.control)
                    .monospacedDigit()
                    .foregroundStyle(theme.ink)
                    .accessibilityLabel("Attachment \(position)")
                    .chatIdentifier(identifiers.position)
                stepButton("Next", symbol: theme.symbols.drillIn, identifier: identifiers.next,
                           isOn: paging.hasNext) { $0.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(theme.spacing.lg)
        }
    }

    private func stepButton(
        _ title: String, symbol: String, identifier: String?, isOn: Bool,
        change: @escaping (inout ChatMediaPaging) -> Void
    ) -> some View {
        Button(title, systemImage: symbol) { step(change) }
            .chatTextStyle(.control)
            .controlSize(theme.controlSize)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!isOn)
            .chatIdentifier(identifier)
    }

    private var closeButton: some View {
        Button("Close", systemImage: theme.symbols.close, action: close)
            .chatTextStyle(.control)
            .controlSize(theme.controlSize)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(theme.spacing.lg)
            .chatIdentifier(identifiers.close)
    }
}
