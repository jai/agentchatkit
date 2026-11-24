import SwiftUI

/// The system's spinner at the size of the text it stands by: as tall as that font's capitals and on their baseline, so
/// it is centred on them, its strokes about as heavy as theirs, and it grows as they do. The system's own sizes
/// take no account of it: 14 pt beside 9 pt capitals (Jai, 2026-11-24). Scaled, not drawn here, so Core Animation still plays it.
struct ChatSpinner: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.fontResolutionContext) private var fonts
    let style: Font.TextStyle
    /// Its height, in the font's capitals.
    var capitals: CGFloat = 1

    private var side: CGFloat {
        CTFontGetCapHeight(theme.font(style).resolve(in: fonts).ctFont) * capitals
    }

    /// The smallest of the system's that needs no enlarging, which would blur it, and how tall it draws. Their strokes are
    /// 12 to 14% of their size, as the system font's are of its capitals.
    private func system(for side: CGFloat) -> (size: ControlSize, height: CGFloat) {
        #if os(macOS)
        let small = ControlSize.small
        #else
        let small = ControlSize.regular
        #endif
        return side <= Self.heights.small ? (small, Self.heights.small) : (.large, Self.heights.large)
    }

    /// Known, not read as it is laid out: a `visualEffect` that read it laid the Mac's spinner out again on every pass,
    /// thousands of times a second, until AppKit ended the app (Agent Pager run 45390008471, 2026-11-24).
    /// `ChatSpinnerTests` holds them to the system's.
    #if os(macOS)
    static let heights: (small: CGFloat, large: CGFloat) = (16, 32)
    #else
    static let heights: (small: CGFloat, large: CGFloat) = (20, 37)
    #endif

    var body: some View {
        let side = side
        let system = system(for: side)
        ProgressView()
            .controlSize(system.size)
            // The system's grows with the text too, and thinner; `side` already has the text's size in it.
            .dynamicTypeSize(.large)
            .fixedSize()
            .scaleEffect(side / system.height)
            .frame(width: side, height: side)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
    }
}
