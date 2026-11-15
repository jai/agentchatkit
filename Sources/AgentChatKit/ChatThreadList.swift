import SwiftUI

/// Native rows, selection and actions. Host route values never enter the kit's navigation domain.
public struct ChatThreadList<Item: Identifiable, Row: View, Destination: View>: View {
    @Environment(\.chatTheme) private var theme
    @State private var localSelection: Item.ID?
    @State private var controllers = ChatThreadActionStore<Item.ID>()
    public var items: [Item]
    private let title: (Item) -> String
    private let actions: (Item) -> ChatThreadActions
    private let row: (Item) -> Row
    private let navigation: Navigation
    private let header: AnyView
    private let footer: AnyView
    private let hostSelection: Binding<Item.ID?>?
    private let open: ((Item) -> Void)?

    private enum Navigation {
        case host
        case destination((Item) -> Destination)
    }

    /// Convenience navigation keeps native disclosure indicators. Do not add a second chevron to the row.
    public init(
        items: [Item], title: @escaping (Item) -> String,
        actions: @escaping (Item) -> ChatThreadActions = { _ in ChatThreadActions() },
        selection: Binding<Item.ID?>? = nil, open: ((Item) -> Void)? = nil,
        @ViewBuilder row: @escaping (Item) -> Row, @ViewBuilder destination: @escaping (Item) -> Destination
    ) {
        self.items = items
        self.title = title
        self.actions = actions
        self.row = row
        hostSelection = selection
        self.open = open
        navigation = .destination(destination)
        header = AnyView(EmptyView())
        footer = AnyView(EmptyView())
    }

    /// Rows contain the host's NavigationLink(value:) or selection button. Return calls `open` on Mac.
    /// Header/footer retain the host's starting, new, empty and error content.
    public init<Header: View, Footer: View>(
        items: [Item], title: @escaping (Item) -> String,
        actions: @escaping (Item) -> ChatThreadActions = { _ in ChatThreadActions() },
        selection: Binding<Item.ID?>? = nil, open: ((Item) -> Void)? = nil,
        @ViewBuilder row: @escaping (Item) -> Row,
        @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer
    ) where Destination == EmptyView {
        self.items = items
        self.title = title
        self.actions = actions
        self.row = row
        hostSelection = selection
        self.open = open
        navigation = .host
        self.header = AnyView(header())
        self.footer = AnyView(footer())
    }

    private var selection: Binding<Item.ID?> { hostSelection ?? $localSelection }

    public var body: some View {
        nativeList
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.groundPage)
            .onChange(of: items.map(\.id)) { _, ids in
                controllers.retain(Set(ids))
                if let selected = selection.wrappedValue, !ids.contains(selected) { selection.wrappedValue = nil }
            }
    }

    private var nativeList: some View {
        List(selection: selection) {
            header
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 0) { link(item) }
                    .chatThreadActions(title: title(item), actions: actions(item),
                                       controller: controllers.controller(for: item.id))
                    .tag(item.id)
                    .listRowInsets(theme.spacing.rowInsets)
            }
            footer
        }
        #if os(macOS)
        .onKeyPress(.return) {
            guard let item = selectedItem, let open else { return .ignored }
            guard controllers.controller(for: item.id).isIdle else { return .handled }
            open(item)
            return .handled
        }
        .onDeleteCommand(perform: deleteSelected)
        #endif
    }

    private var selectedItem: Item? { items.first { $0.id == selection.wrappedValue } }

    #if os(macOS)
    private var deleteSelected: (() -> Void)? {
        guard let item = selectedItem else { return nil }
        let hooks = actions(item)
        let controller = controllers.controller(for: item.id)
        guard hooks.delete != nil, controller.isIdle else { return nil }
        return { controller.requestDelete(hooks) }
    }
    #endif

    @ViewBuilder private func link(_ item: Item) -> some View {
        switch navigation {
        case .host: row(item)
        case let .destination(destination):
            NavigationLink { destination(item) } label: { row(item) }
                .buttonStyle(.plain)
        }
    }
}
