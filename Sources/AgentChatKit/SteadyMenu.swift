import SwiftUI

/// A menu drawn again only when its rows show something else. A `Menu` drawn with its screen is handed to UIKit again
/// at each redraw: an open one's rows are made anew, and one whose finger was down just then takes no tap (Agent Pager
/// fb_569733d05b7b197c). What `rows` and `face` draw comes from `shown` and `look` alone, and from the environment; a
/// row, and the tap (`primary`), act through `choose`, which reaches the screen's latest `perform`.
struct SteadyMenu<Shown: Equatable, Look: Equatable, Choice, Rows: View, Face: View>: View {
    private let shown: Shown
    private let look: Look
    private let perform: (Choice) -> Void
    @State private var content: SteadyMenuContent<Shown, Look, Choice, Rows, Face>

    init(
        _ shown: Shown, look: Look, primary: Choice? = nil, perform: @escaping (Choice) -> Void,
        @ViewBuilder rows: @escaping (Shown, _ choose: @escaping (Choice) -> Void) -> Rows,
        @ViewBuilder face: @escaping (Look) -> Face
    ) {
        self.shown = shown
        self.look = look
        self.perform = perform
        _content = State(initialValue: .init(shown: shown, look: look, primary: primary, rows: rows, face: face))
    }

    var body: some View {
        content.perform = perform
        return DrawnMenu(content: content)
            .onChange(of: shown) { content.shown = shown }
            .onChange(of: look) { content.look = look }
    }
}

@MainActor @Observable
private final class SteadyMenuContent<Shown: Equatable, Look: Equatable, Choice, Rows: View, Face: View> {
    var shown: Shown
    var look: Look
    @ObservationIgnored let primary: Choice?
    @ObservationIgnored let rows: (Shown, _ choose: @escaping (Choice) -> Void) -> Rows
    @ObservationIgnored let face: (Look) -> Face
    /// What its screen last drew the menu with. Not observed: a new one redraws nothing.
    @ObservationIgnored var perform: ((Choice) -> Void)?

    init(
        shown: Shown, look: Look, primary: Choice?,
        rows: @escaping (Shown, _ choose: @escaping (Choice) -> Void) -> Rows, face: @escaping (Look) -> Face
    ) {
        self.shown = shown
        self.look = look
        self.primary = primary
        self.rows = rows
        self.face = face
    }
}

/// Its one value is the same at every redraw of the screen. Not an `Equatable` view of what it shows: SwiftUI does not
/// ask it while a busy machine has not yet prepared to, and draws it again.
private struct DrawnMenu<Shown: Equatable, Look: Equatable, Choice, Rows: View, Face: View>: View {
    let content: SteadyMenuContent<Shown, Look, Choice, Rows, Face>

    var body: some View {
        if let primary = content.primary {
            Menu {
                rows
            } label: {
                DrawnFace(content: content)
            } primaryAction: {
                content.perform?(primary)
            }
        } else {
            Menu {
                rows
            } label: {
                DrawnFace(content: content)
            }
        }
    }

    private var rows: some View {
        content.rows(content.shown) { [content] in content.perform?($0) }
    }
}

/// Apart from the menu: a new look draws the face alone, not the rows.
private struct DrawnFace<Shown: Equatable, Look: Equatable, Choice, Rows: View, Face: View>: View {
    let content: SteadyMenuContent<Shown, Look, Choice, Rows, Face>

    var body: some View {
        content.face(content.look)
    }
}
