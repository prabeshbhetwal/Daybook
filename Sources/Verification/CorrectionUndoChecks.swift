import Foundation

/// Undo of the person's own category change takes back what it taught, and what the store does around
/// that: a choice it cannot keep is logged, an entry it cannot read is kept, and the branches of the
/// recording that decide what is remembered at all.
enum CorrectionUndoChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Undoing a category change, from the row or Edit > Undo, forgets it as a suggestion", undoForgetsTheChoice),
        ("Undoing the later of two choices of one kind leaves the earlier as it was, count, date and vetoes",
         undoLeavesTheEarlier),
        ("Undo still forgets the choice after a relaunch", undoSurvivesRelaunch),
        ("A choice that cannot be remembered is logged once, and the category change still lands", unrememberedIsLogged),
        ("An entry the file holds that this build cannot read is kept, and does not cost the rest",
         unreadEntriesAreKept),
        ("A session still running is never remembered", runningIsNotRemembered),
        ("Leaving a category the person chose is no veto, and leaving one a rule chose is", vetoFollowsTheSource),
        ("A count already at the limit stays there instead of overflowing", countCannotOverflow),
    ]

    private typealias Sessions = CorrectionsStoreChecks

    @MainActor
    private static func twoSessions() -> (store: SessionStore, clock: TestClock, suite: String,
                                          first: DaySession, second: DaySession)? {
        let (store, clock, suite) = Sessions.make()
        guard let first = Sessions.ended(store, clock, begin: Sessions.automatic("Parser")),
              let second = Sessions.ended(store, clock, begin: Sessions.automatic("Router")) else { return nil }
        return (store, clock, suite, first, second)
    }

    private static func undoForgetsTheChoice() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for byRow in [true, false] {
                let how = byRow ? "the row's Undo" : "Edit > Undo"
                guard let made = twoSessions() else { return ["no sessions were made"] }
                defer { MemoryDefaults.remove(named: made.suite) }
                let store = made.store
                expect(store.setWorkType(.learning, for: made.first), "the category change was refused", &problems)
                expect(store.correctionSuggestion(for: made.second) == .learning, "no choice to take back", &problems)
                guard let correction = store.lastCorrection else { return problems + ["no correction was kept"] }
                let undone = byRow ? store.undoCorrection(expectedID: correction.id) : store.undoLastCorrection()
                expect(undone, "\(how) was refused: \(store.correctionError ?? "no reason")", &problems)
                expect(Sessions.record(made.first, in: store)?.workType == .deepWork,
                       "\(how) did not put the category back", &problems)
                expect(store.correctionSuggestion(for: made.second) == nil,
                       "after \(how), the next session of its kind was still offered the undone category", &problems)
                expect(Sessions.stored(store).entries.isEmpty,
                       "after \(how), the file still holds \(Sessions.stored(store).entries)", &problems)
            }
            return problems
        }
    }

    private static func undoLeavesTheEarlier() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let made = twoSessions() else { return ["no sessions were made"] }
            defer { MemoryDefaults.remove(named: made.suite) }
            let store = made.store, clock = made.clock
            guard let third = Sessions.ended(store, clock, begin: Sessions.automatic("Doctor", .learning)) else {
                return ["no third session"]
            }
            store.setWorkType(.learning, for: made.first)
            let earlier = Sessions.stored(store).entries
            clock.advance(3_600)
            // Moving a session out of Learning lifts the veto on Deep Work and vetoes Learning.
            expect(store.setWorkType(.deepWork, for: third), "the second change was refused", &problems)
            expect(Sessions.stored(store).entries.first?.chosen == "deepWork"
                   && Sessions.stored(store).entries.first?.vetoed == ["learning"],
                   "the second change left \(Sessions.stored(store).entries)", &problems)
            expect(store.undoLastCorrection(), "the second change could not be undone", &problems)
            expect(Sessions.stored(store).entries == earlier,
                   "undo left \(Sessions.stored(store).entries), not \(earlier)", &problems)
            expect(store.correctionSuggestion(for: made.second) == .learning,
                   "the earlier choice was lost with the later one", &problems)
            return problems
        }
    }

    private static func undoSurvivesRelaunch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let made = twoSessions() else { return ["no sessions were made"] }
            defer { MemoryDefaults.remove(named: made.suite) }
            let clock = made.clock
            expect(made.store.setWorkType(.learning, for: made.first), "the category change was refused", &problems)
            guard let id = made.store.lastCorrection?.id else { return problems + ["no correction was kept"] }
            // The same folder and preferences, read again by new objects.
            let archive = SessionArchive(directory: made.store.engine.archive.dataDirectoryURL, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: made.suite) ?? .standard),
                                       archive: archive, ownBundleID: "com.test", schedulesDwell: false,
                                       now: { clock.value })
            AppCoordinator.restorePersistedEngine(engine, awayAtLaunch: false)
            let relaunched = SessionStore(engine: engine, now: { clock.value })
            expect(relaunched.undoCorrection(expectedID: id),
                   "Undo after a relaunch was refused: \(relaunched.correctionError ?? "no reason")", &problems)
            expect(Sessions.stored(relaunched).entries.isEmpty,
                   "Undo after a relaunch left \(Sessions.stored(relaunched).entries)", &problems)
            return problems
        }
    }

    private static func unrememberedIsLogged() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let made = twoSessions() else { return ["no sessions were made"] }
            defer { MemoryDefaults.remove(named: made.suite) }
            // A file a newer Daybook wrote, in place before the store first reads it.
            let file = made.store.engine.archive.dataDirectoryURL.appendingPathComponent("corrections.json")
            let newer = Data(#"{"version":2,"entries":[]}"#.utf8)
            try? newer.write(to: file)
            var logged: [String] = []
            Diagnostics.observer = { logged.append($0) }
            defer { Diagnostics.observer = nil }
            expect(made.store.setWorkType(.learning, for: made.first), "the category change was refused", &problems)
            expect(logged.filter { $0.contains("not remembered") }.count == 1,
                   "a refused remember was logged \(logged.filter { $0.contains("not remembered") }.count) times: \(logged)",
                   &problems)
            expect((try? Data(contentsOf: file)) == newer, "a newer Daybook's file changed", &problems)
            return problems
        }
    }

    private static func unreadEntriesAreKept() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("corrections.json")
        var known = CategoryCorrections()
        known.record(fingerprint: Sessions.typical, chosen: "learning", vetoed: "deepWork", at: SelfTest.base)
        let strangers: [Any] = [
            // Shaped like a choice, but of a kind this build does not know, with a field of its own.
            ["kind": "awayAnswer", "answer": "tookBreak", "chosen": "tookBreak", "vetoed": [String](), "count": 2,
             "lastUsed": 0, "fingerprint": ["shares": [5, 0, 0, 0, 0, 0, 0], "topApps": ["a", ""], "siteKind": "none"]]
                as [String: Any],
            ["kind": "category", "chosen": "learning"] as [String: Any],   // a category choice missing its fingerprint
            7,
        ]
        guard let encoded = try? JSONEncoder().encode(known),
              var document = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any],
              let entries = document["entries"] as? [Any] else { return ["the fixture file was not made"] }
        document["entries"] = entries + strangers
        guard let bytes = try? JSONSerialization.data(withJSONObject: document) else { return ["no fixture bytes"] }
        try? bytes.write(to: file)

        let store = CorrectionsStore(directory: directory)
        expect(store.corrections.entries.count == 1 && store.corrections.unread.count == 3,
               "the file read as \(store.corrections.entries.count) entries and \(store.corrections.unread.count) unread",
               &problems)
        expect(store.suggestion(for: Sessions.typical, now: SelfTest.base) == "learning",
               "one entry this build cannot read cost the others", &problems)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        expect(names == ["corrections.json"], "the file was set aside for one entry: \(names)", &problems)
        expect(store.record(fingerprint: CategoryCorrectionChecks.fingerprint([0, 5, 0, 0, 0, 0, 0]), chosen: "admin",
                            vetoed: nil, at: SelfTest.base) == nil, "the next record was refused", &problems)
        let written = ((try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
            as? [String: Any])?["entries"] as? [Any] ?? []
        expect(written.count == 5, "the file holds \(written.count) entries, not 5", &problems)
        for stranger in strangers {
            expect(written.contains { ($0 as AnyObject).isEqual(stranger) },
                   "an entry this build cannot read was not written back as it was: \(stranger)", &problems)
        }
        return problems
    }

    private static func runningIsNotRemembered() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = Sessions.make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let done = Sessions.ended(store, clock, begin: Sessions.automatic("Parser")),
                  let stored = Sessions.record(done, in: store) else { return ["no session was made"] }
            let running = ActivitySnapshotChecks.daySession([stored], running: true)
            expect(store.setWorkType(.learning, for: running), "the category change was refused", &problems)
            expect(Sessions.stored(store).entries.isEmpty, "a running session was remembered", &problems)
            return problems
        }
    }

    private static func vetoFollowsTheSource() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = Sessions.make()
            defer { MemoryDefaults.remove(named: suite) }
            let own = Sessions.ended(store, clock) { $0.start(workType: .deepWork, intent: "Mine") }
            let action = ActivityAutomaticAction(ruleID: UUID(), ruleName: "Coding", workType: .deepWork,
                                                 evidence: DateInterval(start: clock.value.addingTimeInterval(-300),
                                                                        end: clock.value),
                                                 reason: "Coding evidence", ruleVersion: 1, generation: 1,
                                                 expectedRecordID: nil)
            let ruled = Sessions.ended(store, clock) { _ = $0.startAutomatically(action: action) }
            guard let own, let ruled else { return ["no sessions were made"] }
            let sources = [own, ruled].map { Sessions.record($0, in: store)?.effectiveCategorySource }
            expect(sources == [.user, .rule], "the fixtures carry sources \(sources)", &problems)

            expect(store.setWorkType(.learning, for: own), "the person's own session was refused", &problems)
            expect(Sessions.stored(store).entries.first?.vetoed == [],
                   "leaving the person's own category vetoed it: \(String(describing: Sessions.stored(store).entries.first))",
                   &problems)
            expect(store.setWorkType(.admin, for: ruled), "the rule's session was refused", &problems)
            let entry = Sessions.stored(store).entries.first
            expect(entry?.chosen == "admin" && entry?.vetoed == ["deepWork"],
                   "leaving a rule's category did not veto it: \(String(describing: entry))", &problems)
            return problems
        }
    }

    private static func countCannotOverflow() -> [String] {
        var problems: [String] = []
        let limit = "9223372036854775807"
        let text = #"{"version":1,"entries":[{"kind":"category","fingerprint":{"shares":[5,0,0,0,0,0,0],"topApps":["com.example.editor",""],"siteKind":"none"},"chosen":"learning","vetoed":[],"count":"#
            + limit + #","lastUsed":0}]}"#
        guard var corrections = try? JSONDecoder().decode(CategoryCorrections.self, from: Data(text.utf8)) else {
            return ["a count at the limit did not decode"]
        }
        corrections.record(fingerprint: Sessions.typical, chosen: "learning", vetoed: nil, at: SelfTest.base)
        expect(corrections.entries.first?.count == Int.max,
               "a count at the limit became \(String(describing: corrections.entries.first?.count))", &problems)
        return problems
    }
}
