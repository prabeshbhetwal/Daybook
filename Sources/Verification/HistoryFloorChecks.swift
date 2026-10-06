import Foundation

/// History starts on 1 January 2001, where stored dates count from. A record
/// dated earlier is malformed: one dated about 4713 BC made History build some
/// 6,700 year rows and stall. History's notices say what it leaves out.
enum HistoryFloorChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("History leaves out and discloses records from before 2001, and keeps everything after",
         historyStartsIn2001),
        ("History's notices count left-out records in the singular or plural each needs",
         noticeCountsReadAsEnglish),
    ]

    private static func historyStartsIn2001() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let clock = TestClock(SelfTest.anchoredNow())
            let firstDay = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
            // Where Calendar clamps a stored date of -1e300.
            let ancient = Date(timeIntervalSinceReferenceDate: -211_845_140_000)
            // Old but possible: noon on the first day History shows.
            let oldest = firstDay.addingTimeInterval(12 * 3_600)
            // Before 2001, so malformed too, but within the years Calendar keeps.
            let late1990s = firstDay.addingTimeInterval(-400 * 86_400)
            let records = [
                SessionRecord(name: "Corrupted date", workType: .deepWork, start: ancient,
                              end: ancient.addingTimeInterval(3_600), workSeconds: 3_600),
                SessionRecord(name: "Wrong year", workType: .deepWork, start: late1990s,
                              end: late1990s.addingTimeInterval(3_600), workSeconds: 3_600),
                SessionRecord(name: "Oldest real", workType: .deepWork, start: oldest,
                              end: oldest.addingTimeInterval(3_600), workSeconds: 3_600),
                SessionRecord(name: "Today", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-2 * 3_600),
                              end: clock.value.addingTimeInterval(-3_600), workSeconds: 3_600),
                // Too long to place on rows: the other notice History gives.
                SessionRecord(name: "Too long", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-500 * 86_400),
                              end: clock.value.addingTimeInterval(-3 * 3_600), workSeconds: 3_600)
            ]
            let usageSessions = [
                AppUsageSession(bundleID: "org.example.old", appName: "Old",
                                start: ancient, end: ancient.addingTimeInterval(600))
            ]

            let built = HistoryStats.build(sessionRecords: records, usage: usageSessions, calendar: calendar)
            expect(built.droppedBeforeFirstDay == 3,
                   "three records predate 2001, got \(built.droppedBeforeFirstDay)", &problems)
            expect(built.days.contains { $0.date == firstDay } && !built.days.contains { $0.date < firstDay },
                   "History should keep 1 January 2001 and nothing before it, got \(built.days.map(\.date))",
                   &problems)

            let suite = "fc-selftest-history-floor-\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated defaults suite"] }
            defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
            let usage = SelfTest.makeUsageArchive(clock, sessions: usageSessions)
            let archive = SelfTest.makeArchive(clock, records: records, calendar: calendar)
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            // A decision receipt adds its own days to History after the builder.
            var saved = engine.snapshot()
            saved.awayDecisions = [AwayDecisionReceipt(
                id: UUID(), range: DateInterval(start: ancient, end: ancient.addingTimeInterval(600)),
                name: "Corrupted away", workType: .breakTime, threadID: UUID(), sessionStart: ancient,
                decision: .tookBreak, insertedRecord: nil, creditedSeconds: 0)]
            engine.restore(from: saved)
            expect(engine.awayDecisions.count == 1,
                   "the check should plant one corrupted receipt, got \(engine.awayDecisions.count)", &problems)
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()

            let shown = store.historyDays.map(\.date).min()
            expect(shown == firstDay, "History should start on \(firstDay), got \(String(describing: shown))",
                   &problems)
            expect(store.historyIntegrityNotices.contains {
                $0.contains("3 records dated before 2001")
                    && $0.localizedCaseInsensitiveContains("source records remain preserved")
            }, "History should disclose the 3 records from before 2001, got \(store.historyIntegrityNotices)",
                   &problems)
            expect(store.historyIntegrityNotices.contains { $0.contains("History omitted 1 focus record from") },
                   "History should say it omitted 1 focus record, got \(store.historyIntegrityNotices)", &problems)
            expect(archive.records == records && usage.sessions == usageSessions,
                   "leaving records out of History should never rewrite either source archive", &problems)

            // A live update rebuilds from the oldest changed day, which an
            // app-use record dated far back moves to that record's day.
            let checkpointed = usage.checkpoint(AppUsageSession(
                bundleID: "org.example.older", appName: "Older",
                start: ancient.addingTimeInterval(7_200), end: ancient.addingTimeInterval(7_800)))
            expect(checkpointed, "the check should save a far-back app-use record", &problems)
            store.refreshReview(rebuildingHistory: false)
            let live = store.historyDays.map(\.date).min()
            expect(live == firstDay,
                   "after a live update History should still start on \(firstDay), got \(String(describing: live))",
                   &problems)
            return problems
        }
    }

    private static func noticeCountsReadAsEnglish() -> [String] {
        var problems: [String] = []
        let cases: [((Int, Int, Int), String?)] = [
            ((0, 0, 0), nil),
            ((0, 1, 0), "1 focus record"),
            ((2, 0, 1), "2 app-usage records and 1 rest record"),
            ((1, 1, 1), "1 app-usage record, 1 focus record and 1 rest record"),
        ]
        for ((usage, focus, rest), expected) in cases {
            let text = SessionStore.recordCounts(usage: usage, focus: focus, rest: rest)
            expect(text == expected, "\(usage)/\(focus)/\(rest) left out should read \(expected ?? "nothing"), "
                       + "got \(text ?? "nothing")", &problems)
        }
        return problems
    }
}
