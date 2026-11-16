@testable import AgentChatKit
import Testing

/// The chip by the reply box (`ModelReasoningChip`), on Agent Pager's fixtures for an Orca chat: Opus at high.
struct ModelReasoningTests {
    private static let levels: [ModelReasoning.Effort] = [
        .init(id: "low", label: "Low"), .init(id: "medium", label: "Medium"), .init(id: "high", label: "High"),
        .init(id: "xhigh", label: "Extra high"), .init(id: "max", label: "Max"),
    ]

    private static func options(_ model: String?, _ effort: String?, fast: Bool = false) -> ModelReasoning {
        ModelReasoning(
            models: [
                .init(id: "opus", label: "Opus", efforts: levels),
                .init(id: "sonnet", label: "Sonnet", efforts: levels),
                .init(id: "haiku", label: "Haiku", efforts: []),
                .init(id: "claude-opus-5-5", label: "Claude Opus 5.5", short: "Opus 5.5", efforts: nil),
            ],
            model: model, effort: effort, fast: fast
        )
    }

    @Test func theChipSaysTheModelAndItsLevel() {
        #expect(Self.options("opus", "high").chip == "Opus · high")
        #expect(Self.options("sonnet", "xhigh").chip == "Sonnet · extra high")
    }

    @Test func fastModeComesAfterThem() {
        #expect(Self.options("opus", "high", fast: true).chip == "Opus · high · fast")
    }

    @Test func aModelWithoutLevelsHasNoReasoning() {
        let haiku = Self.options("haiku", nil)
        #expect(haiku.chip == "Haiku")
        #expect(haiku.efforts.isEmpty)
        #expect(Self.options("opus", "high").efforts.count == 5)
    }

    @Test func aModelWhoseLevelsArentKnownShowsTheLevelAsHeldAndItsShortName() {
        let options = Self.options("claude-opus-5-5", "high")
        #expect(options.chip == "Opus 5.5 · high")
        #expect(options.efforts.isEmpty)
    }

    @Test func aModelNotInTheChoicesShowsItsID() {
        #expect(Self.options("gpt-5", nil).chip == "gpt-5")
    }

    @Test func noChoicesOrNoModelIsNoChip() {
        #expect(ModelReasoning(models: [], model: "opus", effort: "high").chip == nil)
        #expect(Self.options(nil, nil).chip == nil)
    }
}
