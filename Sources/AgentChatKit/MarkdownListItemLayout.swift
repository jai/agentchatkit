import SwiftUI

/// A list item's marker and its words, on one first baseline: an `HStack` that asks the words for their size once. The
/// stack asked three times, the first at no width at all to see how far they give, and words with no width are wrapped
/// a letter to a line: most of the time a chat of long lists took to open (Agent Pager fb_3cde3642c7513c88).
struct MarkdownListItemLayout: Layout {
    let gap: CGFloat

    private func offers(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (marker: ProposedViewSize, words: ProposedViewSize) {
        let marker = subviews[0].sizeThatFits(.unspecified)
        let words = proposal.width.map { max(0, $0 - marker.width - gap) }
        return (.unspecified, ProposedViewSize(width: words, height: proposal.height))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }
        let offers = offers(proposal, subviews)
        let marker = subviews[0].dimensions(in: offers.marker)
        let words = subviews[1].dimensions(in: offers.words)
        let baseline = max(marker[.firstTextBaseline], words[.firstTextBaseline])
        return CGSize(
            width: marker.width + gap + words.width,
            height: max(baseline - marker[.firstTextBaseline] + marker.height, baseline - words[.firstTextBaseline] + words.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            return
        }
        let offers = offers(proposal, subviews)
        let marker = subviews[0].dimensions(in: offers.marker)
        let words = subviews[1].dimensions(in: offers.words)
        let baseline = max(marker[.firstTextBaseline], words[.firstTextBaseline])
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + baseline - marker[.firstTextBaseline]), proposal: offers.marker
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + marker.width + gap, y: bounds.minY + baseline - words[.firstTextBaseline]),
            proposal: offers.words
        )
    }
}
