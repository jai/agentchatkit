import SwiftUI

/// A titled group of a chat list's rows (`ChatThreadList.grouped(_:)`): a project, a day, "Waiting on you".
public struct ChatThreadGroup<ID: Hashable>: Identifiable {
    public var id: String
    public var title: String
    public var items: [ID]
    public var isFoldable: Bool
    public var identifier: String?

    public init(id: String, title: String, items: [ID], isFoldable: Bool = true, identifier: String? = nil) {
        self.id = id
        self.title = title
        self.items = items
        self.isFoldable = isFoldable
        self.identifier = identifier
    }

    /// The group's rows from the list's items, in the group's order; an ID with no item is left out.
    func rows<Item: Identifiable>(from items: [Item]) -> [Item] where Item.ID == ID {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return self.items.compactMap { byID[$0] }
    }
}

/// A group's header: its title and count, and a chevron that folds it when it can fold.
struct ChatThreadGroupHeader<ID: Hashable>: View {
    @Environment(\.chatTheme) private var theme
    let group: ChatThreadGroup<ID>
    let isFolded: Bool
    let toggle: () -> Void

    var body: some View {
        if group.isFoldable {
            Button(action: toggle) { label }
                .buttonStyle(.plain)
                .accessibilityValue(isFolded ? "Folded" : "Open")
                .accessibilityIdentifier(group.identifier ?? "chat-group-\(group.id)")
        } else {
            label.accessibilityIdentifier(group.identifier ?? "chat-group-\(group.id)")
        }
    }

    private var label: some View {
        HStack(spacing: ChatSpace.xs) {
            Text(group.title).chatTextStyle(.meta).foregroundStyle(theme.ink)
            Text("\(group.items.count)").chatTextStyle(.meta).foregroundStyle(theme.inkQuiet)
            Spacer(minLength: 0)
            if group.isFoldable {
                Image(systemName: theme.symbols.fold)
                    .rotationEffect(.degrees(isFolded ? -90 : 0))
                    .foregroundStyle(theme.inkQuiet)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }
}

/// The last reply under a thread's row, quiet and on one line: "You: Ship it after the tests."
public struct ChatReplyPreview: View {
    @Environment(\.chatTheme) private var theme
    public let text: String
    public var author: String?
    public var identifier: String?

    public init(_ text: String, author: String? = nil, identifier: String? = nil) {
        self.text = text
        self.author = author
        self.identifier = identifier
    }

    public var body: some View {
        Text(author.map { "\($0): \(text)" } ?? text)
            .chatTextStyle(.meta)
            .foregroundStyle(theme.inkQuiet)
            .lineLimit(1)
            .chatIdentifier(identifier)
    }
}
