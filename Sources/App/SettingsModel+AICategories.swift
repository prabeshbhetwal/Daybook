import Foundation
import FoundationModels

/// What the Settings row "Let AI assign categories to automatic sessions" reads beside the person's own
/// settings (Phase C, rulings C8, C14, C19 and C20). The app hands in its own; checks hand in preferences in
/// memory, a scratch label file and the model's availability.
struct AICategorySource {
    /// The switch, in preferences a backup leaves out (C19).
    let setting: AIAssignSetting
    /// The label file the assistant keeps: the tally and why it cannot be written. Nil without an assistant.
    let labels: AILabelStore?
    /// Read on every call: the model can come and go while the app runs.
    var modelAvailable: () -> Bool = { ModelGate.modelAvailable }
    /// Why the model is not there, read only when `modelAvailable` says so; checks hand in a stand-in (C22).
    var unavailableReason: () -> String = { AICategorySource.liveUnavailableReason }
    /// What time it is, for which labels are still in use; checks hand in their own.
    var now: () -> Date = { Date() }

    /// In the words Ask uses for the same model.
    static var liveUnavailableReason: String {
        if #available(macOS 26, *), let notice = AskModel.notice(for: SystemLanguageModel.default.availability) {
            return notice.text
        }
        return noModelReason
    }

    static let noModelReason = "This Mac can't run on-device AI. The rest of Daybook works as usual."
}

/// The AI category row's values, so the Settings group only draws them and binds the switch.
extension SettingsModel {
    /// "Let AI assign categories to automatic sessions". Off where nothing was handed in to keep it. Written
    /// through `write`, so the refresh takes shadow mode's offers away, or brings them back, at once.
    var aiAssignsCategories: Bool {
        get { aiCategories?.setting.isOn ?? false }
        set { write { aiCategories?.setting.isOn = newValue } }
    }

    /// Why the switch cannot be used now, or nil when it can: the model is not there to answer, as the source
    /// says, or the person turned on-device AI off.
    var aiAssignDisabledReason: String? {
        guard let source = aiCategories else { return AICategorySource.noModelReason }
        guard source.modelAvailable() else { return source.unavailableReason() }
        return useAppleIntelligence ? nil : "Turn on Use on-device AI in Settings › Privacy & Data to let it assign categories."
    }

    /// "AI matched 17 of your last 20 choices", or nil where there is no label file.
    var aiTallyText: String? { aiCategories?.labels?.book.tallyText() }

    /// Why the label file is not being written, shown beside the switch. Until it is fixed nothing is asked.
    var aiLabelsFailure: String? { aiCategories?.labels?.failure }

    /// What the category editor checks a name against: every category, Unsorted and each AI label still in use,
    /// as Keep and Rename on a label do (C32).
    var namedCategories: [WorkTypeDefinition] {
        WorkTypeCatalog.namedDefinitions(besides: aiCategories.map { $0.labels?.book.liveLabels(now: $0.now()) ?? [] } ?? [])
    }
}
