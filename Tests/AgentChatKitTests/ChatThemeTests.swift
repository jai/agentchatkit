import SwiftUI
import Testing
@testable import AgentChatKit

struct ChatThemeTests {
    @Test func legacyFontRemainsTheLiveFallbackForUnsetSemanticRoles() {
        var theme = ChatTheme(font: { .system($0, design: .monospaced) })
        #expect(theme.textStyle(.body).font == theme.font(.body))
        #expect(theme.textStyle(.meta).font == theme.font(.caption))
        theme.font = { .system($0, design: .serif).leading(.loose) }
        #expect(theme.textStyle(.objectTitle).font == theme.font(.headline))
        #expect(theme.textStyle(.objectTitle).resolvedFont == theme.font(.headline))
        #expect(theme.textStyle(.body).lineSpacing == nil)
        #expect(theme.textStyle(.control).font == theme.font(.body).weight(.semibold))
    }

    @Test func hostRolesKeepTheirFontAndLeadingAndLineSpacing() {
        let body = ChatTextStyle(font: .body, lineSpacing: 9, leading: .loose)
        let theme = ChatTheme(typography: ChatTypography(body: body), spacing: ChatSpacing(xs: 7, sm: 13))
        #expect(theme.textStyle(.body).resolvedFont == body.font.leading(.loose))
        #expect(theme.textStyle(.body).lineSpacing == 9)
        #expect(theme.textStyle(.meta).font == theme.font(.caption))
        #expect(theme.spacing.xs == 7)
        #expect(theme.spacing.sm == 13)
    }
    @Test func explicitHostRolesOverrideAnExistingComponentsFallback() {
        var theme = ChatTheme(font: { .system($0, design: .monospaced) })
        let originalTicks = ChatTextStyle(font: theme.font(.caption2))
        let originalQuickReply = ChatTextStyle(font: theme.font(.footnote).weight(.semibold))
        #expect(theme.textStyle(.meta, fallback: originalTicks).resolvedFont == originalTicks.resolvedFont)
        #expect(theme.textStyle(.control, fallback: originalQuickReply).resolvedFont == originalQuickReply.resolvedFont)
        theme.typography.meta = ChatTextStyle(font: .title, lineSpacing: 7, leading: .loose)
        theme.typography.control = ChatTextStyle(font: .headline)
        #expect(theme.textStyle(.meta, fallback: originalTicks).resolvedFont == Font.title.leading(.loose))
        #expect(theme.textStyle(.meta, fallback: originalTicks).lineSpacing == 7)
        #expect(theme.textStyle(.control, fallback: originalQuickReply).resolvedFont == Font.headline)
    }
}
