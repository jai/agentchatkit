import AgentChatKit
import SwiftUI

struct DemoScreenshotsScreen: View {
    @State private var viewing = SentScreenshotViewing()
    @State private var jpegs: [Data] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: ChatSpace.md) {
            Text("Sent in order; persistence stays in this host.")
            if loaded {
                SentScreenshotStrip(key: "fixture-pictures") { [jpegs] _ in .success(jpegs) }
            }
        }
        .padding(ChatSpace.md)
        .navigationTitle("Sent screenshots")
        .presentsSentScreenshots(viewing)
        .task {
            if let png = SampleScreenshot.png(), let jpeg = ComposerImageEncoder.encode(png)?.jpeg {
                jpegs = [jpeg, jpeg]
                loaded = true
            }
        }
    }
}
