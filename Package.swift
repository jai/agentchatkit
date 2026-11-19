// swift-tools-version: 6.2
import PackageDescription

// AgentChatKit: the chat with a coding agent, as a Swift package (README.md). PRHub, Agent Pager and FeedbackKit draw
// every agent chat with it, and follow it live with AgentChatLive (docs/live-protocol.md).
let package = Package(
    name: "AgentChatKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        // Foundation alone, safe in an app extension: a message's screenshots.
        .library(name: "AgentChatCore", targets: ["AgentChatCore"]),
        // The chat: its screen, bubbles, field, attachments, Markdown and theme.
        .library(name: "AgentChatKit", targets: ["AgentChatKit"]),
        // Follows a chat live, on DurableNetworking: stream, reconnect, read while down, one cursor.
        .library(name: "AgentChatLive", targets: ["AgentChatLive"]),
        // A live chat server in memory, for tests, previews and the demo.
        .library(name: "AgentChatLiveTesting", targets: ["AgentChatLiveTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jai/durable-networking", from: "0.1.0"),
    ],
    targets: [
        .target(name: "AgentChatCore"),
        .target(name: "AgentChatKit", dependencies: ["AgentChatCore"]),
        .target(name: "AgentChatLive", dependencies: [
            "AgentChatKit", .product(name: "DurableNetworking", package: "durable-networking"),
        ]),
        .target(name: "AgentChatLiveTesting", dependencies: [
            "AgentChatLive", .product(name: "DurableNetworking", package: "durable-networking"),
        ]),
        .testTarget(name: "AgentChatKitTests", dependencies: ["AgentChatKit"], path: "Tests/AgentChatKitTests/Unit"),
        .testTarget(name: "AgentChatKitIntegrationTests", dependencies: ["AgentChatKit"],
                    path: "Tests/AgentChatKitTests/Integration"),
        .testTarget(name: "AgentChatLiveUnitTests", dependencies: ["AgentChatLive"]),
        .testTarget(name: "AgentChatLiveIntegrationTests", dependencies: [
            "AgentChatLive", "AgentChatLiveTesting",
            .product(name: "DurableNetworking", package: "durable-networking"),
        ], path: "Tests/AgentChatLiveTests"),
    ]
)
