import SwiftUI

/// Shared scrolling, lazy rows and menu actions. Navigation remains with the host, including value-based routes.
public struct ChatThreadList<Item: Identifiable, Row: View, Destination: View>: View {
    @Environment(\.chatTheme) private var theme
    public var items: [Item]
    private let title: (Item) -> String
    private let actions: (Item) -> ChatThreadActions
    private let row: (Item) -> Row
    private let navigation: Navigation
    private let header: AnyView
    private let footer: AnyView

    private enum Navigation {
        case host
        case destination((Item) -> Destination)
    }

    /// A host without its own route values can supply each destination directly.
    public init(
        items: [Item], title: @escaping (Item) -> String,
        actions: @escaping (Item) -> ChatThreadActions = { _ in ChatThreadActions() },
        @ViewBuilder row: @escaping (Item) -> Row, @ViewBuilder destination: @escaping (Item) -> Destination
    ) {
        self.items = items
        self.title = title
        self.actions = actions
        self.row = row
        navigation = .destination(destination)
        header = AnyView(EmptyView())
        footer = AnyView(EmptyView())
    }

    /// Rows include the host's own NavigationLink or selection button. Header/footer keep its empty and error states.
    public init<Header: View, Footer: View>(
        items: [Item], title: @escaping (Item) -> String,
        actions: @escaping (Item) -> ChatThreadActions = { _ in ChatThreadActions() },
        @ViewBuilder row: @escaping (Item) -> Row,
        @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer
    ) where Destination == EmptyView {
        self.items = items
        self.title = title
        self.actions = actions
        self.row = row
        navigation = .host
        self.header = AnyView(header())
        self.footer = AnyView(footer())
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ChatSpace.xs) {
                header
                ForEach(items) { item in
                    link(item)
                        .chatThreadActions(title: title(item), actions: actions(item))
                        .transition(.opacity)
                }
                footer
            }
            .padding(.vertical, ChatSpace.sm)
            .animation(ChatMotion.fold, value: items.map(\.id))
        }
        .background(theme.groundPage)
    }

    @ViewBuilder private func link(_ item: Item) -> some View {
        switch navigation {
        case .host: row(item)
        case let .destination(destination):
            NavigationLink { destination(item) } label: { row(item) }
                .buttonStyle(.plain)
        }
    }
}
