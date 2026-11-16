import AgentChatKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// One chat, as a host draws it with AgentChatKit: `ChatView` with the host's slots filled. The footer is the agent at
/// work; the extras are the screenshots a message took; the composer has the paperclip and the model chip.
struct DemoChatScreen: View {
    @Environment(\.chatTheme) private var theme
    @Bindable var chat: DemoChat
    @Binding var themeChoice: DemoTheme
    @State private var readsEnd = true
    @FocusState private var focused: Bool

    var body: some View {
        ChatView(
            messages: chat.messages, sent: chat.sentCount, readsEnd: $readsEnd, focus: $focused,
            waitWhat: chat.isWorking ? nil : { chat.send(ChatQuickReply.waitWhat.text) },
            isSending: chat.isSending
        ) { message in
            if let pictures = chat.screenshots[message.id] {
                Thumbnails(pictures: pictures)
            }
        } header: {
            EmptyView()
        } footer: {
            if let activity = chat.activity {
                ChatWorkingLine(activity: activity, identifier: "demo-activity")
            }
        } composer: {
            SessionComposer(
                draft: $chat.draft, isSending: chat.isSending, send: chat.sendDraft, focused: $focused,
                attachments: chat.attachments,
                modelPicker: ModelPicker(options: chat.options, pick: chat.pick)
            )
            .composerBar()
        }
        .background(theme.groundPage)
        .navigationTitle(chat.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                Button("Add sample screenshot", systemImage: "photo.badge.plus") {
                    if let png = SampleScreenshot.png() {
                        Task { await chat.attachments.add(png) }
                    }
                }
                .accessibilityIdentifier("demo-sample-screenshot")
                Menu("Theme", systemImage: "paintpalette") {
                    Picker("Theme", selection: $themeChoice) {
                        ForEach(DemoTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                .accessibilityIdentifier("demo-theme")
            }
        }
    }
}

/// The footer while the agent works: a spinner and what it is doing ("Reading ChatView.swift").

/// The screenshots that went with a message, small, under its bubble.
private struct Thumbnails: View {
    let pictures: [Data]

    var body: some View {
        HStack(spacing: ChatSpace.xs) {
            ForEach(pictures.indices, id: \.self) { index in
                if let image = Self.image(pictures[index]) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: ChatRadius.md))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func image(_ data: Data) -> Image? {
        #if os(iOS)
        UIImage(data: data).map(Image.init(uiImage:))
        #else
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}
