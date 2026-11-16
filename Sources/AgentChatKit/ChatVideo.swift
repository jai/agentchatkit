import AVKit
import SwiftUI

/// A video kept as a video (jai/agentchatkit#4): the file the host sends or plays, and how long it runs.
public struct ChatVideoClip: Equatable, Sendable {
    public var url: URL
    public var duration: Duration

    public init(url: URL, duration: Duration) {
        self.url = url
        self.duration = duration
    }

    /// "0:07", "1:05", "1:02:03": how a video's length reads on its thumbnail.
    public static func durationText(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        let hours = total / 3600, minutes = total % 3600 / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// What a sent strip shows: a picture, or a video by its poster frame (`SentScreenshotStrip(key:loadMedia:)`).
public enum SentMedia: Sendable {
    case picture(Data)
    case video(poster: Data, clip: ChatVideoClip)
}

/// A video's mark on its thumbnail: a play badge and its length.
struct ChatVideoBadge: View {
    let duration: Duration

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "play.fill").imageScale(.small)
            Text(ChatVideoClip.durationText(duration)).monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.55), in: .capsule)
        .padding(3)
        .accessibilityHidden(true)
    }
}

/// A video played in the viewer.
struct ChatVideoPlayer: View {
    let clip: ChatVideoClip
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let player = AVPlayer(url: clip.url)
                self.player = player
                player.play()
            }
            .onDisappear { player?.pause() }
            .accessibilityLabel("Video, \(ChatVideoClip.durationText(clip.duration))")
    }
}
