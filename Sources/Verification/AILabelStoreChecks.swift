import Foundation

/// `ai-labels.json` and what sits around it: the file reads back what was written (dates included), a file
/// that cannot be read is set aside and a later save starts afresh, the backup carries it, "Let AI assign
/// categories" is off until the person turns it on and stays out of a backup, and the catalogue keeps an
/// unkept label through the person's own later edits to their categories.
enum AILabelStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The label file reads back every label, answer, comparison and date it was given", roundTrips),
        ("A label file that cannot be read is set aside, and the next save writes a fresh one", setsUnreadableAside),
        ("The backup carries the label file", backupHoldsTheFile),
        ("Letting AI assign categories is off by default and never goes into a backup", settingStaysOut),
        ("The catalogue keeps an unkept label when the person edits their own categories", catalogueKeepsLabels),
    ]

    private static func roundTrips() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        var book = AIFixture.filledBook()
        // Fractions of a second survive: the file stores dates as they are, not as whole seconds.
        book.madeAt = [SelfTest.base.addingTimeInterval(0.25), SelfTest.base.addingTimeInterval(86_400.5)]
        let store = AILabelStore(directory: directory, now: SelfTest.base)
        expect(store.save(book, at: SelfTest.base) == nil, "a book was not saved", &problems)
        expect(store.book == book, "the store did not hold what it saved", &problems)
        let reread = AILabelStore(directory: directory, now: SelfTest.base).book
        expect(reread == book, "a relaunch read something other than what was saved: \(reread)", &problems)
        expect(reread.labels.map(\.name) == ["Films", "Games", "Chess"] && reread.labels.last?.archived == true,
               "labels or their archived flag did not survive", &problems)
        expect(reread.madeAt == book.madeAt, "the label makes lost their times: \(reread.madeAt)", &problems)
        expect(AILabelStore(directory: SelfTest.scratchDirectory()).book == AILabelBook(),
               "a folder with no file did not read as an empty book", &problems)
        return problems
    }

    private static func setsUnreadableAside() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        // Not JSON at all, and JSON of the wrong shape: neither can be read as a book.
        for garbage in ["this is not json", "[1, 2, 3]"] {
            let directory = SelfTest.scratchDirectory()
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(AILabelStore.fileName)
            try? Data(garbage.utf8).write(to: file)
            let store = AILabelStore(directory: directory, now: SelfTest.base)
            let names = ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
            expect(store.book == AILabelBook() && store.failure == nil,
                   "an unreadable file was not read as empty (\(garbage)): \(String(describing: store.failure))", &problems)
            expect(names.count == 1 && names[0].hasPrefix("ai-labels-corrupt-"),
                   "the unreadable file was not set aside (\(garbage)): \(names)", &problems)
            let filled = AIFixture.filledBook()
            expect(store.save(filled, at: SelfTest.base) == nil && AILabelStore(directory: directory).book == filled,
                   "a fresh file was not written after the old one was set aside", &problems)
        }
        return problems
    }

    // Guards `DataBackup.clone`, which copies the whole folder, not this work: it cannot fail on the label file alone.
    private static func backupHoldsTheFile() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        _ = AILabelStore(directory: directory).save(AIFixture.filledBook(), at: SelfTest.base)
        let manager = FileManager.default
        if let clone = try? DataBackup.clone(of: directory) {
            defer { try? manager.removeItem(at: clone) }
            expect(manager.fileExists(atPath: clone.appendingPathComponent(AILabelStore.fileName).path),
                   "the temporary clone left the label file out", &problems)
        } else {
            problems.append("no clone was made")
        }
        return problems
    }

    private static func settingStaysOut() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-ai-assign-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let setting = AIAssignSetting(defaults: defaults)
        expect(!setting.isOn, "assigning was on before the person turned it on", &problems)
        setting.isOn = true
        expect(AIAssignSetting(defaults: defaults).isOn, "turning assigning on was not remembered", &problems)
        let persistence = PersistenceStore(defaults: defaults)
        persistence.useAppleIntelligence = false
        let snapshot = persistence.backupSnapshot
        expect(snapshot["fc.useAppleIntelligence"] != nil, "the backup snapshot dropped an ordinary preference", &problems)
        expect(snapshot[AIAssignSetting.key] == nil, "the backup snapshot carried the assigning switch", &problems)
        persistence.removeAll()
        expect(!setting.isOn, "removing every preference left the assigning switch on", &problems)
        return problems
    }

    private static func catalogueKeepsLabels() -> [String] {
        var problems: [String] = []
        let catalogue = WorkTypeCatalog()
        let films = AIFixture.label("ai.films", "Films")
        catalogue.install(aiLabels: [films])
        var definition = catalogue.definition(for: WorkType(rawValue: films.id))
        expect(definition.name == "Films" && definition.isUnkeptAILabel && definition.isHidden,
               "an installed label did not resolve as a hidden definition: \(definition)", &problems)
        expect(!catalogue.activeTypes.contains(WorkType(rawValue: films.id)), "an unkept label was offered", &problems)
        // The person renames a category: the catalogue is installed again from their customisations alone.
        let renamed = WorkTypeDefinition(id: WorkType.admin.rawValue, name: "Paperwork", symbolName: "tray.full.fill", hue: .teal)
        catalogue.apply(customisations: [renamed])
        definition = catalogue.definition(for: WorkType(rawValue: films.id))
        expect(definition.name == "Films" && definition.isUnkeptAILabel,
               "an edit to a category dropped the unkept label: \(definition)", &problems)
        expect(catalogue.definition(for: .admin).name == "Paperwork", "the person's own edit was not applied", &problems)
        catalogue.install(aiLabels: [])
        expect(catalogue.definition(for: WorkType(rawValue: films.id)).name == "Other",
               "a label taken out of the book was still resolved", &problems)
        return problems
    }
}
