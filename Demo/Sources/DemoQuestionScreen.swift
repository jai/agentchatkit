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
