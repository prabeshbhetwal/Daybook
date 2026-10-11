import Combine
import Foundation

/// What History's search keeps true after it was typed: a "yesterday" or "this
/// week" follows the clock past midnight, a zone change and the app names
/// loading, through the hooks History already has (opening, and the tree's top
/// moving), and the length phrases the final review found unread. "Now" is
/// Wednesday 15 November 2023 (`AskLookupChecks.withFixture`), whose sessions
/// are Thesis on Mon 13 Nov, Parser on Tue 14 Nov and Thesis on Tue 17 Oct.
enum HistorySearchRefoldChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A typed day or week moves with the clock past midnight", followsMidnight),
        ("An app name typed before the names load is read once they do", namesLoadLate),
        ("A zone change rebuilds a typed period in the new zone", zoneChange),
        ("Reading the text again publishes nothing when nothing moved", quiet),
        ("A length reads .5h, 1h30m and a unit given after the second number only", lengths),
    ]

    private typealias Fixture = AskLookupChecks.Fixture

    private static func fixture(_ body: @MainActor (Fixture, inout [String]) -> Void) -> [String] {
        AskLookupChecks.withFixture { f, problems in MainActor.assumeIsolated { body(f, &problems) } }
    }

    private static func labels(_ f: Fixture) -> [String] { f.store.historyParsedSearch.phrases.map(\.label) }

    private static func day(_ f: Fixture, _ day: Int) -> Date {
        f.calendar.date(from: DateComponents(year: 2023, month: 11, day: day))!
    }

    private static func followsMidnight() -> [String] {
        fixture { f, problems in
            let navigation = MainWindowModel(store: f.store)
            f.store.setHistoryQuery("yesterday")
            let hits = Set(f.store.historySearchHits(limit: .max).map(\.name))
            expect(labels(f) == ["Yesterday · Tue 14 Nov"] && hits == ["Parser"],
                   "before midnight: \(labels(f)), \(hits)", &problems)

            // The path the app runs: the tree's top moves, and History reconciles.
            let top = f.store.historyTop()
            f.clock.advance(86_400)
            expect(f.store.historyTop() != top, "the tree's top did not move at midnight, so History's hook would not run", &problems)
            navigation.reconcileHistory()
            expect(labels(f) == ["Yesterday · Wed 15 Nov"], "after midnight the chip reads \(labels(f))", &problems)
            expect(f.store.historyFilter.span == DateInterval(start: day(f, 15), end: day(f, 16)),
                   "the filter holds \(String(describing: f.store.historyFilter.span))", &problems)
            expect(f.store.historySearchHits(limit: .max).isEmpty,
                   "the hits did not follow: \(f.store.historySearchHits(limit: .max).map(\.name))", &problems)

            // History not yet opened when the day turned: opening reads it again.
            f.store.setHistoryQuery("today")
            f.clock.advance(86_400)
            MainWindowModel(store: f.store).prepareHistory()
            expect(labels(f) == ["Today · Fri 17 Nov"], "on opening, today reads \(labels(f))", &problems)

            f.store.setHistoryQuery("this week")
            f.clock.advance(3 * 86_400)
            navigation.reconcileHistory()
            expect(f.store.historyFilter.span == DateInterval(start: day(f, 20), end: day(f, 27)),
                   "this week on Mon 20 Nov holds \(String(describing: f.store.historyFilter.span))", &problems)
        }
    }

    private static func namesLoadLate() -> [String] {
        fixture { f, problems in
            f.store.historyAppNames = [:]
            f.store.setHistoryQuery("Safari")
            expect(f.store.historyParsedSearch.phrases.isEmpty && f.store.historyFilter.appBundleID == nil,
                   "an unknown name was read: \(labels(f))", &problems)
            f.store.refreshReview()
            expect(f.store.historyFilter.appBundleID == "com.apple.Safari" && labels(f) == ["Safari"]
                   && f.store.historyFilter.query.isEmpty,
                   "after the names loaded: \(labels(f)), app \(String(describing: f.store.historyFilter.appBundleID))", &problems)
        }
    }

    private static func zoneChange() -> [String] {
        fixture { f, problems in
            f.store.setHistoryQuery("yesterday")
            let before = f.store.historyFilter.span
            var base = Calendar.current
            base.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            f.store.periodCalendarBase = base
            let la = base.forPeriods
            let today = la.startOfDay(for: f.clock.value)
            let want = DateInterval(start: la.date(byAdding: .day, value: -1, to: today)!, end: today)
            expect(f.store.historyFilter.span == want && want != before,
                   "yesterday in Los Angeles holds \(String(describing: f.store.historyFilter.span)), not \(want)", &problems)
        }
    }

    private static func quiet() -> [String] {
        fixture { f, problems in
            let navigation = MainWindowModel(store: f.store)
            f.store.setHistoryQuery("yesterday Thesis")
            var published = 0
            let tap = f.store.objectWillChange.sink { published += 1 }
            f.store.refoldHistorySearch()
            f.store.refoldHistorySearch()
            navigation.reconcileHistory()
            tap.cancel()
            expect(published == 0, "an unchanged reading published \(published) times", &problems)
        }
    }

    private static func lengths() -> [String] {
        typealias Row = HistorySearchQueryChecks.Row
        let cases: [(String, Row)] = [
            ("over .5h", Row(min: 1_800, labels: ["Over 30m"])),
            ("under .25 hours", Row(max: 900, labels: ["Under 15m"])),
            ("over 1h30m", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("between 1 and 2 hours", Row(min: 3_600, max: 7_200, labels: ["1h–2h"])),
            ("between 30 and 90 minutes", Row(min: 1_800, max: 5_400, labels: ["30m–1h 30m"])),
            ("Sprint 42 between 1 and 2 hours", Row(min: 3_600, max: 7_200, leftover: "Sprint 42", labels: ["1h–2h"])),
        ]
        var problems: [String] = []
        for (text, row) in cases { HistorySearchQueryChecks.verify(text, row, &problems) }
        return problems
    }
}
