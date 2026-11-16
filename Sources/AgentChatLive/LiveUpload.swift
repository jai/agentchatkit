import AgentChatCore
import Foundation

/// A video to send with a message (`LiveChatModel.send(_:videos:)`): a file the app can read.
public struct LiveVideo: Sendable {
    public var file: URL
    public var name: String
    public var mimeType: String
    public var duration: Duration?

    public init(file: URL, name: String? = nil, mimeType: String = "video/quicktime", duration: Duration? = nil) {
        self.file = file
        self.name = name ?? file.lastPathComponent
        self.mimeType = mimeType
        self.duration = duration
    }
}

/// How far sending a message's videos has got, one video at a time: the host asked for room, the file going up
/// (a failed attempt tries again), sent. `HTTPTransport` reports no bytes, so the steps are the progress.
public enum LiveUploadStep: Equatable, Sendable {
    case asking(video: Int)
    case uploading(video: Int, attempt: Int)
    case uploaded(video: Int)
}

/// Why a video did not go: the host refused it (too large, a type it won't take), or its file would not go up.
public enum LiveUploadError: Error, Equatable, Sendable {
    case refused(String)
    case notSent(status: Int?)
    case unreadable
}

extension LiveChatModel {
    /// The tries a file gets before its message fails: a dropped connection or a host error tries again.
    static let uploadAttempts = 3

    /// A message with videos: each goes up first (`_agentchatkit/upload`, then `PUT`), and the message names them as
    /// `resource_link`s. Throws `LiveUploadError` when one does not go; the message is then not sent.
    @discardableResult
    public func send(
        _ text: String, videos: [LiveVideo], images: [MessageImage] = [], force: Bool = false,
        clientRef: String = UUID().uuidString, progress: (@MainActor (LiveUploadStep) -> Void)? = nil
    ) async throws -> String {
        var links: [JSONValue] = []
        for (index, video) in videos.enumerated() {
            links.append(try await upload(video, index: index, progress: progress))
        }
        let pictures = images.compactMap { Data(base64Encoded: $0.data) }
        var prompt = Acp.prompt(text, images: pictures).array ?? []
        prompt.append(contentsOf: links)
        let result = try await callForUpload("session/prompt", [
            "sessionId": .string(endpoint.session), "prompt": .array(prompt),
            "_meta": ["agentchatkit": ["clientRef": .string(clientRef), "force": .bool(force)]],
        ])
        return result["messageId"]?.string ?? ""
    }

    private func upload(_ video: LiveVideo, index: Int,
                        progress: (@MainActor (LiveUploadStep) -> Void)?) async throws -> JSONValue {
        guard let bytes = try? Data(contentsOf: video.file), !bytes.isEmpty else {
            throw LiveUploadError.unreadable
        }
        progress?(.asking(video: index))
        let ticket: JSONValue
        do {
            ticket = try await callForUpload("_agentchatkit/upload", [
                "sessionId": .string(endpoint.session), "name": .string(video.name),
                "mimeType": .string(video.mimeType), "size": .number(Double(bytes.count)),
            ])
        } catch let LiveRequestError.refused(_, message) {
            throw LiveUploadError.refused(message)
        }
        guard let uploadURL = ticket["uploadUrl"]?.string, let uri = ticket["uri"]?.string else {
            throw LiveUploadError.notSent(status: nil)
        }
        var status: Int?
        for attempt in 1...Self.uploadAttempts {
            progress?(.uploading(video: index, attempt: attempt))
            var request = try await uploadRequest(uploadURL, headers: ticket["headers"])
            request.httpBody = bytes
            if let (_, response) = try? await http.send(request) {
                status = response.statusCode
                if (200..<300).contains(response.statusCode) {
                    progress?(.uploaded(video: index))
                    var meta: JSONValue = [:]
                    if let duration = video.duration {
                        let components = duration.components
                        let ms = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
                        meta = ["agentchatkit": ["durationMs": .number(Double(ms))]]
                    }
                    return ["type": "resource_link", "uri": .string(uri), "name": .string(video.name),
                            "mimeType": .string(video.mimeType), "size": .number(Double(bytes.count)), "_meta": meta]
                }
                if (400..<500).contains(response.statusCode) {
                    break // The host won't take it; trying again changes nothing.
                }
            }
        }
        throw LiveUploadError.notSent(status: status)
    }

    /// A `PUT` to the ticket's URL: absolute and signed as it is, or relative to `<base>/acp` with the bearer.
    private func uploadRequest(_ uploadURL: String, headers: JSONValue?) async throws -> URLRequest {
        let isRelative = URL(string: uploadURL)?.scheme == nil
        let url = isRelative ? endpoint.acp.appendingPathComponent(uploadURL) : URL(string: uploadURL) ?? endpoint.acp
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if isRelative {
            request.setValue("Bearer \(try await currentBearer())", forHTTPHeaderField: "Authorization")
        }
        if case let .object(fields)? = headers {
            for (field, value) in fields {
                if let value = value.string { request.setValue(value, forHTTPHeaderField: field) }
            }
        }
        return request
    }
}
