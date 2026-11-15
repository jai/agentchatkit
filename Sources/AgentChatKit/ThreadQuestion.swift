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
    private let label: (Option) -> String
    private let answer: ((Option) -> Void)?
    private let reply: (() -> Void)?
    private let waitWhat: (() -> Void)?

    public init(
        question: String? = nil, context: String? = nil, options: [Option],
        isSending: Bool = false, showsQuestion: Bool = true, showsContext: Bool = true,
        label: @escaping (Option) -> String, answer: ((Option) -> Void)? = nil,
        reply: (() -> Void)? = nil, waitWhat: (() -> Void)? = nil
    ) {
        self.question = question
        self.context = context
        self.options = options
        self.isSending = isSending
        self.showsQuestion = showsQuestion
        self.showsContext = showsContext
        self.label = label
        self.answer = answer
        self.reply = reply
        self.waitWhat = waitWhat
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ChatSpace.sm) {
            if showsQuestion, let question {
                Text(question).font(theme.font(.headline))
            }
            if showsContext, let context {
                Text(context).font(theme.font(.subheadline)).foregroundStyle(theme.inkQuiet)
            }
            if let answer, !options.isEmpty {
                ThreadAnswerLayout {
                    ForEach(options) { option in
                        Button {
                            taps += 1
                            answer(option)
                        } label: {
                            Text(label(option))
                                .font(theme.font(.headline))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(theme.ink)
                        .disabled(isSending)
                    }
                }
            }
            if reply != nil || waitWhat != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ChatSpace.lg) { replyButtons }
                    VStack(alignment: .leading, spacing: ChatSpace.sm) { replyButtons }
                }
            }
        }
        .foregroundStyle(theme.ink)
        .sensoryFeedback(.impact, trigger: taps)
    }

    @ViewBuilder private var replyButtons: some View {
        if let reply {
            Button("Reply", systemImage: theme.symbols.compose, action: reply)
                .buttonStyle(.borderless)
                .font(theme.font(.footnote).weight(.semibold))
                .disabled(isSending)
        }
        if let waitWhat { WaitWhatButton(isSending: isSending, send: waitWhat) }
    }
}
