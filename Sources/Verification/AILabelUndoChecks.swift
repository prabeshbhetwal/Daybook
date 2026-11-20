import Foundation

/// A retired label coming back and the names nothing may share (Phase C review): an Undo whose label file save
/// fails says so and Retry finishes it, a removed name stays removed while another removed label holds it, and the
/// category editor refuses Unsorted and the name of a label the AI made.
enum AILabelUndoChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("Undo of a Remove whose label file save fails says so, and Retry brings the label back", undoOwesTheLabelFile),
        ("Undo keeps a removed name while another removed label holds it", sharedRemovedNameStays),
        ("The category editor refuses Unsorted and the name of a label the AI made", editorRefusesHiddenNames),
    ]

    private static func undoOwesTheLabelFile() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { return problems.append("no label was made") }
            expect(rig.f.store.removeAILabel(label.id), "Remove was refused", &problems)
            guard let unblock = AILaunchChecks.blockLabelFile(rig) else { return problems.append("the label file could not be held") }
            _ = rig.f.store.undoLastCorrection()
            expect(rig.stored()?.workType.rawValue == label.id, "Undo did not put the session back under the label", &problems)
            let store = rig.f.store
            expect(store.correctionError != nil && store.correctionRetry != nil,
                   "a label file Undo could not write was not shown with a Retry: \(String(describing: store.correctionError))", &problems)
            unblock()
            expect(store.retryLastCorrection(), "Retry was refused: \(store.correctionError ?? "no reason")", &problems)
            let book = rig.reloaded().book
            expect(book.labels.first { $0.id == label.id }?.archived == false && !book.removedNames.contains(label.name),
                   "Retry did not bring the label back: \(book.labels.map(\.archived)) \(book.removedNames)", &problems)
            expect(store.correctionError == nil && store.correctionRetry == nil, "the error or Retry stayed after Retry", &problems)
        }
    }

    private static func sharedRemovedNameStays() -> [String] {
        var book = AILabelBook()
        book.labels = [AIFixture.label("ai.a", "Films", seed: 1, archived: true), AIFixture.label("ai.b", "Films", seed: 2, archived: true)]
        book.removedNames = ["Films"]
        return Rig.withRig(prepare: { f in _ = AILabelStore(directory: f.engine.archive.dataDirectoryURL).save(book, at: SelfTest.base) }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            var carrying = rig.record
            carrying.workType = WorkType(rawValue: "ai.b")
            rig.f.store.aiLabelsFollowUndo(of: [carrying])
            let after = rig.assistant.labels.book
            expect(after.labels.first { $0.id == "ai.b" }?.archived == false, "the label Undo brought back stayed archived", &problems)
            expect(after.removedNames == ["Films"],
                   "the name came back while another removed label holds it: \(after.removedNames)", &problems)
        }
    }

    private static func editorRefusesHiddenNames() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-ai-names-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
        defer {
            MemoryDefaults.remove(named: suite)
            WorkTypeCatalog.shared.apply(customisations: [])
        }
        let labels = AILabelStore(directory: SelfTest.scratchDirectory())
        var book = AILabelBook()
        book.labels = [AIFixture.label("ai.selftest-films", "Films")]
        guard labels.save(book, at: AIFixture.base) == nil else { return ["the label file was not written"] }
        let settings = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.aiCategories = AICategorySource(setting: AIAssignSetting(defaults: defaults), labels: labels, now: { AIFixture.base })
        MainActor.assumeIsolated {
            for name in ["Films", "Unsorted"] {
                let editor = CategoryEditorState()
                editor.beginNew()
                editor.name = name
                CategoryEditorForm(model: settings, editor: editor, onFinished: {}).commitForTesting()
                expect(editor.validationMessage != nil && !settings.workTypeDefinitions.contains { $0.name == name },
                       "Settings saved a category named \(name): \(settings.workTypeDefinitions.map(\.name))", &problems)
            }
        }
        return problems
    }
}
