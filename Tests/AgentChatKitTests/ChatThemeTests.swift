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

    @Test func originalIDsRemainDefaultsAndHostsCanReplaceEveryControl() {
        #expect(QueuedReplyIdentifiers().row == "queued-reply")
        #expect(ReplyStatusIdentifiers().status == "reply-status")
        #expect(ReplyStatusIdentifiers().sentTicks == "reply-ticks-1")
        #expect(ReplyStatusIdentifiers().deliveredTicks == "reply-ticks-2")
        #expect(ThreadQuestionIdentifiers<String>().waitWhat == "wait-what")
        #expect(SentScreenshotIdentifiers().thumbnail("key", 2) == "sent-screenshot")
        #expect(SentScreenshotIdentifiers().close == "sent-screenshot-viewer-close")
        #expect(ChatThreadRowIdentifiers().status == nil)
        #expect(ChatThreadRowIdentifiers().chips == nil)
        let ids = ReplyStatusIdentifiers(retry: "finder-message-retry")
        #expect(ids.retry == "finder-message-retry")
    }
}
