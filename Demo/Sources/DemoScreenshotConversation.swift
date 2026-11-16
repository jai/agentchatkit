import AgentChatKit
import SwiftUI

/// A long conversation whose newest message carries portrait screenshots that load a moment after it shows, so the
/// chat scrolls to its end while the strip appears: where a thumbnail's accessibility frame was left behind on the Mac.
struct DemoScreenshotConversation: View {
    @State private var viewing = SentScreenshotViewing()
    @State private var readsEnd = true
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let messages: [ChatMessage] = (0..<24).map { index in
        ChatMessage(id: "m\(index)", role: index.isMultiple(of: 2) ? .theirs : .mine,
                    text: "Message \(index + 1) of the conversation before the screenshots.")
    } + [ChatMessage(id: "shots", role: .mine, text: "Here is what I see.", hasExtras: true)]

    var body: some View {
        ChatView(messages: messages, sent: messages.count, readsEnd: $readsEnd, focus: $focused) { message in
            if message.id == "shots" {
                SentScreenshotStrip(key: "conversation", identifiers: DemoAdoptionSettings.screenshotIDs) { _ in
                    try? await Task.sleep(for: .milliseconds(400))
                    let jpeg = await MainActor.run {
                        SampleScreenshot.png(portrait: true).flatMap { ComposerImageEncoder.encode($0)?.jpeg }
                    }
                    return .success(jpeg.map { [$0, $0] } ?? [])
                }
            }
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        } composer: {
            SessionComposer(draft: $draft, isSending: false, send: {}, focused: $focused)
                .composerBar()
        }
        .presentsSentScreenshots(viewing)
        .navigationTitle("Screenshots in a conversation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
