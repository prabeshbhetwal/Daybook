import Foundation

/// An app that stays in front grows its open stretch with the clock, and no
/// revision moves when it does. App time read from the sorted-use cache must
/// keep up, for Ask and for History's own app view alike, because both read
/// the same cache.
enum AskLiveAppTimeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's app time and History's app view keep counting while one app stays in front",
         appTimeKeepsCounting),
        ("Ask's app time keeps counting inside a running session, and rebuilds once a minute at most",
         appTimeKeepsCountingInSession),
    ]

    private static let notes = "com.example.Notes"

    private static func appTimeKeepsCounting() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.tracker?.appActivated(bundleID: notes, name: "Notes")
            f.clock.advance(5 * 60)
            let first = f.store.askLookup(.appTime(.today, app: "notes"))
            expect(first == "Notes today: 5m in front; used in 0 sessions.", "after 5m, Ask says “\(first)”", &problems)
            f.store.setHistoryApp(notes)
            f.store.refreshReview()
            SelfTest.expectClose(f.store.historyAppLens()?.total ?? -1, 300, "History's Notes figure after 5m",
                                 &problems)

            // Half an hour with no app switch: no revision moves.
            f.clock.advance(30 * 60)
            let second = f.store.askLookup(.appTime(.today, app: "notes"))
            expect(second == "Notes today: 35m in front; used in 0 sessions.",
                   "half an hour later, with Notes still in front, Ask says “\(second)”", &problems)
            SelfTest.expectClose(f.store.historyAppLens()?.total ?? -1, 2_100,
                                 "History's Notes figure half an hour later", &problems)
        }
    }

    private static func appTimeKeepsCountingInSession() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.engine.start(workType: .deepWork, intent: "Reading")
            f.store.tracker?.appActivated(bundleID: notes, name: "Notes")
            f.clock.advance(5 * 60)
            _ = f.store.askLookup(.appTime(.today, app: "notes"))
            let built = f.store.historySortedUsageComputeCount

            // Within the minute nothing has moved, so nothing is rebuilt.
            f.clock.advance(5)
            _ = f.store.askLookup(.appTime(.today, app: "notes"))
            expect(f.store.historySortedUsageComputeCount == built,
                   "a second lookup in the same minute rebuilt the sorted use", &problems)

            f.clock.advance(30 * 60)
            let later = f.store.askLookup(.appTime(.today, app: "notes"))
            expect(later.hasPrefix("Notes today: 35m in front;"), "half an hour later Ask says “\(later)”", &problems)
            expect(f.store.historySortedUsageComputeCount == built + 1,
                   "half an hour later the sorted use was built \(f.store.historySortedUsageComputeCount - built) times",
                   &problems)
            f.store.setHistoryApp(notes)
            f.store.refreshReview()
            SelfTest.expectClose(f.store.historyAppLens()?.total ?? -1, 2_105,
                                 "History's Notes figure half an hour later, inside the session", &problems)
        }
    }
}
