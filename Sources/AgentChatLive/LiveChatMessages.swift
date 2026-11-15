import AgentChatKit
import Foundation

public extension LiveChat {
    /// With LiveQueuedReplies above the composer, queued messages appear only there. chatMessages keeps its
    /// historical all-nonremoved behavior for hosts that have not adopted the strip.
    var conversationMessages: [ChatMessage] {
        chatMessages.filter { message($0.id)?.status != .queued }
    }

    /// Only the host's queued status belongs above the composer, already in the stream's display order.
    var queuedReplies: [LiveMessage] {
        messages.filter { $0.kind == .user && $0.status == .queued }
    }

    /// The legacy ChatView projection, in display order, including queued bubbles; removed messages are absent.
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
    var conversationMessages: [ChatMessage] { chat.conversationMessages }
}
