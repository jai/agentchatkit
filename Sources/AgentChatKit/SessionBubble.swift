import SwiftUI

/// A message in any of the app's chats — a thread, a session message, Ask AI on a PR, Feedback: the agent's on the left
/// in Markdown, Jai's on the right in the accent as he typed them, the time or a note under it, and what hangs under it —
/// where a reply of his stands, or the question waiting on him.
public struct SessionBubble<Accessory: View>: View {
    @Environment(\.chatTheme) private var theme
    public let title: String?
    public let text: String
    public let date: Date?
    public let isMine: Bool
    public var footnote: String?
    public let accessory: Accessory
    /// What the host draws in the bubble in place of the words (`chatMessageContent`).
    var content: AnyView?

    public init(
        title: String?, text: String, date: Date?, isMine: Bool, footnote: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.text = text
        self.date = date
        self.isMine = isMine
        self.footnote = footnote
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: ChatSpace.xs) {
            VStack(alignment: .leading, spacing: ChatSpace.xs) {
                if let title {
                    Text(title)
                        .font(theme.font(.body).weight(.semibold))
                }
                // An agent writes Markdown; Jai's own words are drawn as he typed them. On a Mac the words select; on the
                // phone a long press is Copy, below.
                if let content {
                    content
                } else if isMine {
                    Text(text)
                        .selectable(Self.selectsWords)
                } else {
                    MarkdownText(text, isSelectable: Self.selectsWords)
                }
            }
            .font(theme.font(.callout))
            .padding(ChatStyle.bubbleInsets)
            .foregroundStyle(isMine ? theme.onBubble : theme.ink)
            .background(
                isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                in: .rect(cornerRadius: ChatStyle.radius, style: .continuous)
            )
            // Tap and hold (a right click on a Mac): Copy, the whole message as it was written (Jai, 2026-11-14).
            .contentShape(.rect(cornerRadius: ChatStyle.radius, style: .continuous))
            .contextMenu {
                Button("Copy", systemImage: theme.symbols.copy) { Pasteboard.copy(text) }
                    .accessibilityIdentifier("bubble-copy")
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(theme.font(.caption2))
                    .foregroundStyle(.secondary)
            }
            accessory
        }
        .modifier(BubbleColumn(isMine: isMine))
    }

    /// The bubble with the host's drawing in place of its words, when the host claims its message.
    func drawing(_ content: AnyView?) -> Self {
        var bubble = self
        bubble.content = content
        return bubble
    }

    /// Selection on a Mac; on the phone the bubble's long press is Copy.
    private static var selectsWords: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private var caption: String {
        [date?.formatted(date: .omitted, time: .shortened), footnote].compactMap(\.self).joined(separator: " · ")
    }
}

/// A bubble's place in its chat: the whole width, the bubble at Jai's side or the agent's, never wider than the chat
/// less `ChatStyle.otherSide`, nor, in a wide chat, than `ChatStyle.widestShare` of it. Measured from the width the chat gives, so a
/// column, a sheet or a window each lay their bubbles out alike.
private struct BubbleColumn: ViewModifier {
    let isMine: Bool

    func body(content: Content) -> some View {
        BubbleColumnLayout(isMine: isMine) { content }
    }
}

private struct BubbleColumnLayout: Layout {
    let isMine: Bool

    static func widest(in width: CGFloat) -> CGFloat {
        let roomy = width - ChatStyle.otherSide
        return max(0, width < ChatStyle.shareFrom ? roomy : min(roomy, width * ChatStyle.widestShare))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let bubble = subviews.first else {
            return .zero
        }
        guard let width = proposal.width, width.isFinite else {
            return bubble.sizeThatFits(proposal)
        }
        let size = bubble.sizeThatFits(ProposedViewSize(width: Self.widest(in: width), height: proposal.height))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else {
            return
        }
        let offered = ProposedViewSize(width: Self.widest(in: bounds.width), height: proposal.height)
        let size = bubble.sizeThatFits(offered)
        let x = isMine ? bounds.maxX - size.width : bounds.minX
        bubble.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: offered)
    }
}

extension SessionBubble where Accessory == EmptyView {
    public init(title: String?, text: String, date: Date?, isMine: Bool, footnote: String? = nil) {
        self.init(title: title, text: text, date: date, isMine: isMine, footnote: footnote) { EmptyView() }
    }
}
