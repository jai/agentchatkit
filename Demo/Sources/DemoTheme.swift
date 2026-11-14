import AgentChatKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A look a host could give its chats: a `ChatTheme`, the tint Jai's bubbles take, and a colour scheme where the look
/// has only one. Each is set once at the root, as a host would (`.chatTheme(_:)`).
enum DemoTheme: String, CaseIterable, Identifiable {
    /// PRHub's: the system's fonts, its orange accent and GitHub's states (PRHub's DESIGN.md).
    case prHub
    /// A dark terminal: monospaced throughout, green on black, a terminal for a tool call.
    case terminal
    /// A page: serif words on warm paper, an ink-blue accent.
    case paper

    var id: Self { self }

    var label: String {
        switch self {
        case .prHub: "PR Hub"
        case .terminal: "Terminal"
        case .paper: "Paper"
        }
    }

    var tint: Color {
        switch self {
        case .prHub: Color(hex: 0xF15D34)
        case .terminal: Color(hex: 0x2EA043)
        case .paper: Color(light: 0x2B4C7E, dark: 0x7FA3D9)
        }
    }

    var colorScheme: ColorScheme? {
        self == .terminal ? .dark : nil
    }

    var chat: ChatTheme {
        switch self {
        case .prHub:
            ChatTheme(
                ink: Color(light: 0x000000, dark: 0xFFFFFF),
                inkQuiet: Color(light: 0x3C3C43, dark: 0xEBEBF5, opacity: 0.6),
                groundPage: Color(light: 0xF2F2F7, dark: 0x000000),
                groundCard: Color(light: 0xFFFFFF, dark: 0x1C1C1E),
                groundFill: Color(light: 0x767680, dark: 0x767680, opacity: 0.12, darkOpacity: 0.24),
                line: Color(light: 0x3C3C43, dark: 0x545458, opacity: 0.29, darkOpacity: 0.6),
                toneGood: Color(light: 0x1A7F37, dark: 0x3FB950),
                toneBad: Color(light: 0xCF222E, dark: 0xF85149),
                toneWaiting: Color(light: 0x9A6700, dark: 0xD29922)
            )
        case .terminal:
            ChatTheme(
                font: { ChatTheme.systemFont($0).monospaced() },
                code: { text in
                    AnyView(text.font(ChatTheme.systemFont(.footnote).monospaced())
                        .foregroundStyle(Color(hex: 0x7EE787)))
                },
                ink: Color(hex: 0xC9D1D9),
                inkQuiet: Color(hex: 0x6E7681),
                onBubble: .black,
                groundPage: Color(hex: 0x0D1117),
                groundCard: Color(hex: 0x161B22),
                groundFill: Color(hex: 0x21262D),
                line: Color(hex: 0x30363D),
                toneGood: Color(hex: 0x3FB950),
                toneBad: Color(hex: 0xF85149),
                toneWaiting: Color(hex: 0xD29922),
                symbols: {
                    var symbols = ChatTheme.Symbols()
                    symbols.toolCall = "terminal"
                    symbols.askAI = "questionmark.circle"
                    symbols.delivered = "checkmark.circle.fill"
                    symbols.attach = "plus"
                    return symbols
                }()
            )
        case .paper:
            ChatTheme(
                font: Self.serif,
                ink: Color(light: 0x2B2622, dark: 0xEDE6DA),
                inkQuiet: Color(light: 0x7A6F63, dark: 0xA39888),
                groundPage: Color(light: 0xF6F1E7, dark: 0x1E1B17),
                groundCard: Color(light: 0xFFFCF5, dark: 0x2A2621),
                groundFill: Color(light: 0xE9E1D2, dark: 0x3A342C),
                line: Color(light: 0xD8CDBA, dark: 0x4A4238),
                toneGood: Color(light: 0x3E7B3A, dark: 0x8BC48A),
                toneBad: Color(light: 0xA8322D, dark: 0xE38A84),
                toneWaiting: Color(light: 0x9A6B12, dark: 0xD9AE5F),
                symbols: {
                    var symbols = ChatTheme.Symbols()
                    symbols.toolCall = "book.closed"
                    symbols.askAI = "text.bubble"
                    return symbols
                }()
            )
        }
    }

    /// The system's serif at each style: Dynamic Type on the phone, the Mac's own sizes there.
    private static let serif: @Sendable (Font.TextStyle) -> Font = { style in
        #if os(macOS)
        let sizes: [Font.TextStyle: CGFloat] = [.body: 14, .callout: 14, .footnote: 12, .caption: 11, .caption2: 11]
        return .system(size: sizes[style] ?? 14, design: .serif)
        #else
        return .system(style, design: .serif)
        #endif
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, opacity: opacity
        )
    }

    /// One colour in light mode, another in dark.
    init(light: UInt32, dark: UInt32, opacity: Double = 1, darkOpacity: Double? = nil) {
        let lightColor = Color(hex: light, opacity: opacity)
        let darkColor = Color(hex: dark, opacity: darkOpacity ?? opacity)
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? darkColor : lightColor)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor)
        })
        #endif
    }
}
