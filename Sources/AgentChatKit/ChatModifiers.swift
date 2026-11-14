import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// The phone's convention for a screen with a reply box: a drag in the content — a scroll as it starts — puts the
    /// keyboard away, and so does a tap (`KeyboardDismissTap`; both still reach the list and what they land on). Both
    /// take the field's focus, so the keyboard slides away; the scroll view's own dismissal dropped it with no
    /// animation, and a List reports no scroll phases to watch. The Mac has no keyboard to put away, so there the field
    /// keeps its focus.
    public func dismissesKeyboard(_ focus: FocusState<Bool>.Binding) -> some View {
        #if os(iOS)
        simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
            if focus.wrappedValue {
                focus.wrappedValue = false
            }
        })
        .gesture(KeyboardDismissTap { focus.wrappedValue = false })
        #else
        self
        #endif
    }

    /// The phone's full-screen cover; a sheet over the Mac's window.
    func fullScreenCoverOrSheet<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// A message bar, held on a wide iPad to the width of an iPad in portrait, centred (`ChatStyle.barMaxWidth`).
    public func chatBarWidth() -> some View {
        #if os(iOS)
        frame(maxWidth: ChatStyle.barMaxWidth).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }
}

extension VerticalAlignment {
    /// A message field's send button: on the phone centred on the field's last line; on the
    /// Mac, whose glass button is shorter than the field, on the last line's baseline, so it sits centred on that line
    /// at every text size.
    public static var sendButton: VerticalAlignment {
        #if os(macOS)
        .lastTextBaseline
        #else
        VerticalAlignment(ComposerLine.self)
        #endif
    }

    /// The field's last line on the phone: the button's middle sits on it, so a one-line field and its button are
    /// centred, and a grown field keeps the button by the line being typed.
    private enum ComposerLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
}

#if os(iOS)
/// A tap that leaves the touch to what it lands on. A SwiftUI `TapGesture` over a `List`, even a simultaneous one, stops
/// the list's `Button` rows firing; a recognizer that does not cancel touches does not.
private struct KeyboardDismissTap: UIGestureRecognizerRepresentable {
    let dismiss: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended {
            dismiss()
        }
    }
}
#endif
