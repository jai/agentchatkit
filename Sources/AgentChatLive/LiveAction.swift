import Foundation

/// What the client does after a stream ends or is refused (docs/live-protocol.md, "Refusals" and "close").
public enum LiveAction: Equatable, Sendable {
    /// Stop following: a bug, not this person's chat, or the chat is gone.
    case stop(LiveStop)
    /// Get a new bearer from the host, then try once more.
    case reauth
    /// Read every 2 s; stream again after this long.
    case read(after: Duration)
    /// Read; reconnect with back-off.
    case backoff
    /// Reconnect at once.
    case now
    /// Reconnect after this long, with no back-off.
    case after(Duration)

    /// For a refusal before the stream started.
    public static func forStatus(_ status: Int, error: String? = nil, retryAfterSeconds: Int? = nil) -> LiveAction {
        switch status {
        case 401: .reauth
        case 403: .stop(.forbidden)
        case 404: .stop(.notFound)
        case 429: .read(after: .seconds(retryAfterSeconds ?? 30))
        case 500...: .backoff
        default: .stop(error == "unsupported_version" ? .unsupportedVersion : .badRequest)
        }
    }

    /// For the server's `close` frame.
    public static func forClose(_ close: LiveClose) -> LiveAction {
        switch close.code {
        case 4000: .now
        case 4001: .reauth
        case 4003: .stop(.forbidden)
        case 4004: .stop(.gone)
        case 4029: .read(after: .milliseconds(close.retryAfterMs))
        case 4503: .after(.milliseconds(min(close.retryAfterMs, 5_000)))
        default: .backoff
        }
    }
}

/// Why a chat stopped following.
public enum LiveStop: Equatable, Sendable {
    case badRequest, unsupportedVersion, unauthorized, forbidden, notFound, gone
}

/// The protocol's timings. `standard` is the protocol's; tests shorten them.
public struct LiveTiming: Sendable {
    public var backoff: [Duration]
    /// Each back-off is this share longer or shorter, at random.
    public var jitter: Double
    /// A stream open this long starts the back-off again from the first step.
    public var backoffResetsAfter: Duration
    public var readInterval: Duration

    public init(backoff: [Duration], jitter: Double, backoffResetsAfter: Duration, readInterval: Duration) {
        self.backoff = backoff
        self.jitter = jitter
        self.backoffResetsAfter = backoffResetsAfter
        self.readInterval = readInterval
    }

    public static let standard = LiveTiming(
        backoff: [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)],
        jitter: 0.2, backoffResetsAfter: .seconds(10), readInterval: .seconds(2)
    )

    /// The wait before reconnect attempt `attempt` (0 first), before jitter.
    public func backoff(attempt: Int) -> Duration {
        backoff[min(attempt, backoff.count - 1)]
    }
}
