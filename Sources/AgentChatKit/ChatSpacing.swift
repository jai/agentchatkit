import SwiftUI

/// Host spacing tokens for the shared thread, queue, question, status and screenshot views.
public struct ChatSpacing: Sendable {
    public var xs: CGFloat
    public var sm: CGFloat
    public var md: CGFloat
    public var lg: CGFloat
    public var rowInsets: EdgeInsets

    public init(xs: CGFloat = ChatSpace.xs, sm: CGFloat = ChatSpace.sm,
                md: CGFloat = ChatSpace.md, lg: CGFloat = ChatSpace.lg,
                rowInsets: EdgeInsets = EdgeInsets(top: ChatSpace.xs, leading: ChatSpace.lg,
                                                   bottom: ChatSpace.xs, trailing: ChatSpace.lg)) {
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.rowInsets = rowInsets
    }
}
