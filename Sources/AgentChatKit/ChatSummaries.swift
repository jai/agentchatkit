import FoundationModels
import SwiftUI

/// "Summarize" on a long agent reply: tap and hold the bubble (a right click on a Mac) and a short summary shows under
/// it, written on the device by Apple Intelligence. Nothing leaves the device. On by default, in every chat; the item
/// is there only for an agent reply of at least `minimumLength` characters, and only while the model is ready (Apple
/// Intelligence on, supported, downloaded). A host turns it off with `.chatSummaries(.off)`.
public struct ChatSummaries: Sendable {
    /// Whether the summarizer can run now.
    public var isAvailable: @Sendable () -> Bool
    /// The summary of a reply's words.
    public var summarize: @Sendable (String) async throws -> String
    /// The shortest reply, in characters, that offers a summary.
    public var minimumLength: Int

    public init(minimumLength: Int = 600, isAvailable: @escaping @Sendable () -> Bool,
                summarize: @escaping @Sendable (String) async throws -> String) {
        self.minimumLength = minimumLength
        self.isAvailable = isAvailable
        self.summarize = summarize
    }

    /// Apple Intelligence's on-device model (`SystemLanguageModel`), never Private Cloud Compute.
    public static let onDevice = ChatSummaries(isAvailable: { SystemLanguageModel.default.isAvailable }) { text in
        let session = LanguageModelSession(instructions: """
        Summarize the text you are given in two to four short sentences. Keep names, numbers, decisions and anything \
        the reader must do. Write plain sentences, with no preamble and no Markdown.
        """)
        return try await session.respond(to: text).content
    }

    /// No "Summarize" in any bubble.
    public static let off = ChatSummaries(isAvailable: { false }) { _ in "" }

    func offers(_ text: String) -> Bool {
        text.count >= minimumLength && isAvailable()
    }
}

public extension View {
    /// How the chats in this view summarize a long agent reply (`ChatSummaries.onDevice` unless a host says so).
    func chatSummaries(_ summaries: ChatSummaries) -> some View {
        environment(\.chatSummaries, summaries)
    }
}

extension EnvironmentValues {
    @Entry var chatSummaries: ChatSummaries = .onDevice
}

/// A reply's summary under its bubble: being written, written, or why it could not be.
enum ReplySummary: Equatable {
    case none
    case writing
    case written(String)
    case failed(String)
}

struct ReplySummaryView: View {
    @Environment(\.chatTheme) private var theme
    let summary: ReplySummary
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ChatSpace.sm) {
            Image(systemName: "apple.intelligence")
                .foregroundStyle(theme.inkQuiet)
                .accessibilityHidden(true)
            switch summary {
            case .none:
                EmptyView()
            case .writing:
                ProgressView().controlSize(.small)
                Text("Summarizing…").foregroundStyle(theme.inkQuiet)
            case let .written(words):
                Text(words).textSelection(.enabled)
            case let .failed(reason):
                Text(reason).foregroundStyle(theme.toneBad)
            }
            Spacer(minLength: 0)
            Button("Hide summary", systemImage: theme.symbols.close, action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkQuiet)
                .accessibilityIdentifier("bubble-summary-dismiss")
        }
        .font(theme.font(.footnote))
        .padding(ChatSpace.sm)
        .background(theme.groundCard, in: .rect(cornerRadius: ChatRadius.md))
        .overlay(RoundedRectangle(cornerRadius: ChatRadius.md).strokeBorder(theme.line))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bubble-summary")
        .transition(.opacity)
    }
}
