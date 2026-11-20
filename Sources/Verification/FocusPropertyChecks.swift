import Foundation
import AppKit

/// Categories carry a stored "counts toward focus goals" property (Phase C, ruling C11). These checks hold the
/// figures that count focus still while it is true for every category, then what moves when one is set false,
/// what a stored list from before the property reads as, and the two categories that are never offered:
/// the hidden "Unsorted" and a label an AI proposed that the person has not kept.
enum FocusPropertyChecks: CheckSuite {
    typealias Fixture = FocusPropertyFixture
    private static var reading: WorkType { Fixture.reading }

    static let tests: [(String, () -> [String])] = [
        ("With every category counting toward focus, each daily total, goal, streak and History figure is what it was before",
         totalsAreUnchanged),
        ("A stored category list without the key reads as counting toward focus for every category and not for Break",
         olderListReads),
        ("A category set not to count toward focus stays startable and drops out of totals, goals, streaks, the dashboard and History",
         setNotToCount),
        ("Unsorted is a hidden grey category that is not startable, not focus and in no list, and a record carrying it reads Unsorted",
         unsortedIsHidden),
        ("A label flagged as unkept is hidden everywhere and never written into the stored categories",
         unkeptIsNeverStored),
    ]

    /// Review Focus 1, read on the code as it was before the property existed: hand-counted from the fixture.
    private static let everyCategoryCounts = Fixture.Figures(
        dayTotals: [10_800, 5_400, 1_800, 7_200], sessions: [2, 2, 1, 1], currentStreak: 2, bestStreak: 2,
        goalCredit: [10_800, 5_400, 1_800, 7_200], dashboardSessions: [2, 2, 1, 1],
        dashboardSeconds: [10_800, 5_400, 1_800, 7_200], historyFocused: [10_800, 5_400, 1_800, 7_200],
        historySessions: [2, 2, 1, 1], historyRowFocused: [10_800, 5_400, 1_800, 7_200],
        historyMainType: ["deepWork", "custom.reading", "deepWork", "admin"], readingGoal: "3600.0",
        categoryGoalItems: 1)

    /// The same fixture with Reading set not to count: its hour leaves every figure, and with it a streak day.
    private static let readingNotCounted = Fixture.Figures(
        dayTotals: [10_800, 1_800, 1_800, 7_200], sessions: [2, 1, 1, 1], currentStreak: 1, bestStreak: 1,
        goalCredit: [10_800, 1_800, 1_800, 7_200], dashboardSessions: [2, 1, 1, 1],
        dashboardSeconds: [10_800, 1_800, 1_800, 7_200], historyFocused: [10_800, 1_800, 1_800, 7_200],
        historySessions: [2, 1, 1, 1], historyRowFocused: [10_800, 1_800, 1_800, 7_200],
        historyMainType: ["deepWork", "meetings", "deepWork", "admin"], readingGoal: "none",
        categoryGoalItems: 0)

    private static func totalsAreUnchanged() -> [String] {
        var problems: [String] = []
        let figures = Fixture.withCatalogue([Fixture.readingDefinition()]) { Fixture.figures() }
        for difference in Fixture.differences(figures, everyCategoryCounts) {
            problems.append("with every category counting, \(difference)")
        }
        return problems
    }

    private static func olderListReads() -> [String] {
        var problems: [String] = []
        let stored = Data("""
        [{"id":"deepWork","name":"Making","symbolName":"hammer.fill","hue":"purple"},
         {"id":"breakTime","name":"Rest","symbolName":"moon.fill","hue":"grey"},
         {"id":"custom.reading","name":"Reading","symbolName":"book.fill","hue":"green","dailyGoal":3600}]
        """.utf8)
        guard let decoded = try? JSONDecoder().decode([WorkTypeDefinition].self, from: stored) else {
            return ["a category list written before the property did not decode"]
        }
        expect(decoded.map(\.countsTowardFocus) == [true, false, true],
               "read without the key the categories said \(decoded.map(\.countsTowardFocus)), not true, false, true",
               &problems)
        Fixture.withCatalogue(decoded) {
            for type in [WorkType.deepWork, .meetings, .admin, .learning, reading] {
                expect(type.countsAsFocus && !type.isBreak, "\(type.rawValue) did not count toward focus", &problems)
            }
            expect(!WorkType.breakTime.countsAsFocus && WorkType.breakTime.isBreak,
                   "Break counted toward focus, or did not read as a break", &problems)
        }
        let off = WorkTypeDefinition(id: reading.rawValue, name: "Reading", symbolName: "book.fill", hue: .green,
                                     countsTowardFocus: false)
        if let data = try? JSONEncoder().encode([off]),
           let back = try? JSONDecoder().decode([WorkTypeDefinition].self, from: data) {
            expect(String(decoding: data, as: UTF8.self).contains("\"countsTowardFocus\":false"),
                   "a category set not to count was written without the key", &problems)
            expect(back.first?.countsTowardFocus == false, "a stored false read back as true", &problems)
        } else {
            problems.append("a category set not to count did not round trip")
        }
        return problems
    }

    private static func setNotToCount() -> [String] {
        var problems: [String] = []
        let notCounted = Fixture.readingDefinition { $0.countsTowardFocus = false }
        Fixture.withCatalogue([notCounted]) {
            for difference in Fixture.differences(Fixture.figures(), readingNotCounted) {
                problems.append("with Reading set not to count, \(difference)")
            }
            expect(!reading.countsAsFocus && !reading.isBreak && reading.dailyGoal == nil,
                   "Reading still counted as focus or read as a break, or kept a goal", &problems)
            // Not a break: offered, startable, continuable by the same rule, splittable, pinnable.
            expect(WorkType.allCases.contains(reading) && WorkType.startable.contains(reading),
                   "Reading left the pickers or became unstartable", &problems)
            expect(reading.startableOrFallback == reading, "Reading was swapped for the fallback", &problems)
            expect(!WorkType.startable.contains(.breakTime), "Break became startable", &problems)
            let record = Fixture.records().first { $0.workType == reading }
            expect(record?.canSplit(at: Fixture.at(-1, 14, 30)) == true, "a Reading session could not be split",
                   &problems)
            expect(SavedActivities.normalised([SavedActivity(name: "Novel", workType: reading)]).count == 1,
                   "a Reading activity could not be pinned", &problems)
            let editor = CategoryEditorState()
            editor.edit(notCounted)
            let saved = editor.definitionForSaving(existing: WorkTypeCatalog.shared.allDefinitions)
            expect(saved?.countsTowardFocus == false, "editing Reading in Settings put it back to counting",
                   &problems)
        }
        // The setting is the person's on a built-in too, and never on Break.
        let catalogue = WorkTypeCatalog(customisations: [
            WorkTypeDefinition(id: WorkType.meetings.rawValue, name: "Meetings", symbolName: "person.2.fill",
                               hue: .orange, countsTowardFocus: false),
            WorkTypeDefinition(id: WorkType.breakTime.rawValue, name: "Break", symbolName: "cup.and.saucer.fill",
                               hue: .grey, countsTowardFocus: true)])
        expect(!catalogue.definition(for: .meetings).countsTowardFocus, "Meetings did not take the setting",
               &problems)
        expect(!catalogue.definition(for: .breakTime).countsTowardFocus, "Break was set to count toward focus",
               &problems)
        // It survives a relaunch, which is a second store on the same preferences.
        let suite = "fc-selftest-focusproperty-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return problems + ["no in-memory preferences"] }
        defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
        PersistenceStore(defaults: defaults).workTypeDefinitions = [notCounted]
        _ = PersistenceStore(defaults: defaults)
        expect(!reading.countsAsFocus, "Reading counted as focus again after a relaunch", &problems)
        return problems
    }

    private static func unsortedIsHidden() -> [String] {
        var problems: [String] = []
        let unsorted = WorkType.unsorted
        let shipped = WorkTypeCatalog()
        expect(unsorted.displayName == "Unsorted" && unsorted.hue == .grey,
               "Unsorted was called \(unsorted.displayName) in \(unsorted.hue)", &problems)
        expect(NSImage(systemSymbolName: unsorted.symbolName, accessibilityDescription: nil) != nil,
               "Unsorted's symbol \(unsorted.symbolName) does not exist", &problems)
        expect(!unsorted.countsAsFocus && !unsorted.isBreak, "Unsorted counted as focus or read as a break",
               &problems)
        expect(!WorkType.startable.contains(unsorted) && !WorkType.allCases.contains(unsorted),
               "Unsorted is offered as a category", &problems)
        expect(shipped.activeTypes == [.deepWork, .meetings, .admin, .learning, .breakTime],
               "the shipped categories are \(shipped.activeTypes.map(\.rawValue))", &problems)
        expect(!shipped.allDefinitions.contains { $0.id == unsorted.rawValue },
               "Unsorted is in Settings' list of categories", &problems)
        expect(unsorted.startableOrFallback == WorkType.fallbackStartable,
               "a session cannot start as Unsorted, so it falls back", &problems)
        expect(WorkType.ordered([unsorted, .deepWork]) == [.deepWork, unsorted],
               "a total listing Unsorted lost it or put it first", &problems)
        let edited = WorkTypeCatalog(customisations: [
            WorkTypeDefinition(id: unsorted.rawValue, name: "Mine", symbolName: "tag.fill", hue: .blue,
                               countsTowardFocus: true)])
        expect(edited.definition(for: unsorted).name == "Unsorted" && !edited.definition(for: unsorted).countsTowardFocus
               && !edited.allDefinitions.contains { $0.id == unsorted.rawValue },
               "a stored entry changed Unsorted or listed it", &problems)
        // A record carrying it adds no focus to the day and keeps its name and kind through the file.
        let record = SessionRecord(name: "", workType: unsorted, start: Fixture.at(0, 9), end: Fixture.at(0, 10),
                                   workSeconds: 3_600)
        let archive = SelfTest.makeArchive(TestClock(Fixture.at(0, 19)), records: [record], calendar: Fixture.calendar)
        expect(archive.workSeconds(on: Fixture.day(0)) == 0 && archive.threadCount(on: Fixture.day(0)) == 0,
               "an Unsorted record added to the day's focus", &problems)
        expect(record.workType.sessionTitle(named: "") == "Unsorted", "an Unsorted record did not read Unsorted",
               &problems)
        if let data = try? JSONEncoder().encode(record),
           let back = try? JSONDecoder().decode(SessionRecord.self, from: data) {
            expect(back.workType == unsorted, "an Unsorted record read back as \(back.workType.rawValue)", &problems)
        } else {
            problems.append("an Unsorted record did not round trip")
        }
        return problems
    }

    private static func unkeptIsNeverStored() -> [String] {
        var problems: [String] = []
        let label = WorkTypeDefinition(id: "ai.0001", name: "Films", symbolName: "film.fill", hue: .pink,
                                       isUnkeptAILabel: true)
        let calls = WorkTypeDefinition(id: "custom.calls", name: "Calls", symbolName: "phone.fill", hue: .green)
        if let data = try? JSONEncoder().encode(label) {
            expect(!String(decoding: data, as: UTF8.self).contains("isUnkeptAILabel"),
                   "the unkept flag was encoded", &problems)
            expect((try? JSONDecoder().decode(WorkTypeDefinition.self, from: data))?.isUnkeptAILabel == false,
                   "the unkept flag was read from a file", &problems)
        } else {
            problems.append("a definition did not encode")
        }
        let suite = "fc-selftest-focusproperty-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return problems + ["no in-memory preferences"] }
        defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
        let store = PersistenceStore(defaults: defaults)
        store.workTypeDefinitions = [label, calls]
        let raw = defaults.data(forKey: "fc.workTypes").map { String(decoding: $0, as: UTF8.self) } ?? ""
        expect(!raw.contains("ai.0001") && !raw.contains("Films") && raw.contains("custom.calls"),
               "the stored categories were \(raw)", &problems)
        expect(store.workTypeDefinitions.map(\.id) == ["custom.calls"],
               "the stored categories read back as \(store.workTypeDefinitions.map(\.id))", &problems)
        let settings = SettingsModel(store: store, isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in })
        settings.saveCategory(label)
        expect(store.workTypeDefinitions.map(\.id) == ["custom.calls"],
               "Settings saved a label that was not kept", &problems)
        store.workTypeDefinitions = [label]
        expect(defaults.data(forKey: "fc.workTypes") == nil, "a list of only an unkept label was stored", &problems)

        // Hidden: named for the records that carry it, offered nowhere, listed nowhere, not startable.
        Fixture.withCatalogue([calls, label]) {
            let type = label.workType
            expect(type.displayName == "Films", "a label's records lost its name: \(type.displayName)", &problems)
            expect(!WorkType.allCases.contains(type) && !WorkType.startable.contains(type),
                   "an unkept label is offered or startable", &problems)
            expect(!WorkTypeCatalog.shared.allDefinitions.contains { $0.id == label.id },
                   "an unkept label is in Settings' list", &problems)
            expect(type.startableOrFallback == WorkType.fallbackStartable,
                   "a session could start as an unkept label", &problems)
        }
        return problems
    }
}
