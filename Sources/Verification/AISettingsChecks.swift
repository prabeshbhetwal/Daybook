import Combine
import Foundation

/// The Settings row for AI categories (Phase C, rulings C14, C19 and C20): the assigning switch kept in its own
/// preference, disabled with a reason while on-device AI is off or missing, the tally line, the label file's
/// failure, and a category kept from a session report reaching an open Settings window.
enum AISettingsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The assigning switch in Settings reads and writes its own preference", switchRoundTrips),
        ("The assigning switch is disabled with a reason while on-device AI is off or missing", switchExplainsWhyNot),
        ("Settings shows the tally line and why the label file is not written", showsTallyAndFailure),
        ("A label kept from a session report reaches an open Settings window's categories", keptLabelReachesSettings),
    ]

    /// A Settings model over preferences in memory, the switch's source on the same preferences.
    private static func withSettings(labels: AILabelStore? = nil, modelAvailable: Bool = true,
                                     _ body: (SettingsModel, UserDefaults, inout [String]) -> Void) -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-ai-settings-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let settings = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.aiCategories = AICategorySource(setting: AIAssignSetting(defaults: defaults), labels: labels,
                                                 modelAvailable: { modelAvailable },
                                                 unavailableReason: { "No model in this check." })
        body(settings, defaults, &problems)
        return problems
    }

    private static func switchRoundTrips() -> [String] {
        withSettings { settings, defaults, problems in
            expect(!settings.aiAssignsCategories, "assigning was on before the person turned it on", &problems)
            var announced = 0
            let watch = settings.objectWillChange.sink { announced += 1 }
            settings.aiAssignsCategories = true
            watch.cancel()
            expect(AIAssignSetting(defaults: defaults).isOn, "turning the switch on did not reach its preference", &problems)
            expect(settings.aiAssignsCategories && announced > 0,
                   "the switch did not read back on, or Settings was not told (\(announced))", &problems)
            AIAssignSetting(defaults: defaults).isOn = false
            expect(!settings.aiAssignsCategories, "the switch did not follow its preference", &problems)
        }
    }

    private static func switchExplainsWhyNot() -> [String] {
        var problems = withSettings { settings, _, problems in
            settings.useAppleIntelligence = false
            let reason = settings.aiAssignDisabledReason ?? ""
            expect(reason.contains("on-device AI"), "with on-device AI off the switch gave no reason: \(reason)", &problems)
            settings.useAppleIntelligence = true
            expect(settings.aiAssignDisabledReason == nil,
                   "with on-device AI on the switch stayed disabled: \(String(describing: settings.aiAssignDisabledReason))", &problems)
        }
        problems += withSettings(modelAvailable: false) { settings, _, problems in
            settings.useAppleIntelligence = true
            expect(settings.aiAssignDisabledReason?.isEmpty == false, "without the model the switch gave no reason", &problems)
        }
        return problems
    }

    private static func showsTallyAndFailure() -> [String] {
        let folder = SelfTest.scratchDirectory()
        let labels = AILabelStore(directory: folder)
        var problems = withSettings(labels: labels) { settings, _, problems in
            expect(settings.aiTallyText == "No choices to compare yet",
                   "an empty tally read \(String(describing: settings.aiTallyText))", &problems)
            var book = labels.book
            let record = UUID()
            book.tallyAnswer(.pick(WorkType.admin.rawValue), recordID: record)
            book.recordChoice(recordID: record, chosen: WorkType.admin.rawValue)
            expect(labels.save(book, at: SelfTest.base) == nil, "the tally was not saved", &problems)
            expect(settings.aiTallyText == "AI matched your last choice",
                   "the tally line read \(String(describing: settings.aiTallyText))", &problems)
            expect(settings.aiLabelsFailure == nil, "a label file that saves showed a failure", &problems)
        }
        // A label file that cannot be read and cannot be set aside: every save is refused, and Settings says why.
        let stuckFolder = SelfTest.scratchDirectory(), manager = FileManager.default
        guard (try? manager.createDirectory(at: stuckFolder, withIntermediateDirectories: true)) != nil,
              (try? Data("not json".utf8).write(to: stuckFolder.appendingPathComponent(AILabelStore.fileName))) != nil,
              (try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: stuckFolder.path)) != nil
        else { return problems + ["the label file was not put out of reach"] }
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuckFolder.path) }
        let stuck = AILabelStore(directory: stuckFolder)
        guard let failure = stuck.failure else { return problems + ["the label store was not left unable to save"] }
        problems += withSettings(labels: stuck) { settings, _, problems in
            expect(settings.aiLabelsFailure == failure,
                   "Settings did not show why the label file is not written: \(String(describing: settings.aiLabelsFailure))", &problems)
        }
        return problems
    }

    private static func keptLabelReachesSettings() -> [String] {
        CategoryAssistantRig.withRig(reply: { _, _ in CategoryAssistantRig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            let settings = SettingsModel(store: rig.f.persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            var announced = 0
            let watch = settings.objectWillChange.sink { announced += 1 }
            defer { watch.cancel() }
            expect(rig.f.store.keepAILabel(label.id), "Keep on the label was refused", &problems)
            expect(settings.workTypeDefinitions.contains { $0.id == label.id },
                   "Settings' categories did not hold the kept label", &problems)
            expect(announced > 0, "an open Settings window was not told a category was kept", &problems)
        }
    }
}
