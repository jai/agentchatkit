import SwiftUI

/// A question and host-defined options. IDs and answer payloads stay in the host's option type.
public struct ThreadQuestion<Option: Identifiable>: View {
    @Environment(\.chatTheme) private var theme
    @State private var taps = 0
    public var question: String?
    public var context: String?
    public var options: [Option]
    public var isSending: Bool
    public var showsQuestion: Bool
    public var showsContext: Bool
    public var identifiers: ThreadQuestionIdentifiers<Option.ID>
    private let label: (Option) -> String
    private let answer: ((Option) -> Void)?
    private let selected: ((Option) -> Bool)?
    private let reply: (() -> Void)?
    private let waitWhat: (() -> Void)?
    private var contextRole = ChatTextRole.body
    private var contextColor: Color?
    private var contextLineLimit: Int?
    private var questionLineLimit: Int?

    public init(
        question: String? = nil, context: String? = nil, options: [Option],
        isSending: Bool = false, showsQuestion: Bool = true, showsContext: Bool = true,
        label: @escaping (Option) -> String, answer: ((Option) -> Void)? = nil,
        reply: (() -> Void)? = nil, waitWhat: (() -> Void)? = nil,
        selected: ((Option) -> Bool)? = nil, identifiers: ThreadQuestionIdentifiers<Option.ID> = .init()
    ) {
        self.question = question
        self.context = context
        self.options = options
        self.isSending = isSending
        self.showsQuestion = showsQuestion
        self.showsContext = showsContext
        self.label = label
        self.answer = answer
        self.selected = selected
        self.reply = reply
        self.waitWhat = waitWhat
        self.identifiers = identifiers
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            if showsQuestion, let question {
                Text(question).chatTextStyle(.objectTitle).lineLimit(questionLineLimit)
                    .chatIdentifier(identifiers.question)
            }
            if showsContext, let context {
                Text(context).chatTextStyle(contextRole).foregroundStyle(contextColor ?? theme.inkQuiet)
                    .lineLimit(contextLineLimit)
                    .chatIdentifier(identifiers.context)
            }
            if let answer, !options.isEmpty {
                ThreadAnswerLayout(spacing: theme.spacing.sm) {
                    ForEach(options) { option in
                        Button {
                            taps += 1
                            answer(option)
                        } label: {
                            Text(label(option))
                                .frame(maxWidth: .infinity)
                        }
                        .chatTextStyle(.control)
                        .chatIdentifier(identifiers.answer(option.id))
                        .accessibilityAddTraits(selected?(option) == true ? .isSelected : [])
                        .controlSize(theme.controlSize)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(theme.ink)
                        .disabled(isSending)
                    }
                }
            }
            if reply != nil || waitWhat != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.spacing.lg) { replyButtons }
                    VStack(alignment: .leading, spacing: theme.spacing.sm) { replyButtons }
                }
            }
        }
        .foregroundStyle(theme.ink)
        .sensoryFeedback(.impact, trigger: taps)
        .modifier(QuestionContainer(identifier: identifiers.container))
    }

    /// How the context looks: a role of the host's typography, its colour (quiet ink when nil), and at most
    /// `lineLimit` lines (all of it when nil). A host shows a context's kind this way, such as a warning in its tone.
    public func context(role: ChatTextRole = .body, color: Color? = nil, lineLimit: Int? = nil) -> Self {
        var question = self
        question.contextRole = role
        question.contextColor = color
        question.contextLineLimit = lineLimit
        return question
    }

    /// At most `limit` lines of the question (all of it when nil). The answers keep their own lines: a `.lineLimit`
    /// put on the whole view from outside would cut them too.
    public func questionLineLimit(_ limit: Int?) -> Self {
        var question = self
        question.questionLineLimit = limit
        return question
    }

    @ViewBuilder private var replyButtons: some View {
        if let reply {
            Button(theme.controls.replyLabel, systemImage: theme.symbols.reply, action: reply)
                .chatControlButton(standard: .borderless)
                .chatTextStyle(.control)
                .chatIdentifier(identifiers.reply)
                .controlSize(theme.controlSize)
                .disabled(isSending)
        }
        if let waitWhat {
            WaitWhatButton(isSending: isSending, identifier: identifiers.waitWhat, send: waitWhat)
                .controlSize(theme.controlSize)
        }
    }
}

/// The question as one element, when the host names it (`ThreadQuestionIdentifiers.container`).
private struct QuestionContainer: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
