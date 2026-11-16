import SwiftUI

/// What a chat's agent is doing, for a thread row's accessory: at work (with its activity), waiting on the person,
/// idle, or offline (its runner not answering).
public enum ChatAgentActivity: Equatable, Sendable {
    case working(String)
    case needsYou
    case idle
    case offline
}

/// The words for each state that has no words of its own.
public struct ChatAgentStateLabels: Sendable {
    public var needsYou = "Needs you"
    public var idle = "Idle"
    public var offline = "Offline"

    public init() {}
}

/// A thread row's agent state, in one place for every app's chat list: a spinner and the activity while it works,
/// "Needs you" in the waiting tone, or a quiet "Idle" / "Offline". Put it in `ChatThreadRow`'s accessory.
public struct ChatAgentStateLine: View {
    @Environment(\.chatTheme) private var theme
    public let activity: ChatAgentActivity
    public var labels: ChatAgentStateLabels
    public var identifier: String?

    public init(_ activity: ChatAgentActivity, labels: ChatAgentStateLabels = .init(), identifier: String? = nil) {
        self.activity = activity
        self.labels = labels
        self.identifier = identifier
    }

    public var body: some View {
        HStack(spacing: ChatSpace.xs) {
            if case .working = activity {
                ProgressView().controlSize(.mini)
            }
            Text(Self.words(activity, labels: labels))
        }
        .chatTextStyle(.meta)
        .foregroundStyle(activity == .needsYou ? theme.toneWaiting : theme.inkQuiet)
        .accessibilityElement(children: .combine)
        .chatIdentifier(identifier)
    }

    /// The line's words: the activity with an ellipsis (unless it ends with one), or the state's label.
    public static func words(_ activity: ChatAgentActivity, labels: ChatAgentStateLabels = .init()) -> String {
        switch activity {
        case let .working(doing): doing.hasSuffix("…") || doing.hasSuffix("...") ? doing : doing + "…"
        case .needsYou: labels.needsYou
        case .idle: labels.idle
        case .offline: labels.offline
        }
    }
}

/// "Load earlier" at the top of a chat, a spinner while it loads. Put it in `ChatView`'s header while there is more.
public struct ChatLoadEarlier: View {
    public let isLoading: Bool
    public var title: String
    public var identifier: String
    private let load: () -> Void

    public init(isLoading: Bool, title: String = "Load earlier", identifier: String = "chat-load-earlier",
                load: @escaping () -> Void) {
        self.isLoading = isLoading
        self.title = title
        self.identifier = identifier
        self.load = load
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button(title, action: load)
                    .chatControlButton(standard: .borderless)
            }
        }
        .chatTextStyle(.control)
        .frame(maxWidth: .infinity)
        .padding(.vertical, ChatSpace.xs)
        .accessibilityIdentifier(identifier)
    }
}
