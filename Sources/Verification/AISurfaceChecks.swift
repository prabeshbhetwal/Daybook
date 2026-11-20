import Foundation

/// What the views say and offer of Apple Intelligence's part (Phase C, rulings C8, C17 and C20): the mark is
/// spoken as words, the row says the category was the AI's, the suggestion row draws nothing while a
/// remembered correction is offered, the Settings switch cannot be used while on-device AI is off, and the
/// category editor never offers Break a say in focus goals. The signature following the source is
/// `AIReportChecks`' fourth check.
enum AISurfaceChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("The AI mark is spoken as words and says on hover how to keep or change it", markIsSpoken),
        ("A session row tells VoiceOver its category was assigned by AI only when it was", rowSaysAssigned),
        ("The suggestion row says what it offers and draws nothing while a remembered correction is offered",
         suggestionRowGivesWay),
        ("The Settings switch to let AI assign categories cannot be used while on-device AI is off", switchNeedsAI),
        ("The category editor offers Counts toward focus goals for every category but Break", editorFocusToggle),
    ]

    private static func markIsSpoken() -> [String] {
        var problems: [String] = []
        expect(AIMark.spoken == "assigned by AI", "the mark is spoken as \(AIMark.spoken)", &problems)
        expect(AIMark.helpText == "Assigned by on-device AI. Open the session to keep or change it.",
               "the mark's help reads \(AIMark.helpText)", &problems)
        return problems
    }

    private static func rowSaysAssigned() -> [String] {
        var problems: [String] = []
        let marked = SessionEntryCard.spokenCategory(.deepWork, aiMark: true)
        let plain = SessionEntryCard.spokenCategory(.deepWork, aiMark: false)
        expect(marked == "\(WorkType.deepWork.displayName), assigned by AI", "a marked row said \(marked)", &problems)
        expect(plain == WorkType.deepWork.displayName, "an unmarked row said \(plain)", &problems)
        return problems
    }

    private static func suggestionRowGivesWay() -> [String] {
        var problems: [String] = []
        let pick = AISuggestionRow.line(for: .pick(.deepWork))
        let made = AISuggestionRow.line(for: .newCategory(name: "Films"))
        expect(pick == "On-device AI suggests \(WorkType.deepWork.displayName).", "a pick was offered as \(pick)", &problems)
        expect(made == "On-device AI suggests a new category, Films.", "a new category was offered as \(made)", &problems)
        problems += Rig.withRig([Rig.Spec(seed: 1), Rig.Spec(seed: 1)], reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(0)
            expect(rig.f.store.aiReport(for: rig.session(0)).suggestion.map { AISuggestionRow.line(for: $0) } != nil,
                   "the row drew nothing before any correction", &problems)
            _ = rig.f.store.setWorkType(.learning, for: rig.session(1))
            guard rig.f.store.correctionSuggestion(for: rig.session(0)) != nil else {
                problems.append("no remembered correction was offered"); return
            }
            let line = rig.f.store.aiReport(for: rig.session(0)).suggestion.map { AISuggestionRow.line(for: $0) }
            expect(line == nil, "the row drew \(line ?? "") beside a remembered correction", &problems)
        }
        return problems
    }

    private static func switchNeedsAI() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-ai-surface-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let settings = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.aiCategories = AICategorySource(setting: AIAssignSetting(defaults: defaults), labels: nil,
                                                 modelAvailable: { true })
        settings.useAppleIntelligence = false
        expect(!SettingsGroups.aiSwitchUsable(settings), "the switch could be used with on-device AI off", &problems)
        settings.useAppleIntelligence = true
        expect(SettingsGroups.aiSwitchUsable(settings), "the switch stayed disabled with on-device AI on", &problems)
        return problems
    }

    private static func editorFocusToggle() -> [String] {
        var problems: [String] = []
        expect(!CategoryEditorForm.offersFocusSetting(for: WorkType.breakTime.rawValue),
               "Break was offered Counts toward focus goals", &problems)
        for type in [WorkType.deepWork, .meetings] {
            expect(CategoryEditorForm.offersFocusSetting(for: type.rawValue),
                   "\(type.displayName) was not offered Counts toward focus goals", &problems)
        }
        return problems
    }
}
