import SwiftUI

/// A chat's bubble and field (`SessionBubble`, `SessionComposer`). Each measure's only home: a change to one is one line
/// here. Colours, fonts and icons are the host's (`ChatTheme`); these are the chat's own shape.
public enum ChatStyle {
    /// Words from the bubble's edge.
    public static let bubbleInsets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    /// Words from the field's edge.
    public static let fieldInsets = EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14)
    /// The room a bubble leaves on the other side, so whose it is reads at a glance.
    public static let otherSide: CGFloat = 48
    /// The most of a wide chat's width a bubble takes, so on an iPad or a Mac window it stays a bubble, never a page.
    /// A chat narrower than `shareFrom` (a phone) only keeps `otherSide`.
    public static let widestShare: CGFloat = 0.75
    public static let shareFrom: CGFloat = 480
    public static let radius = ChatRadius.lg
    /// How far down an attachment open full screen is swiped to close it.
    public static let viewerDismissDrag: CGFloat = 120
    /// The fade over the page above the field's bar, and the room it leaves over the field.
    public static let barFade: CGFloat = 14
    /// A screenshot waiting to go with the message, above the field, and the button that takes it off.
    public static let attachmentSize: CGFloat = 64
    public static let attachmentRemove: CGFloat = 22
    /// How far the second delivery tick sits over the first: half a glyph, so the two read as one mark (Jai,
    /// 2026-11-14: at a quarter the edges only touched).
    public static let tickOverlap: CGFloat = -6
    /// How near the end of a chat counts as reading it, so a new message keeps the reader there.
    public static let followSlack: CGFloat = 40
    /// A message bar's widest on a wide iPad, centred: the width of an iPad in portrait.
    public static let barMaxWidth: CGFloat = 820
    /// Equal-width quick answers stop growing on a wide Mac window.
    public static let answerMaxWidth: CGFloat = 240
    public static let screenshotViewerMinWidth: CGFloat = 480
    public static let screenshotViewerMinHeight: CGFloat = 360
}

/// What people write, laid out (`MarkdownText`).
public enum MarkdownStyle {
    /// Between a list's marker or checkbox and its words.
    public static let markerGap: CGFloat = 6
    /// A nested list's step in, per level.
    public static let indent: CGFloat = 18
    /// A quote's words from its bar, and the bar's width.
    public static let quoteInset: CGFloat = 10
    public static let quoteBar: CGFloat = 3
    /// A table cell's widest, before its words wrap; a table wider than the text scrolls sideways.
    public static let tableCellMaxWidth: CGFloat = 240
    /// An image's tallest, so a screenshot in a description doesn't take the whole screen.
    public static let imageMaxHeight: CGFloat = 360
    /// A table's border.
    public static let hairline: CGFloat = 0.5
}

/// Space between and around things in a chat. The same steps as PRHub's DESIGN.md `spacing`.
public enum ChatSpace {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
}

/// Corners in a chat. The same steps as PRHub's DESIGN.md `rounded`.
public enum ChatRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 18
}

/// A chat's motion. The same durations as PRHub's DESIGN.md `x-motion`.
public enum ChatMotion {
    /// Something opening, closing or arriving in place.
    public static let fold = Animation.snappy(duration: 0.28)
    /// One state replacing another where it stands, and a picture arriving.
    public static let swap = Animation.easeInOut(duration: 0.18)
}
