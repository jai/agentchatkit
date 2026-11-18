import AgentChatKit
import SwiftUI

/// A chat that sends videos as videos (jai/agentchatkit#4): the composer keeps a video whole, with its poster, play
/// badge and length; the sent message's strip shows it the same way, and both viewers play it.
struct DemoVideoScreen: View {
    @State private var attachments: ComposerAttachments = {
        let attachments = ComposerAttachments()
        attachments.keepsVideos = true
        return attachments
    }()
    @State private var messages = [ChatMessage(id: "hello", role: .theirs, text: "Attach a video and send it.")]
    @State private var media: [String: [SentMedia]] = [:]
    @State private var viewing = SentScreenshotViewing()
    @State private var readsEnd = true
    @State private var draft = ""
    @FocusState private var focused: Bool

    static let identifiers = SentScreenshotIdentifiers(thumbnail: { key, index in "sent-\(key)-\(index)" },
                                                       viewer: "sent-video-viewer", close: "sent-video-viewer-close")

    var body: some View {
        ChatView(messages: messages, sent: media.count, readsEnd: $readsEnd, focus: $focused) { message in
            if let items = media[message.id] {
                SentScreenshotStrip(key: message.id, identifiers: Self.identifiers) { [items] _ in .success(items) }
            }
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        } composer: {
            SessionComposer(draft: $draft, isSending: false, send: send, focused: $focused, attachments: attachments)
                .composerBar()
        }
        .presentsSentScreenshots(viewing)
        .navigationTitle("Videos")
        .toolbar {
            Button("Add sample video", systemImage: "video.badge.plus") {
                Task {
                    if let url = await SampleVideo.url() {
                        await attachments.add(video: url)
                    }
                }
            }
            .accessibilityIdentifier("demo-sample-video")
        }
    }

    private func send() {
        let taken = attachments.take().map { image in
            image.video.map { SentMedia.video(poster: image.jpeg, clip: $0) } ?? .picture(image.jpeg)
        }
        let id = "me-\(media.count)"
        let words = draft.isEmpty ? "Here it is." : draft
        draft = ""
        messages.append(ChatMessage(id: id, role: .mine, text: words, date: .now, hasExtras: !taken.isEmpty))
        media[id] = taken
    }
}
