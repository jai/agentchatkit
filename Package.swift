// swift-tools-version: 6.2
import PackageDescription

// AgentChatKit: the chat with a coding agent, as a Swift package (README.md). PRHub, Agent Pager and FeedbackKit draw
// every agent chat with it.
let package = Package(
    name: "AgentChatKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        // Foundation alone, safe in an app extension: a message's screenshots.
        .library(name: "AgentChatCore", targets: ["AgentChatCore"]),
        // The chat: its screen, bubbles, field, attachments, Markdown and theme.
        .library(name: "AgentChatKit", targets: ["AgentChatKit"]),
    ],
    targets: [
        .target(name: "AgentChatCore"),
        .target(name: "AgentChatKit", dependencies: ["AgentChatCore"]),
        .testTarget(name: "AgentChatKitTests", dependencies: ["AgentChatKit"]),
    ]
)
