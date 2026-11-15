import AgentChatKit
import SwiftUI

/// Deterministic launch settings used only by the shared-piece fixtures and their capture tests.
enum DemoAdoptionSettings {
    static var fixture: String? { UserDefaults.standard.string(forKey: "DemoFixture") }
    static var customIDs: Bool { UserDefaults.standard.bool(forKey: "DemoCustomIDs") }
    static var appearance: String? { UserDefaults.standard.string(forKey: "DemoAppearance") }
    static var large: Bool { appearance == "large" }

    static var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": .dark
        case "light", "large": .light
        default: nil
        }
    }

    static func theme(_ base: ChatTheme) -> ChatTheme {
        guard fixture != nil else { return base }
        var theme = base
        guard !UserDefaults.standard.bool(forKey: "DemoLegacyTypography") else { return theme }
        // A host family and metrics, rather than a package-owned point size. Mac large text is host-owned.
        #if os(macOS)
        let meta: Font.TextStyle = large ? .title3 : .caption
        let title: Font.TextStyle = large ? .largeTitle : .title2
        let body: Font.TextStyle = large ? .title : .body
        let control: Font.TextStyle = large ? .title2 : .body
        #else
        let meta: Font.TextStyle = .caption
        let title: Font.TextStyle = .title2
        let body: Font.TextStyle = .body
        let control: Font.TextStyle = .body
        #endif
        theme.typography = ChatTypography(
            meta: .init(font: .system(meta, design: .monospaced), lineSpacing: ChatSpace.xs, leading: .loose),
            objectTitle: .init(font: .system(title, design: .serif).bold(), leading: .loose),
            body: .init(font: .system(body, design: .serif), lineSpacing: ChatSpace.sm, leading: .loose),
            control: .init(font: .system(control).weight(.semibold), leading: .standard)
        )
        theme.spacing = ChatSpacing(xs: ChatSpace.sm, sm: ChatSpace.md, md: ChatSpace.lg, lg: ChatSpace.lg)
        return theme
    }

    static func rowIDs(_ id: String) -> ChatThreadRowIdentifiers {
        customIDs ? .init(row: id == "context" ? "thread-line" : "sessionRow-\(id)", context: "context-\(id)", title: "title-\(id)",
                          titleMark: "mark-\(id)", about: "about-\(id)",
                          status: id == "fallback" ? "configured-status-fallback" : nil,
                          chips: id == "fallback" ? "configured-chip-fallback" : nil) : .init()
    }

    static func actionIDs(_ id: String) -> ChatThreadActionIdentifiers {
        customIDs ? .init(archive: "archive-\(id)", delete: "delete-\(id)", confirmDelete: "confirm-\(id)",
                          cancelDelete: "cancel-\(id)", dismissError: "dismiss-\(id)", progress: "pending-\(id)") : .init()
    }

    static var screenshotIDs: SentScreenshotIdentifiers {
        customIDs ? .init(thumbnail: { key, index in "picture-\(key)-\(index)" },
                          viewer: "host-viewer", close: "viewer-close") : .init()
    }
}
