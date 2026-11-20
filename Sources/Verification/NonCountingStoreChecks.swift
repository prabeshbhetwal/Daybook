import Foundation

/// The sites of a category set not to count toward focus (Phase C, C11) that need a store around them: History's
/// search, continuing and starting again, counting a recorded break into a session, a running session's figures,
/// and Story's totals and credit. Each would fail if its site asked "does it count?" where it should ask "is it
/// a break?", or the other way round. See `NonCountingCoreChecks` for the ones that need none.
enum NonCountingStoreChecks: CheckSuite {
    typealias Fixture = NonCountingFixture
    private static var reading: WorkType { Fixture.reading }
    private static var today: Date { Fixture.Base.day(0) }

    static let tests: [(String, () -> [String])] = [
        ("Searching History finds a session in a category set not to count, lists its day and shows its row",
         searchFindsIt),
        ("A session in a category set not to count can be continued or started again, and a break cannot",
         continuing),
        ("A recorded break can be counted into a session in a category set not to count",
         breakCountsIntoIt),
        ("A running session in a category set not to count adds no focus, session or streak, and its timer still runs",
         runningAddsNoFocus),
        ("Story's totals, session count and category credit give a category set not to count no focus",
         storyGivesNoFocus),
    ]

    private static func days(_ store: SessionStore) -> [JournalDay] {
        store.historyJournal().compactMap { entry in
            if case .day(let day) = entry { return day }
            return nil
        }
    }

    private static func searchFindsIt() -> [String] {
        MainActor.assumeIsolated {
            guard let f = Fixture() else { return ["the fixture could not be set up"] }
            defer { f.cleanUp() }
            var problems: [String] = []
            f.store.setHistoryQuery("novel")
            let found = days(f.store)
            expect(found.count == 1 && found[0].threads == [f.novel.threadID],
                   "searching Novel listed \(found.map { $0.threads?.count ?? -1 }) sessions on its day, not Novel's thread",
                   &problems)
            expect(found.first?.focused == 0 && found.first?.sessions == 0,
                   "a session that does not count added \(found.first?.focused ?? -1) seconds of focus", &problems)
            let rows = found.first.map { f.store.journalThreads(on: $0.date, only: $0.threads) } ?? []
            expect(rows == [f.novel.threadID], "the day showed \(rows.count) rows, not Novel's", &problems)

            // The sessions that count are still listed by thread with their focus, and a break by its record.
            f.store.setHistoryQuery("parser")
            let counted = days(f.store).first
            expect(counted?.threads == [f.deep.threadID] && counted?.focused == 3_600 && counted?.sessions == 1,
                   "searching Parser listed \(String(describing: counted?.threads?.count)) sessions with "
                   + "\(counted?.focused ?? -1) seconds", &problems)
            f.store.setHistoryQuery("lunch")
            let rest = days(f.store).first
            expect(rest?.threads == [f.lunch.id] && rest?.breaks == 1 && rest?.focused == 0 && rest?.sessions == 0,
                   "searching Lunch listed \(String(describing: rest?.threads?.count)) rows and "
                   + "\(rest?.breaks ?? -1) breaks", &problems)
            return problems
        }
    }

    private static func continuing() -> [String] {
        MainActor.assumeIsolated {
            guard let f = Fixture() else { return ["the fixture could not be set up"] }
            defer { f.cleanUp() }
            var problems: [String] = []
            let row = ActivitySnapshotChecks.daySession([f.novel])
            expect(f.store.canContinue(row), "a Reading session could not be continued", &problems)
            expect(f.store.canStartNewSession(row), "a Reading session could not be started again", &problems)
            // A row that carries none of the records' own ids is found by its thread and its end.
            let grouped = DaySession(id: UUID(), threadID: f.novel.threadID, name: f.novel.name, workType: reading,
                                     start: f.novel.start, end: f.novel.end, worked: f.novel.workSeconds,
                                     stretches: 1, spans: [DateInterval(start: f.novel.start, end: f.novel.end)],
                                     recordIDs: [f.novel.id], isRunning: false)
            expect(f.store.canContinue(grouped), "a Reading row that names no record could not be continued",
                   &problems)
            let rest = ActivitySnapshotChecks.daySession([f.lunch])
            expect(!f.store.canStartNewSession(rest) && !f.store.canContinue(rest),
                   "a break could be continued or started as a session", &problems)
            f.store.continueSession(row)
            expect(f.engine.state != .idle && f.engine.activeWorkType == reading
                   && f.engine.activeThreadID == f.novel.threadID,
                   "continuing Novel left the engine \(f.engine.state) in \(f.engine.activeWorkType.rawValue)",
                   &problems)
            return problems
        }
    }

    private static func breakCountsIntoIt() -> [String] {
        MainActor.assumeIsolated {
            guard let f = Fixture() else { return ["the fixture could not be set up"] }
            defer { f.cleanUp() }
            var problems: [String] = []
            let rest = RestEntry(id: f.lunch.id, name: f.lunch.name, start: f.lunch.start, end: f.lunch.end)
            expect(f.store.legacyFocusTargets(for: rest).map(\.id) == [f.novel.id, f.deep.id],
                   "the sessions offered for the break were "
                   + "\(f.store.legacyFocusTargets(for: rest).map(\.name)), not Novel then Parser", &problems)
            guard f.engine.reclassifyLegacyBreak(recordID: f.lunch.id, decision: .mergeTime,
                                                 focusTargetID: f.novel.id) else {
                return problems + ["the break could not be counted into Novel: \(f.engine.awayDecisionError ?? "no reason")"]
            }
            let counted = f.engine.lastAwayDecision?.insertedRecord
            expect(counted?.workType == reading && counted?.threadID == f.novel.threadID
                   && counted?.workSeconds == 900,
                   "the break was counted as \(counted?.workType.rawValue ?? "nothing") for "
                   + "\(counted?.workSeconds ?? -1) seconds", &problems)
            return problems
        }
    }

    private static func runningAddsNoFocus() -> [String] {
        MainActor.assumeIsolated {
            guard let f = Fixture(), let control = Fixture() else { return ["the fixture could not be set up"] }
            defer { control.cleanUp(); f.cleanUp() }
            var problems: [String] = []
            let before = f.engine.sessionsToday
            f.engine.start(workType: reading, intent: "Chapter two")
            f.clock.advance(600)
            expect(f.engine.elapsed == 600, "the timer of a Reading session read \(f.engine.elapsed), not 600",
                   &problems)
            expect(f.engine.elapsedToday() == 0, "a running Reading session added \(f.engine.elapsedToday()) seconds "
                   + "to today", &problems)
            expect(f.engine.todayTotal == f.archive.todayTotal(),
                   "today's total read \(f.engine.todayTotal), not \(f.archive.todayTotal())", &problems)
            expect(f.engine.sessionsToday == before, "a running Reading session made \(f.engine.sessionsToday) sessions "
                   + "today, not \(before)", &problems)
            // The same session in a category that counts, as the control.
            control.engine.start(workType: .admin, intent: "Chapter two")
            control.clock.advance(600)
            expect(control.engine.elapsedToday() == 600 && control.engine.sessionsToday == before + 1,
                   "a running Admin session added \(control.engine.elapsedToday()) seconds and made "
                   + "\(control.engine.sessionsToday) sessions", &problems)
            return problems
        }
    }

    private static func storyGivesNoFocus() -> [String] {
        MainActor.assumeIsolated {
            guard let f = Fixture() else { return ["the fixture could not be set up"] }
            defer { f.cleanUp() }
            var problems: [String] = []
            func read(_ when: String) {
                let credit = f.store.categoryCredit(on: today, usage: f.usage)
                expect(f.store.storyFocusedSeconds(on: today) == 3_600,
                       "\(when), Story's focus read \(f.store.storyFocusedSeconds(on: today)), not 3600", &problems)
                expect(f.store.storySessionCount(on: today) == 1,
                       "\(when), Story counted \(f.store.storySessionCount(on: today)) sessions, not 1", &problems)
                expect(f.store.storyCategorySeconds(on: today) == [.deepWork: 3_600],
                       "\(when), Story's categories read \(f.store.storyCategorySeconds(on: today))", &problems)
                expect(Set(credit.keys) == [WorkType.deepWork.rawValue],
                       "\(when), credit went to \(credit.keys.sorted()), not Deep work alone", &problems)
            }
            read("with Reading finished")
            f.engine.start(workType: reading, intent: "Chapter two")
            f.clock.advance(600)
            read("with Reading running")
            return problems
        }
    }
}
