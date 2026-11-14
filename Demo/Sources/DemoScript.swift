import AgentChatKit
import Foundation

/// What the scripted agent does for one message: tool calls and words, in order, and the same answer said plainly for
/// "Wait, what?". Nothing here reaches a network: every reply is written out below.
struct DemoReply {
    enum Step {
        /// A tool call: its row in the chat, and what the working line says while it runs.
        case tool(name: String, summary: String, activity: String)
        /// The working line alone, for a moment.
        case think(String)
        /// Words, streamed into one bubble.
        case say(String)
    }

    var steps: [Step]
    /// What "Wait, what?" answers with after it.
    var plain: String
}

enum DemoScript {
    /// The Tour's first message.
    static let greeting = """
        Hi! I'm a **scripted agent**: everything I say is written into this demo, and nothing leaves the device.

        Try one of these:

        - Ask *"How does scrolling work?"* and scroll up while I answer.
        - Ask *"Show me the Markdown"* for headings, code, a table and a task list.
        - Ask *"How do themes work?"*, then switch the theme from the toolbar.
        - Add a screenshot (the paperclip, or the toolbar's sample) and send it.
        - Change my model with the chip above the field.
        - Tap **Wait, what?** under anything I say.
        """

    /// The reply to a message of his, by what it asks about.
    static func reply(to words: String, screenshots: Int, model: String) -> DemoReply {
        let asked = words.lowercased()
        if screenshots > 0 {
            return screenshotReply(count: screenshots, words: asked)
        }
        if asked.contains("scroll") || asked.contains("follow") || asked.contains("long") {
            return scrolling
        }
        if asked.contains("markdown") || asked.contains("code") || asked.contains("table") {
            return markdown
        }
        if asked.contains("theme") || asked.contains("colour") || asked.contains("color") {
            return theming
        }
        if asked.contains("model") || asked.contains("reasoning") {
            return modelReply(model)
        }
        return general
    }

    private static let general = DemoReply(
        steps: [
            .think("Reading the question"),
            .tool(name: "Grep", summary: "\"ChatView(\" in Sources/", activity: "Searching the package"),
            .tool(name: "Read", summary: "Sources/AgentChatKit/ChatView.swift", activity: "Reading ChatView.swift"),
            .say("""
                `ChatView` is the whole chat screen. A host gives it:

                1. its **messages**, oldest first, as `ChatMessage`s (yours, mine, and tool calls like the two above);
                2. **slots** for what only the host has: a `header`, `extras` under a message, a `footer` (this \
                demo's working line lives there) and the `composer`.

                Everything else, the bubbles, the Markdown, keeping you at the end as I write, is the package's.
                """),
        ],
        plain: """
            **The short version:** you hand `ChatView` a list of messages, and it draws the chat.

            - Your app owns the conversation.
            - The package owns how it looks and scrolls.
            - Slots let your app add its own bits.
            """
    )

    private static let scrolling = DemoReply(
        steps: [
            .tool(name: "Read", summary: "Sources/AgentChatKit/ChatFollow.swift", activity: "Reading ChatFollow.swift"),
            .think("Writing a long answer on purpose"),
            .say((1...14).map { part in
                """
                **Part \(part).** While you're at the end of the chat, the page follows the newest words as they \
                arrive, laid out before the frame is drawn so nothing jumps. Scroll up now and it stops following: \
                you stay exactly where you are while this keeps growing below you. Scroll back to the end and it \
                follows again.
                """
            }.joined(separator: "\n\n")),
        ],
        plain: """
            **At the end, it follows. Scrolled up, it stays put.**

            - Reading the end: new words keep you at the end.
            - Scrolled up: you stay where you are.
            - Sending a message: the chat jumps to the end.
            """
    )

    private static let markdown = DemoReply(
        steps: [
            .tool(name: "Read", summary: "Sources/AgentChatKit/MarkdownBlocks.swift",
                  activity: "Reading MarkdownBlocks.swift"),
            .say("""
                ## What an agent's Markdown looks like

                Inline: **bold**, *italic*, `code`, ~~struck~~ and [a link](https://github.com/jai/agentchatkit).

                > A quote, with its bar.

                ```swift
                ChatView(messages: messages, sent: sent, readsEnd: $readsEnd, focus: $focused) { _ in
                    EmptyView()
                } header: { EmptyView() } footer: { EmptyView() } composer: { composer }
                ```

                | Piece | Whose |
                |---|---|
                | Bubbles, Markdown, scrolling | the package |
                | Messages, slots, theme | the host |

                1. Stream a reply
                2. Show tool calls
                3. Ship your own app
                """),
        ],
        plain: """
            **I showed every kind of formatting a reply can have.**

            - Headings, bold, code and links.
            - A code block and a table.
            - A numbered list.
            """
    )

    private static let theming = DemoReply(
        steps: [
            .tool(name: "Read", summary: "Sources/AgentChatKit/ChatTheme.swift", activity: "Reading ChatTheme.swift"),
            .say("""
                A chat takes its **fonts, colours and icons** from `ChatTheme`, which the host sets once at its root:

                ```swift
                RootView().chatTheme(ChatTheme(font: { .app($0) }, toneGood: .green))
                ```

                This demo has three: **PR Hub** (PRHub's own look), **Terminal** and **Paper**. Switch them from the \
                toolbar: the same chat redraws in each, and the package knows nothing about any of them.
                """),
        ],
        plain: """
            **Your app picks the fonts and colours; the chat follows.**

            - Set `.chatTheme(...)` once at the top of your app.
            - Try the toolbar's Theme menu to see it change.
            """
    )

    private static func modelReply(_ model: String) -> DemoReply {
        DemoReply(
            steps: [
                .say("""
                    I'm answering as **\(model)**. The chip above the field picks the model and its reasoning. The \
                    chip waits for the host to say the change took, so it never shows a pick the agent doesn't have. \
                    The time under each of my replies says which model wrote it.
                    """),
            ],
            plain: """
                **Tap the chip above the field to change my model.**

                - It shows what's in use now.
                - Each reply notes which model wrote it.
                """
        )
    }

    private static func screenshotReply(count: Int, words: String) -> DemoReply {
        let pictures = count == 1 ? "the screenshot" : "the \(count) screenshots"
        return DemoReply(
            steps: [
                .tool(name: "View", summary: count == 1 ? "screenshot-1.jpg" : "screenshot-1…\(count).jpg",
                      activity: "Looking at \(pictures)"),
                .say("""
                    Got \(pictures). Each one was made small enough for me to read whole before it was sent \
                    (at most \(ComposerImageEncoder.maxPixels) px on its long side), and your bubble says it went with \
                    the message rather than showing the pictures again.
                    """),
            ],
            plain: """
                **I received \(pictures).**

                - They were shrunk before sending.
                - Your bubble notes they were attached.
                """
        )
    }

    /// The Long chat's history: enough of it that the page scrolls a long way, with tool calls among the words.
    static func longHistory(now: Date) -> [ChatMessage] {
        let topics = [
            "the scroll position", "the composer's height", "a table's width", "the tick colours", "Dynamic Type",
            "the Mac's text size", "pasting a screenshot", "a tool call's row", "the working line", "the model chip",
            "a code block", "the keyboard", "an iPad's width", "a quote's bar", "Wait, what?",
        ]
        var messages: [ChatMessage] = []
        for (index, topic) in topics.enumerated() {
            let date = now.addingTimeInterval(Double(index - topics.count) * 300)
            messages.append(ChatMessage(
                id: "long-me-\(index)", role: .mine, text: "Can you check \(topic)?", date: date, ticks: .delivered
            ))
            messages.append(ChatMessage(
                id: "long-tool-\(index)", role: .tool(name: "Read"), text: "Sources/AgentChatKit/… for \(topic)"
            ))
            messages.append(ChatMessage(
                id: "long-them-\(index)", role: .theirs,
                text: "Checked **\(topic)**: it behaves as described. Nothing to change, and I added a note so it "
                    + "stays that way.\n\n- Looked at the code\n- Ran it on a phone and a Mac",
                date: date.addingTimeInterval(60)
            ))
        }
        return messages
    }
}
