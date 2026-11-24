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

    /// The smallest of the system's that needs no enlarging, which would blur it. Their strokes are 12 to 14% of their
    /// size, as the system font's are of its capitals.
    private var system: ControlSize {
        #if os(macOS)
        side <= 16 ? .small : .large
        #else
        side <= 20 ? .regular : .large
        #endif
    }

    var body: some View {
        let side = side
        ProgressView()
            .controlSize(system)
            // The system's grows with the text too, and thinner; `side` already has the text's size in it.
            .dynamicTypeSize(.large)
            .fixedSize()
            .visualEffect { spinner, place in spinner.scaleEffect(side / max(place.size.height, 1)) }
            .frame(width: side, height: side)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
    }
}
