import AgentChatKit
import Testing

@MainActor
struct FoldSetTests {
    @Test func foldsAreKeptInTheStoreAndPrunedToWhatIsStillListed() {
        let store = FoldStore()
        let folds = store.open()
        folds.toggle("machine:one")
        folds.toggle("machine:two")
        folds.toggle("machine:two")
        folds.toggle("needs-you")

        let relaunched = store.open()
        #expect(relaunched.isFlipped("machine:one") && relaunched.isFlipped("needs-you"))
        #expect(!relaunched.isFlipped("machine:two"))
        relaunched.keep(only: ["needs-you", "machine:three"])
        #expect(store.folds == ["needs-you"])
        #expect(!FoldSet().isFlipped("needs-you"))
        #expect(!store.open().isFlipped("machine:one"))
        #expect(store.open().isFlipped("needs-you"))
    }
}

@MainActor
private final class FoldStore {
    var folds: [String] = []
    func open() -> FoldSet { FoldSet(load: { self.folds }, save: { self.folds = $0 }) }
}
