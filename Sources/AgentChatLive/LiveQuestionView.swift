import AgentChatKit
import SwiftUI

public struct LiveQuestionIdentifiers {
    public var question: ThreadQuestionIdentifiers<String>
    public var text: String?
    public var submit: String?
    public var decline: String?
    public var error: String?

    public init(question: ThreadQuestionIdentifiers<String> = .init(), text: String? = nil,
                submit: String? = nil, decline: String? = nil, error: String? = nil) {
        self.question = question
        self.text = text
        self.submit = submit
        self.decline = decline
        self.error = error
    }
}

/// Single choice without free text sends on tap. Forms with free text or multiple choices use Submit.
/// Option order follows the schema.
/// Selection is local presentation state, reset whenever elicitation/create names a different request.
public struct LiveQuestionView: View {
    public enum ChoiceBehavior: Equatable, Sendable {
        /// Follow the schema: free-text/multiple-choice forms use Submit; a plain single choice sends on tap.
        case automatic
        /// A single choice sends on tap, including any composed free text. Multiple choices still use Submit.
        case immediate
    }

    public let controls: LiveChatControls
    public var identifiers: LiveQuestionIdentifiers
    public var choiceBehavior: ChoiceBehavior

    public init(controls: LiveChatControls, identifiers: LiveQuestionIdentifiers = .init(),
                choiceBehavior: ChoiceBehavior = .automatic) {
        self.controls = controls
        self.identifiers = identifiers
        self.choiceBehavior = choiceBehavior
    }

    public var body: some View {
        if let question = controls.live.chat.question {
            LiveQuestionForm(controls: controls, question: question, identifiers: identifiers,
                             choiceBehavior: choiceBehavior)
                .id(question.requestID)
        }
    }
}

private struct LiveQuestionForm: View {
    @Environment(\.chatTheme) private var theme
    let controls: LiveChatControls
    let question: LiveQuestion
    let identifiers: LiveQuestionIdentifiers
    let choiceBehavior: LiveQuestionView.ChoiceBehavior
    @State private var selected: Set<String> = []
    @State private var text = ""

    private var options: [String] { question.options.filter { selected.contains($0.id) }.map(\.id) }
    private var words: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ThreadQuestion(question: question.message, options: question.options, isSending: controls.answering,
                           label: { option in selected.contains(option.id) ? "✓ " + option.label : option.label },
                           answer: choose, selected: { selected.contains($0.id) }, identifiers: identifiers.question)
            if question.freeText {
                TextField("Your answer", text: $text, axis: .vertical)
                    .chatTextStyle(.body)
                    .textFieldStyle(.roundedBorder)
                    .liveIdentifier(identifiers.text)
                    .disabled(controls.answering)
            }
            HStack(spacing: theme.spacing.sm) {
                if question.multiple || question.freeText {
                    Button("Submit answer") { submit() }
                        .buttonStyle(.borderedProminent)
                        .liveIdentifier(identifiers.submit)
                        .disabled(controls.answering || (options.isEmpty && words.isEmpty))
                }
                Button("Decline", role: .cancel) {
                    Task { await controls.decline(question) }
                }
                .buttonStyle(.bordered)
                .liveIdentifier(identifiers.decline)
                .disabled(controls.answering)
            }
            .chatTextStyle(.control)
            .controlSize(theme.controlSize)
            if controls.live.chat.question?.requestID == question.requestID, let error = controls.error(for: question) {
                Text(error.message).chatTextStyle(.meta).foregroundStyle(theme.toneBad)
                    .liveIdentifier(identifiers.error)
            }
        }
    }

    private func choose(_ option: LiveQuestion.Option) {
        if question.multiple {
            if selected.contains(option.id) { selected.remove(option.id) } else { selected.insert(option.id) }
        } else if question.freeText {
            selected = [option.id]
            if choiceBehavior == .immediate { submit() }
        } else {
            selected = [option.id]
            submit()
        }
    }

    private func submit() {
        let chosen = options
        let answer = question.freeText && !words.isEmpty ? words : nil
        Task { await controls.answer(question, options: chosen, text: answer) }
    }
}

extension View {
    @ViewBuilder func liveIdentifier(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}
