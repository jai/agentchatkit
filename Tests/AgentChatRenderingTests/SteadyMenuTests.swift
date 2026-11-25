#if os(iOS)
@testable import AgentChatKit
import SwiftUI
import Testing
import UIKit

@MainActor @Suite(.serialized)
struct SteadyMenuTests {
    @MainActor private final class Rows {
        var shown: [Int] = []
        var looks: [Int] = []
        var choose: ((Int) -> Void)?

        func row(_ shown: Int, _ choose: @escaping (Int) -> Void) -> some View {
            self.shown.append(shown)
            self.choose = choose
            return Button("Row") { choose(shown) }
        }

        func face(_ look: Int) -> some View {
            looks.append(look)
            return Text("Menu \(look)")
        }
    }

    @Observable final class Screen { var draws = 0 }

    private struct Drawn<Content: View>: View {
        let screen: Screen
        let content: (Int) -> Content
        var body: some View { content(screen.draws) }
    }

    @Test func aRowActsThroughTheLatestDrawAndShowsWhatIsNew() async throws {
        let screen = Screen(), rows = Rows()
        var chosen: [String] = []
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: Drawn(screen: screen) { draw in
            SteadyMenu(
                draw / 2, look: draw / 3, perform: { (choice: Int) in chosen.append("draw \(draw), row \(choice)") },
                rows: { rows.row($0, $1) }, face: { rows.face($0) }
            )
        })
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func draw() async throws {
            screen.draws += 1
            try await Task.sleep(for: .milliseconds(800))
        }
        try await Task.sleep(for: .milliseconds(800))
        try await draw()
        rows.choose?(7)
        #expect(chosen == ["draw 1, row 7"])
        #expect(Set(rows.shown) == [0])
        try await draw()
        #expect(rows.shown.last == 1)
        #expect(Set(rows.looks) == [0])
        try await draw()
        #expect(rows.looks.last == 1)
    }
}
#endif
