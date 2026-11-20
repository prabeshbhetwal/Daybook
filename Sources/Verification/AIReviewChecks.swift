import Combine
import Foundation

/// Three holes a review of the AI report and Settings row found (Phase C, rulings C8, C14 and C17): a shadow
/// suggestion outliving the person's own choice of category, an open Settings window missing a change to the
/// label file, and the row reading its two marks from two passes over the archive.
enum AIReviewChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("A shadow suggestion is withdrawn once the person sets the session's category", suggestionGivesWayToThePerson),
        ("An open Settings window hears when the AI label file changes", settingsHearsTheLabelFile),
        ("A session row reads how it began and the AI mark together", rowMarksTogether),
    ]

    private static func suggestionGivesWayToThePerson() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            guard rig.f.store.aiReport(for: rig.session()).suggestion != nil else {
                problems.append("shadow mode offered nothing"); return
            }
            _ = rig.f.store.setWorkType(.learning, for: rig.session())
            let report = rig.f.store.aiReport(for: rig.session())
            expect(report.suggestion == nil, "the suggestion was still offered over the person's choice: \(report)", &problems)
        }
    }

    private static func settingsHearsTheLabelFile() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-ai-review-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let labels = AILabelStore(directory: SelfTest.scratchDirectory())
        let settings = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.aiCategories = AICategorySource(setting: AIAssignSetting(defaults: defaults), labels: labels,
                                                 modelAvailable: { true })
        var heard = 0
        let watch = settings.objectWillChange.sink { heard += 1 }
        var book = labels.book
        book.tally = [TallyEntry(recordID: UUID(), answerID: WorkType.deepWork.rawValue, chosen: WorkType.deepWork.rawValue)]
        let failure = labels.save(book, at: SelfTest.base)
        watch.cancel()
        expect(failure == nil, "the label file was not saved: \(failure ?? "")", &problems)
        expect(heard > 0, "Settings was not told the label file changed, so its tally line stayed stale", &problems)
        return problems
    }

    private static func rowMarksTogether() -> [String] {
        var spec = Rig.Spec()
        spec.source = .ai
        return Rig.withRig([spec]) { rig, problems in
            let session = rig.session()
            let marks = rig.f.store.rowMarks(for: session)
            expect(marks.aiMark, "a session whose category the AI set showed no mark", &problems)
            expect(marks.origin == rig.f.store.originText(for: session),
                   "the row's origin \(String(describing: marks.origin)) is not the report's", &problems)
        }
    }
}
