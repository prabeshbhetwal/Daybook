import Foundation

/// A category listed nowhere (the hidden "Unsorted", a label an AI proposed that the person has not kept) is not
/// the person's to edit or keep: the editor will not open on it or save it, and the stored list never holds it.
/// The catalogue also answers "does this count toward focus?" for one category without copying its definition.
enum HiddenCategoryChecks: CheckSuite {
    private static let label = WorkTypeDefinition(id: "ai.0001", name: "Films", symbolName: "film.fill", hue: .pink,
                                                  isUnkeptAILabel: true)
    private static let calls = WorkTypeDefinition(id: "custom.calls", name: "Calls", symbolName: "phone.fill",
                                                  hue: .green)

    static let tests: [(String, () -> [String])] = [
        ("The category editor will not open on or save Unsorted or a label that was not kept",
         editorRefuses),
        ("Neither Unsorted nor a label that was not kept is ever written into the person's stored categories",
         neverStored),
        ("The catalogue says whether a category counts toward focus as its definition does, for any identifier",
         catalogueAnswers),
    ]

    private static func editorRefuses() -> [String] {
        var problems: [String] = []
        defer { WorkTypeCatalog.shared.apply(customisations: []) }
        WorkTypeCatalog.shared.apply(customisations: [calls, label])
        let editor = CategoryEditorState()
        for hidden in [WorkTypeCatalog.unsortedDefinition, label] {
            editor.edit(hidden)
            expect(!editor.isOpen, "the editor opened on \(hidden.name)", &problems)
            // A form already on it, however it got there, still will not hand it over for saving.
            editor.selectedID = hidden.id
            editor.name = hidden.name
            editor.symbolName = hidden.symbolName
            expect(editor.definitionForSaving(existing: WorkTypeCatalog.shared.allDefinitions) == nil,
                   "the editor would save \(hidden.name)", &problems)
        }
        editor.edit(calls)
        expect(editor.isOpen && editor.definitionForSaving(existing: WorkTypeCatalog.shared.allDefinitions)?.id == calls.id,
               "the editor would not open on or save a category the person made", &problems)
        return problems
    }

    private static func neverStored() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-hidden-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no in-memory preferences"] }
        defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
        let persistence = PersistenceStore(defaults: defaults)
        persistence.workTypeDefinitions = [WorkTypeCatalog.unsortedDefinition, label, calls]
        expect(persistence.workTypeDefinitions.map(\.id) == ["custom.calls"],
               "the stored categories were \(persistence.workTypeDefinitions.map(\.id))", &problems)
        let settings = SettingsModel(store: persistence, isTrackingEnabled: true, onChange: {},
                                     onTrackingChanged: { _ in })
        settings.saveCategory(WorkTypeCatalog.unsortedDefinition)
        expect(persistence.workTypeDefinitions.map(\.id) == ["custom.calls"],
               "Settings kept \(persistence.workTypeDefinitions.map(\.id)) after Unsorted was saved", &problems)
        return problems
    }

    private static func catalogueAnswers() -> [String] {
        var problems: [String] = []
        let notCounted = NonCountingFixture.notCounted()
        NonCountingFixture.Base.withCatalogue([notCounted, calls, label]) {
            let everything = WorkType.allCases + [.breakTime, .unsorted, label.workType, WorkType(rawValue: "never.heard.of")]
            for type in everything {
                expect(WorkTypeCatalog.shared.countsTowardFocus(type) == type.definition.countsTowardFocus,
                       "\(type.rawValue) counted as \(WorkTypeCatalog.shared.countsTowardFocus(type)), "
                       + "not as its definition says", &problems)
            }
            expect(!WorkTypeCatalog.shared.countsTowardFocus(NonCountingFixture.reading)
                   && WorkTypeCatalog.shared.countsTowardFocus(.deepWork),
                   "the catalogue did not read Reading as not counting and Deep work as counting", &problems)
        }
        return problems
    }
}
