import Foundation

/// Exercises the session actions and the History search model with scratch data.
enum FocusSmokeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An ended focus session is available in History", endedSessionAppears)
    ]

    private static func endedSessionAppears() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(SelfTest.base)
            let engine = SelfTest.makeEngine(clock)
            let usage = SelfTest.makeUsageArchive(clock, sessions: [])
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.intent = "Fixture smoke"
            store.workType = .deepWork
            store.start()
            expect(engine.state == .running, "session should start", &problems)
            clock.advance(120)
            store.stop()
            expect(engine.state == .idle, "session should stop", &problems)
            store.refreshReview()
            store.setHistoryQuery("Fixture smoke")
            let hits = store.historySearchHits()
            expect(hits.count == 1 && hits.first?.name == "Fixture smoke"
                   && hits.first?.worked == 120,
                   "History should find the ended 120-second session; got \(hits.count) hits", &problems)
            return problems
        }
    }
}
