import AgentChatKit
import Foundation

public extension LiveChat {
    /// The chat as `ChatView` draws it, in display order. A person's bubble takes its ticks from its status; a removed
    /// one has no bubble.
    var chatMessages: [ChatMessage] {
        messages.compactMap { message in
            switch message.kind {
            case .user:
                guard message.status != .removed else {
                    return nil
                }
                return ChatMessage(
                    id: message.id, role: .mine,
                    text: ScreenshotLine.bubbleText(message.text, screenshots: message.attachments.count),
                    date: message.date, ticks: message.ticks
                )
            case .agent:
                return ChatMessage(id: message.id, role: .theirs, text: message.text, date: message.date)
            case .tool:
                return ChatMessage(id: message.id, role: .tool(name: message.toolName), text: message.text,
                                   date: message.date)
            }
        }
    }
}

public extension LiveMessage {
    /// One tick while the host has it, two once the agent does; none when it failed, was removed, or was typed
    /// elsewhere.
    var ticks: DeliveryTicks? {
        switch status {
        case .pending, .queued, .delivering: .sent
        case .delivered: .delivered
        case .failed, .removed, nil: nil
        }
    }
}

public extension LiveChatModel {
    var chatMessages: [ChatMessage] { chat.chatMessages }
}
