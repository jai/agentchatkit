import SwiftUI

/// The agent at work, under the chat's messages: a small spinner and what it is doing now ("Searching threads…").
/// One line for every chat, so all of them show work the same way. Put it in `ChatView`'s footer while the agent works;
/// the activity changes in place.
public struct ChatWorkingLine: View {
    @Environment(\.chatTheme) private var theme
    public let activity: String
    public let identifier: String

    /// - Parameters:
    ///   - activity: What the agent is doing ("Working" when the host knows no more). The line adds an ellipsis unless
    ///     the words end with one.
    ///   - identifier: The line's accessibility identifier, for a host's UI tests.
    public init(activity: String = "Working", identifier: String = "chat-working") {
        self.activity = activity
        self.identifier = identifier
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ChatSpace.sm) {
            ChatSpinner(style: .footnote)
            Text(activity.hasSuffix("…") || activity.hasSuffix("...") ? activity : activity + "…")
                .font(theme.font(.footnote))
                .foregroundStyle(theme.inkQuiet)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, ChatSpace.md)
        .animation(ChatMotion.swap, value: activity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
