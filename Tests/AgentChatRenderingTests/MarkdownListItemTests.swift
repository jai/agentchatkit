@testable import AgentChatKit
import SwiftUI
import Testing

/// A list item looks as it did in the `HStack` it replaced, and asks its words for their size once (Agent Pager
/// fb_3cde3642c7513c88: the stack's first ask, at no width, was most of the time a chat of long lists took to open).
@MainActor
struct MarkdownListItemTests {
    private final class Asks {
        var widths: [CGFloat?] = []
    }

    private struct Asked: Layout {
        let asks: Asks

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            asks.widths.append(proposal.width)
            return subviews[0].sizeThatFits(proposal)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews[0].place(at: bounds.origin, proposal: proposal)
        }
    }

    private static let long = "A point that is long enough to wrap onto another line of a phone, as an agent's points often are"

    private static func image(_ view: some View, width: CGFloat?) -> CGImage? {
        let renderer = ImageRenderer(content: view.environment(\.displayScale, 2))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.cgImage
    }

    private static func pixels(_ image: CGImage?) -> Data? {
        image?.dataProvider?.data as Data?
    }

    /// The asks of an item's words, laid out once in a column 300 pt wide.
    private static func asks(_ item: (AnyView) -> some View) -> [CGFloat?] {
        let asks = Asks()
        let words = AnyView(Asked(asks: asks) { Text(long) })
        _ = image(VStack(alignment: .leading) { item(words) }.frame(width: 300, alignment: .leading), width: 300)
        return asks.widths
    }

    @Test func itsWordsAreNeverAskedForTheirSizeAtNoWidth() {
        let widths = Self.asks { words in MarkdownListItemLayout(gap: 6) { Text("•"); words } }
        #expect(!widths.isEmpty)
        #expect(widths.allSatisfy { ($0 ?? 0) > 200 && ($0 ?? .infinity) < 300 }, "asked at \(widths)")
        #expect(Set(widths.map { $0 ?? -1 }).count == 1, "one width: \(widths)")
        let stack = Self.asks { words in HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); words } }
        #expect(stack.contains(0), "the stack it replaced did: \(stack)")
    }

    /// In a column at least twice its marker: in a narrower one the stack broke the marker, and the item keeps it whole.
    @Test(arguments: [CGFloat(60), 120, 300, 700], [CGFloat(11), 16, 34])
    func itLooksAsTheStackItReplaced(width: CGFloat, font: CGFloat) throws {
        guard width > font * 3.5 else {
            return
        }
        for (marker, words) in [("•", Self.long), ("12.", Self.long), ("•", "Short"), ("☐", "One\nTwo")] {
            let item = Self.image(
                MarkdownListItemLayout(gap: 6) { Text(marker).monospacedDigit(); Text(words) }.font(.system(size: font)), width: width
            )
            let stack = Self.image(
                HStack(alignment: .firstTextBaseline, spacing: 6) { Text(marker).monospacedDigit(); Text(words) }
                    .font(.system(size: font)), width: width
            )
            #expect(item?.width == stack?.width && item?.height == stack?.height, "\(marker) \(words) at \(width), \(font) pt")
            #expect(try #require(Self.pixels(item)) == Self.pixels(stack), "\(marker) \(words) at \(width), \(font) pt")
        }
    }

    @Test func aTasksBoxLooksAsInTheStack() throws {
        let item = Self.image(MarkdownListItemLayout(gap: 6) { Image(systemName: "square"); Text(Self.long) }, width: 200)
        let stack = Self.image(
            HStack(alignment: .firstTextBaseline, spacing: 6) { Image(systemName: "square"); Text(Self.long) }, width: 200
        )
        #expect(try #require(Self.pixels(item)) == Self.pixels(stack))
    }
}
