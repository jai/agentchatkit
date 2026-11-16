@testable import AgentChatLive
import AgentChatLiveTesting
import Foundation
import Testing

/// A message with a video, through the dev host: room asked for, the file put, the message naming it
/// (jai/agentchatkit#4).
@Suite(.enabled(if: LiveHostSuites.run, "AGENTCHAT_LIVE_TESTS=off"))
@MainActor
struct LiveUploadTests {
    private let server = LiveDevHost()

    @Test func aVideoGoesUpAndTheMessageNamesIt() async throws {
        let live = LiveChatModel(
            endpoint: LiveEndpoint(acp: server.acp, session: server.session, bearer: { _ in "token" }),
            http: server, streams: server, kept: LiveChat(),
            timing: LiveTiming(backoff: [.milliseconds(1)], jitter: 0, backoffResetsAfter: .seconds(10),
                               answerLimit: .seconds(2))
        )
        let following = Task { await live.follow() }
        defer { following.cancel() }
        for _ in 0..<400 where live.phase != .live { try await Task.sleep(for: .milliseconds(5)) }
        #expect(live.phase == .live)

        let bytes = Data((0..<2048).map { UInt8($0 % 251) })
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var steps: [LiveUploadStep] = []
        let id = try await live.send("Here it is.", videos: [
            LiveVideo(file: file, name: "clip.mp4", mimeType: "video/mp4", duration: .seconds(3)),
        ]) { steps.append($0) }
        #expect(steps == [.asking(video: 0), .uploading(video: 0, attempt: 1), .uploaded(video: 0)])

        for _ in 0..<400 where live.chat.message(id)?.attachments.isEmpty != false {
            try await Task.sleep(for: .milliseconds(5))
        }
        let attachment = try #require(live.chat.message(id)?.attachments.first)
        #expect(attachment.mimeType == "video/mp4")
        #expect(attachment.durationMs == 3000)
        #expect(attachment.uri.hasPrefix("files/"))

        var get = URLRequest(url: server.acp.appendingPathComponent(attachment.uri))
        get.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        let (back, response) = try await server.send(get)
        #expect(response.statusCode == 200)
        #expect(back == bytes)
    }
}
