import SwiftUI

/// Equal cells side by side only when every answer fits on one line, otherwise one per row.
struct ThreadAnswerLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? min(ChatStyle.answerMaxWidth, ideal) * CGFloat(subviews.count)
            + ChatSpace.sm * CGFloat(subviews.count - 1)
        let sideBySide = fits(in: width, subviews)
        let cell = sideBySide ? cellWidth(in: width, count: subviews.count) : width
        let heights = subviews.map { $0.sizeThatFits(.init(width: cell, height: nil)).height }
        return CGSize(width: width, height: sideBySide ? heights.max() ?? 0
            : heights.reduce(0, +) + ChatSpace.sm * CGFloat(subviews.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let sideBySide = fits(in: bounds.width, subviews)
        let cell = sideBySide ? cellWidth(in: bounds.width, count: subviews.count) : bounds.width
        let proposed = ProposedViewSize(width: cell, height: nil)
        var origin = bounds.origin
        for subview in subviews {
            subview.place(at: origin, anchor: .topLeading, proposal: proposed)
            if sideBySide { origin.x += cell + ChatSpace.sm }
            else { origin.y += subview.sizeThatFits(proposed).height + ChatSpace.sm }
        }
    }

    private func cellWidth(in width: CGFloat, count: Int) -> CGFloat {
        min(ChatStyle.answerMaxWidth, max(0, (width - ChatSpace.sm * CGFloat(count - 1)) / CGFloat(count)))
    }

    private func fits(in width: CGFloat, _ subviews: Subviews) -> Bool {
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest <= cellWidth(in: width, count: subviews.count)
    }
}
