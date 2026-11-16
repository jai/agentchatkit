import AgentChatCore
import SwiftUI

/// Host mutations only. Archive and Delete mean only what their supplied hooks implement.
public struct ChatThreadActions {
    public typealias Action = @MainActor () async -> Result<Void, ChatActionError>
    public var archive: Action?
    public var delete: Action?
    public var identifiers: ChatThreadActionIdentifiers
    fileprivate var hostMenu: (@MainActor () -> AnyView)?
    fileprivate var hostSwipe: (@MainActor () -> AnyView)?

    public init(archive: Action? = nil, delete: Action? = nil, identifiers: ChatThreadActionIdentifiers = .init()) {
        self.archive = archive
        self.delete = delete
        self.identifiers = identifiers
    }

    /// Keep host-specific items such as Pin or Open alongside the shared Archive/Delete controls.
    public func menuItems<Menu: View>(@ViewBuilder _ content: @escaping @MainActor () -> Menu) -> Self {
        var actions = self
        actions.hostMenu = { AnyView(content()) }
        return actions
    }

    /// The host's own swipe buttons on the row's leading edge (Pin, Dismiss), on iPhone; Archive and Delete stay on
    /// the trailing edge.
    public func leadingSwipe<Buttons: View>(@ViewBuilder _ content: @escaping @MainActor () -> Buttons) -> Self {
        var actions = self
        actions.hostSwipe = { AnyView(content()) }
        return actions
    }
}

extension View {
    /// Standalone host row. Inside ChatThreadList the list already supplies this modifier and its controller.
    public func chatThreadActions(title: String, actions: ChatThreadActions) -> some View {
        modifier(OwnedChatThreadActions(title: title, actions: actions))
    }

    /// Inside ChatThreadList the list presents the delete confirmation and the error itself (`presentsDialogs: false`).
    func chatThreadActions(title: String, actions: ChatThreadActions,
                           controller: ChatThreadActionController, presentsDialogs: Bool = true) -> some View {
        modifier(ChatThreadActionModifier(title: title, actions: actions, controller: controller,
                                          presentsDialogs: presentsDialogs))
    }
}

private struct OwnedChatThreadActions: ViewModifier {
    let title: String
    let actions: ChatThreadActions
    @State private var controller = ChatThreadActionController()

    func body(content: Content) -> some View {
        content.modifier(ChatThreadActionModifier(title: title, actions: actions, controller: controller))
    }
}

private struct ChatThreadActionModifier: ViewModifier {
    @Environment(\.chatTheme) private var theme
    let title: String
    let actions: ChatThreadActions
    let controller: ChatThreadActionController
    var presentsDialogs = true

    func body(content: Content) -> some View {
        if presentsDialogs {
            rowContent(content).chatThreadActionDialogs(title: title, actions: actions, controller: controller)
        } else {
            rowContent(content)
        }
    }

    private func rowContent(_ content: Content) -> some View {
        menuContent(swipeContent(content))
            .disabled(controller.isPending)
            .overlay(alignment: .trailing) {
                if controller.isPending {
                    ProgressView().padding(theme.spacing.sm)
                        .accessibilityLabel("Updating thread")
                        .chatIdentifier(actions.identifiers.progress)
                }
            }
    }

    /// A row with nothing to offer gets no menu: an empty one still lifts the row on a long press and stays up.
    @ViewBuilder private func menuContent(_ content: some View) -> some View {
        if actions.hostMenu != nil || actions.archive != nil || actions.delete != nil {
            content.contextMenu {
                if let menu = actions.hostMenu {
                    menu()
                    if actions.archive != nil || actions.delete != nil { Divider() }
                }
                buttons
            }
        } else {
            content
        }
    }

    @ViewBuilder private func swipeContent(_ content: Content) -> some View {
        #if os(iOS)
        if let leading = actions.hostSwipe {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { buttons }
                .swipeActions(edge: .leading, allowsFullSwipe: false) { leading() }
        } else {
            content.swipeActions(edge: .trailing, allowsFullSwipe: false) { buttons }
        }
        #else
        content
        #endif
    }

    @ViewBuilder private var buttons: some View {
        if actions.archive != nil {
            Button("Archive", systemImage: theme.symbols.archive) { controller.archive(actions) }
                .chatTextStyle(.control)
                .chatIdentifier(actions.identifiers.archive)
                .disabled(!controller.isIdle)
        }
        if actions.delete != nil {
            Button("Delete", systemImage: theme.symbols.delete, role: .destructive) { controller.requestDelete(actions) }
                .chatTextStyle(.control)
                .chatIdentifier(actions.identifiers.delete)
                .disabled(!controller.isIdle)
        }
    }
}

extension View {
    /// The delete confirmation and the failed-action alert for one thread.
    func chatThreadActionDialogs(title: String, actions: ChatThreadActions,
                                 controller: ChatThreadActionController) -> some View {
        self
            .confirmationDialog("Delete \(title)?", isPresented: Binding(
                get: { controller.isConfirmingDelete },
                set: { if !$0 { controller.dismissConfirmation() } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { controller.confirmDelete(actions) }
                    .chatTextStyle(.control)
                    .chatIdentifier(actions.identifiers.confirmDelete)
                Button("Cancel", role: .cancel) { controller.dismissConfirmation() }
                    .chatTextStyle(.control)
                    .chatIdentifier(actions.identifiers.cancelDelete)
            }
            .alert("Couldn’t update \(title)", isPresented: Binding(
                get: { controller.error != nil }, set: { if !$0 { controller.dismissError() } }
            )) {
                Button("OK") { controller.dismissError() }
                    .chatTextStyle(.control)
                    .chatIdentifier(actions.identifiers.dismissError)
            } message: {
                Text(controller.error?.message ?? "")
            }
    }
}
