import SwiftUI

public extension View {
    /// Keeps the reader at the end of a `ChatScroll` while they read it, and leaves them where they are once they scroll
    /// up: a long answer landing grows the page under them and they stay with its foot. Put on the `ChatScroll`, inside
    /// a `ScrollViewReader`, with `endID` the `id` of the chat's whole content (not of a row at its foot, which the
    /// scroll view would keep in place of the end).
    ///
    /// - Parameters:
    ///   - readsEnd: Whether they were at the end when they last scrolled; the host may read it (to draw less, say).
    ///   - isLoadingEarlier: While older messages go in above: the page holds what they read where it is.
    ///   - sent: Changes when they send a message: the page goes to the end with it.
    func followsChatEnd<Sent: Equatable>(
        _ proxy: ScrollViewProxy, endID: some Hashable, readsEnd: Binding<Bool>, isLoadingEarlier: Bool = false,
        sent: Sent
    ) -> some View {
        modifier(ChatFollow(
            proxy: proxy, endID: AnyHashable(endID), readsEnd: readsEnd, isLoadingEarlier: isLoadingEarlier, sent: sent
        ))
    }
}

private struct ChatFollow<Sent: Equatable>: ViewModifier {
    let proxy: ScrollViewProxy
    let endID: AnyHashable
    @Binding var readsEnd: Bool
    let isLoadingEarlier: Bool
    let sent: Sent
    /// While a finger, or the fling it gave, moves the page: the page is theirs, not ours.
    @State private var isScrolling = false
    /// How tall the page was when they last touched it: what arrives while they scroll is not them scrolling away.
    @State private var heightAtTouch: CGFloat = 0

    /// How far below the bottom bars and keyboard the end of the page is. The visible rect runs under the bars.
    private static func distanceToEnd(_ geometry: ScrollGeometry) -> CGFloat {
        geometry.contentSize.height - (geometry.visibleRect.maxY - geometry.contentInsets.bottom)
    }

    func body(content: Content) -> some View {
        content
            // The page grows or shrinks under them: reading the end, they stay at it; loading earlier, what they read
            // stays where it is. The scroll view's own anchor, so it is laid out that way in one frame. Moved after the
            // layout it had first shown, the page slid, and a row at its foot with an `id` of its own left it short.
            .defaultScrollAnchor(isLoadingEarlier || (readsEnd && !isScrolling) ? .bottom : .top, for: .sizeChanges)
            // Where they read is where their own scrolling stops; the page growing, or the bars and keyboard moving,
            // says nothing of it.
            .onScrollPhaseChange { old, new, context in
                let geometry = context.geometry
                isScrolling = new == .interacting || new == .decelerating
                if new == .interacting {
                    heightAtTouch = geometry.contentSize.height
                }
                guard new == .idle, old != .idle else {
                    return
                }
                let distance = Self.distanceToEnd(geometry)
                readsEnd = distance <= ChatStyle.followSlack + max(0, geometry.contentSize.height - heightAtTouch)
                // A message that landed while they flung to the end is caught up with once they let go.
                if readsEnd, distance > 1, old == .interacting || old == .decelerating {
                    toEnd()
                }
            }
            // The keyboard, or a field growing, covers the end of the page: someone reading it stays with it.
            .onScrollGeometryChange(for: CGFloat.self, of: \.contentInsets.bottom) { old, new in
                if readsEnd, new > old {
                    toEnd()
                }
            }
            // A message they send lands at the end: the page goes there with it.
            .onChange(of: sent) {
                readsEnd = true
                Task { @MainActor in
                    await Task.yield()
                    toEnd()
                }
            }
    }

    private func toEnd() {
        withAnimation(ChatMotion.fold) { proxy.scrollTo(endID, anchor: .bottom) }
    }
}
