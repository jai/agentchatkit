import AgentChatKit
import SwiftUI

struct DemoQuestionScreen: View {
    private struct Option: Identifiable {
        let id: String
        let label: String
    }

    @State private var sending = false
    @State private var longAnswers = false
    @State private var notice = "No callback yet"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChatSpace.md) {
                ThreadQuestion(
                    question: "Which fixture should run?", context: "Both answers use the same emphasis.",
                    options: options,
                    isSending: sending, label: \.label,
                    answer: { option in invoke("Answer: \(option.id)") },
                    reply: { invoke("Reply opened") }, waitWhat: { invoke(ChatQuickReply.waitWhat.text) },
                    identifiers: DemoAdoptionSettings.customIDs
                        ? .init(question: "host-question", context: "host-question-context",
                                answer: { "answer-\($0)" }, reply: "host-reply", waitWhat: "host-wait-what") : .init()
                )
                Toggle("Hold sending", isOn: $sending)
                Toggle("Long answers", isOn: $longAnswers)
                DemoFixtureNotice(text: notice)
            }
            .padding(ChatSpace.md)
        }
        .navigationTitle("Question")
    }

    private var options: [Option] {
        [Option(id: "phone", label: longAnswers ? "Run the complete phone fixture and review every screenshot" : "Phone"),
         Option(id: "mac", label: longAnswers ? "Run the complete Mac fixture and review every screenshot" : "Mac")]
    }

    private func invoke(_ message: String) {
        notice = message
        sending = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            sending = false
        }
    }
}

/// The same long question twice: limited to two lines, with a one-line context in a warning tone, and in full. The
/// limited question's answers keep all their lines (jai/agentchatkit#15).
struct DemoStyledQuestion: View {
    @Environment(\.chatTheme) private var theme

    private struct Option: Identifiable {
        let id: String
        let label: String
    }

    private let question = String(repeating: "Should the agent move the thread's chat onto the kit's own parts now? ", count: 4)
    private let context = "Blocked: two kit parts are missing, so the thread keeps its own chat until they ship."
    private let options = [Option(id: "yes", label: "Yes, move it now and keep the thread's history as it is"),
                           Option(id: "no", label: "No, wait until both parts ship in a release")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChatSpace.lg) {
                card("q-limited")
                    .context(role: .meta, color: theme.toneBad, lineLimit: 1)
                    .questionLineLimit(2)
                card("q-full")
            }
            .padding(ChatSpace.md)
        }
        .navigationTitle("Styled question")
    }

    private func card(_ id: String) -> ThreadQuestion<Option> {
        ThreadQuestion(question: question, context: context, options: options, label: \.label, answer: { _ in },
                       identifiers: {
                           var ids = ThreadQuestionIdentifiers<String>(
                               question: "\(id)-text", context: "\(id)-context", answer: { "\(id)-answer-\($0)" })
                           ids.container = id
                           return ids
                       }())
    }
}
