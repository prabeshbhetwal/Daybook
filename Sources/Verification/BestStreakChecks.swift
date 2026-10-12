import Foundation

/// The best streak beside the current one counts the running session's work
/// today, as the current streak does, so the session that sets a record reads
/// as the record on the Awards sheet and in Ask rather than one day past it.
/// The record a new streak has to beat, which the reward reads, still leaves
/// that session out. Wed 15 Nov 2023, 9:13am; a day counts at 1h.
enum BestStreakChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The Awards sheet and Ask give the record being set as the best streak",
         screensShowRecordBeingSet),
    ]

    /// An hour on each of Sun 5 to Wed 8 Nov and Sat 11 to Tue 14 Nov: the
    /// record and the streak ending yesterday are both 4 days.
    private static func makeEngine(_ clock: TestClock, defaults: UserDefaults) -> SessionEngine? {
        let calendar = Calendar.current
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), calendar: calendar,
                                     now: { clock.value })
        let today = calendar.startOfDay(for: clock.value)
        for back in [10, 9, 8, 7, 4, 3, 2, 1] {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day),
                  archive.append(SessionRecord(name: "Thesis", workType: .deepWork, start: start,
                                               end: start.addingTimeInterval(3_600),
                                               workSeconds: 3_600)) == nil else { return nil }
        }
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        store.streakMinimum = 3_600
        archive.streakMinimum = 3_600
        return SessionEngine(store: store, archive: archive, ownBundleID: "com.example.self",
                             schedulesDwell: false, now: { clock.value })
    }

    private static func screensShowRecordBeingSet() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(SelfTest.base)
            let suite = "fc-selftest-best-streak-store-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else {
                return ["could not create isolated preferences suite"]
            }
            defer { MemoryDefaults.remove(named: suite) }
            guard let engine = makeEngine(clock, defaults: defaults) else { return ["could not seed the archive"] }
            let usage = AppUsageArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)

            engine.start(workType: .deepWork, intent: "Thesis")
            clock.advance(65 * 60)
            store.catchUpWithEngine()
            store.refresh()
            // The Awards sheet's streak panel reads `streak` and "best \(streakBest) days".
            expect(store.streak == 5 && store.streakBest == 5,
                   "the Awards sheet should read 5 days, best 5, got \(store.streak), best \(store.streakBest)",
                   &problems)
            expect(store.awardFacts.bestStreak == 5,
                   "the award facts should hold a best of 5, got \(store.awardFacts.bestStreak)", &problems)
            let goals = store.askLookup(.goals(nil))
            let line = "Current streak: 5 days with at least 1h of focus, since Sat 11 Nov. Longest: 5 days."
            expect(goals.contains(line), "Ask's goals should read “\(line)”, read “\(goals)”", &problems)
            return problems
        }
    }
}
