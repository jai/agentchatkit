import Observation
import SwiftUI

/// Which boxes on a screen Jai has opened or closed, as against how they started. Toggling is the only way to change
/// it, and that animates, so a fold can't ship without motion.
@MainActor
@Observable
public final class FoldSet {
    private var flipped: Set<String>
    /// Where the folds are kept between launches; `nil` keeps them for this screen only.
    private let saveFolds: (([String]) -> Void)?

    public init() {
        flipped = []
        saveFolds = nil
    }

    public convenience init(defaults: UserDefaults, key: String) {
        self.init(load: { defaults.stringArray(forKey: key) ?? [] }, save: { defaults.set($0, forKey: key) })
    }

    /// A host-provided store; in-memory stores can exercise the same relaunch behavior.
    public init(load: () -> [String], save: @escaping ([String]) -> Void) {
        flipped = Set(load())
        saveFolds = save
    }

    public func isFlipped(_ id: String) -> Bool {
        flipped.contains(id)
    }

    /// Forgets every fold but those in `ids`, without moving anything on screen: what they folded is gone.
    public func keep(only ids: Set<String>) {
        let kept = flipped.intersection(ids)
        guard kept != flipped else {
            return
        }
        flipped = kept
        save()
    }

    public func toggle(_ id: String) {
        withAnimation(ChatMotion.fold) {
            if flipped.remove(id) == nil {
                flipped.insert(id)
            }
        }
        save()
    }

    private func save() {
        saveFolds?(flipped.sorted())
    }
}
