import SwiftUI

/// Native rows, selection and actions. Host route values never enter the kit's navigation domain.
public struct ChatThreadList<Item: Identifiable, Row: View, Destination: View>: View {
    @Environment(\.chatTheme) private var theme
    @State private var localSelection: Item.ID?
    @State private var controllers = ChatThreadActionStore<Item.ID>()
    /// Stands in while no row is confirming or showing an error, so the list keeps its modifiers.
    @State private var noDialog = ChatThreadActionController()
    public var items: [Item]
    private let title: (Item) -> String
    private let rowIdentifier: (Item) -> String?
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
        rowIdentifier: @escaping (Item) -> String? = { _ in nil },
        selection: Binding<Item.ID?>? = nil, open: ((Item) -> Void)? = nil,
        @ViewBuilder row: @escaping (Item) -> Row, @ViewBuilder destination: @escaping (Item) -> Destination
    ) {
        self.items = items
        self.title = title
        self.rowIdentifier = rowIdentifier
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
        rowIdentifier: @escaping (Item) -> String? = { _ in nil },
        selection: Binding<Item.ID?>? = nil, open: ((Item) -> Void)? = nil,
        @ViewBuilder row: @escaping (Item) -> Row,
        @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer
    ) where Destination == EmptyView {
        self.items = items
        self.title = title
        self.rowIdentifier = rowIdentifier
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
        let dialog = dialogItem
        nativeList
            // The list, not the row, presents these: on iPhone a row's dialog is anchored to its cell, and removing
            // that row after Delete crashed UICollectionView ("invalid number of items in section").
            .chatThreadActionDialogs(title: dialog.map(title) ?? "",
                                     actions: dialog.map(actions) ?? ChatThreadActions(),
                                     controller: dialog.map { controllers.controller(for: $0.id) } ?? noDialog)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.groundPage)
            .onChange(of: items.map(\.id)) { _, ids in
                controllers.retain(Set(ids))
                if let selected = selection.wrappedValue, !ids.contains(selected) { selection.wrappedValue = nil }
            }
    }

    private var nativeList: some View {
        selectableList
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

    /// On iPhone a selection-bound List takes a host NavigationLink(value:) whose value has the item ID's type as a
    /// selection instead of pushing it, so rows that hold the host's own links get no List selection there.
    @ViewBuilder private var selectableList: some View {
        #if os(iOS)
        if case .host = navigation {
            List { rows }
        } else {
            List(selection: selection) { rows }
        }
        #else
        List(selection: selection) { rows }
        #endif
    }

    /// The host's header and footer sit in sections of their own: in one section with the rows, removing a row while
    /// its menu or dialog closes made UICollectionView's item count disagree and crash the app on iPhone.
    @ViewBuilder private var rows: some View {
        Section { header }
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 0) { link(item) }
                    .chatThreadActions(title: title(item), actions: actions(item),
                                       controller: controllers.controller(for: item.id), presentsDialogs: false)
                    .tag(item.id)
                    .listRowInsets(theme.spacing.rowInsets)
            }
        }
        Section { footer }
    }

    /// The row whose delete confirmation or failure is showing.
    private var dialogItem: Item? {
        items.first {
            let controller = controllers.controller(for: $0.id)
            return controller.isConfirmingDelete || controller.error != nil
        }
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
        case .host: row(item).chatIdentifier(rowIdentifier(item))
        case let .destination(destination):
            NavigationLink { destination(item) } label: { row(item) }
                .buttonStyle(.plain)
                .chatIdentifier(rowIdentifier(item))
        }
    }
}
