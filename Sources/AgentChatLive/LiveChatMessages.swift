import AgentChatKit
import Foundation

public extension LiveChat {
    /// The chat as `ChatView` draws it: its messages in display order, then the person's replies not yet in it. Each
    /// of the person's bubbles takes its ticks from its reply; a failed or removed one has none, and the host says why
    /// from `reply(for:)`.
    var chatMessages: [ChatMessage] {
        messages.map { message in
            switch message.role {
            case .user:
                ChatMessage(
                    id: message.id, role: .mine,
                    text: ScreenshotLine.bubbleText(message.text, screenshots: message.images.count),
                    date: message.date, ticks: reply(for: message).flatMap(\.ticks) ?? nil
                )
            case .assistant:
                ChatMessage(id: message.id, role: .theirs, text: message.text, date: message.date)
            case .tool:
                ChatMessage(id: message.id, role: .tool(name: message.tool), text: message.text, date: message.date)
            }
        } + outstanding.map { reply in
            ChatMessage(
                id: reply.id, role: .mine, text: ScreenshotLine.bubbleText(reply.text, screenshots: reply.images.count),
                date: reply.at.flatMap(LiveDates.parse), ticks: reply.ticks
            )
        }
    }
}

public extension LiveReply {
    /// One tick while the host has it, two once the agent does; none when it failed or was taken back.
    var ticks: DeliveryTicks? {
        switch status {
        case .pending, .queued, .delivering: .sent
        case .delivered: .delivered
        case .failed, .removed: nil
        }
    }
}

public extension LiveChatModel {
    var chatMessages: [ChatMessage] { chat.chatMessages }
}
