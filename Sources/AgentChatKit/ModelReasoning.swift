import SwiftUI

/// A chat's model and reasoning as the host holds them, and the models it can run: what `ModelReasoningChip` shows.
public struct ModelReasoning: Equatable, Sendable {
    public struct Model: Equatable, Sendable, Identifiable {
        public var id: String
        /// Its name in the Model picker.
        public var label: String
        /// Its name on the chip, where shorter than `label` ("Opus 5.5" for "Claude Opus 5.5").
        public var short: String?
        /// Its reasoning levels: empty for a model without them (Haiku); `nil` where the host doesn't know them.
        public var efforts: [Effort]?

        public init(id: String, label: String, short: String? = nil, efforts: [Effort]?) {
            self.id = id
            self.label = label
            self.short = short
            self.efforts = efforts
        }
    }

    public struct Effort: Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    /// A pick in the chip's menu, for the host to set.
    public enum Pick: Equatable, Sendable {
        case model(String)
        case effort(String)
    }

    public var models: [Model]
    public var model: String?
    public var effort: String?
    public var fast: Bool

    public init(models: [Model], model: String?, effort: String?, fast: Bool = false) {
        self.models = models
        self.model = model
        self.effort = effort
        self.fast = fast
    }

    public var current: Model? {
        models.first { $0.id == model }
    }

    /// The current model's levels: empty where it has none or the host doesn't know them, and the Reasoning picker
    /// isn't shown.
    public var efforts: [Effort] {
        current?.efforts ?? []
    }

    /// The chip's words: "Opus · high", with "fast" after them while fast mode is on, and no level for a model
    /// without them. `nil`, and no chip, with no model choices or no current model.
    public var chip: String? {
        guard !models.isEmpty, let model else {
            return nil
        }
        let name = current.map { $0.short ?? $0.label } ?? model
        let level: String? = switch current?.efforts {
        case .some(let levels): levels.first { $0.id == effort }?.label.lowercased()
        case .none: effort
        }
        return [name, level, fast ? "fast" : nil].compactMap(\.self).joined(separator: " · ")
    }
}

/// The model and reasoning a reply box offers (`SessionComposer`'s `modelPicker`): the host's `options` as it holds
/// them, and `pick`, which sets a pick and returns once the host holds the answer. The chip never shows a pick before
/// the host does: it shows the `options` passed after `pick` returns. A thrown error shows beside the chip until the
/// next pick.
public struct ModelPicker {
    public let options: ModelReasoning
    public let pick: @MainActor (ModelReasoning.Pick) async throws -> Void

    public init(options: ModelReasoning, pick: @escaping @MainActor (ModelReasoning.Pick) async throws -> Void) {
        self.options = options
        self.pick = pick
    }
}

/// A chat's model and reasoning by its reply box: "Opus · high", with "fast" while fast mode is on. A tap opens the
/// Model and Reasoning pickers; a model without levels (Haiku) has no Reasoning. While a pick is on its way the chip
/// waits, with a spinner, for the host's answer. No model choices, no chip.
public struct ModelReasoningChip: View {
    @Environment(\.chatTheme) private var theme
    public let picker: ModelPicker
    @State private var isSetting = false
    @State private var failure: String?

    public init(picker: ModelPicker) {
        self.picker = picker
    }

    public var body: some View {
        if let chip = picker.options.chip {
            HStack(spacing: ChatSpace.sm) {
                SteadyMenu(
                    picker.options, look: ChipFace.Look(words: chip, isSetting: isSetting),
                    perform: { pick in Task { await set(pick) } },
                    rows: { ModelReasoningRows(options: $0, choose: $1) }, face: { ChipFace(look: $0) }
                )
                .modifier(ChipStyle())
                .disabled(isSetting)
                .accessibilityLabel("Model and reasoning: \(chip)")
                .accessibilityIdentifier("modelReasoningChip")
                if let failure {
                    Text(failure)
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.toneBad)
                        .lineLimit(1)
                }
            }
        }
    }

    private func set(_ pick: ModelReasoning.Pick) async {
        isSetting = true
        failure = nil
        defer { isSetting = false }
        do {
            try await picker.pick(pick)
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Empty, so the same at each redraw (`AttachStyle`).
private struct ChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.plain)
    }
}

/// The chip itself: its words, and a spinner while a pick is on its way.
private struct ChipFace: View {
    struct Look: Equatable {
        let words: String
        let isSetting: Bool
    }

    @Environment(\.chatTheme) private var theme
    let look: Look

    var body: some View {
        HStack(spacing: ChatSpace.xs) {
            Text(look.words)
            if look.isSetting {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .font(theme.font(.caption2).weight(.semibold))
        .foregroundStyle(theme.inkQuiet)
        .padding(.horizontal, ChatSpace.sm)
        .padding(.vertical, ChatSpace.xs)
        .background(theme.groundFill, in: .capsule)
    }
}

/// The chip's menu: the models, and the model's levels.
private struct ModelReasoningRows: View {
    let options: ModelReasoning
    let choose: (ModelReasoning.Pick) -> Void

    var body: some View {
        Section("Model") {
            Picker("Model", selection: choice(options.model, pick: ModelReasoning.Pick.model)) {
                ForEach(options.models) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        if !options.efforts.isEmpty {
            Section("Reasoning") {
                Picker("Reasoning", selection: choice(options.effort, pick: ModelReasoning.Pick.effort)) {
                    ForEach(options.efforts) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }

    /// A picker's choice: the option as the host holds it; picking another asks the host to set it.
    private func choice(_ held: String?, pick: @escaping (String) -> ModelReasoning.Pick) -> Binding<String> {
        Binding(get: { held ?? "" }, set: { picked in
            if picked != held {
                choose(pick(picked))
            }
        })
    }
}
