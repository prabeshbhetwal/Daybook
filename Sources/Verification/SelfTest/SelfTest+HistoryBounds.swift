import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The archive may hold 5,000 records, but Review must not eagerly compose
    /// them all. The row cap prefers newest stretches while full-period totals,
    /// longest focus, work types and thread counts remain uncapped.
    static func testReviewFocusRowsAreBoundedAndQualified() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(anchoredNow())
            let calendar = Calendar.current
            guard let bounds = calendar.weeksFromMonday.dateInterval(of: .weekOfYear,
                                                      for: clock.value) else {
                return ["could not build dense focus Review bounds"]
            }
            var records: [SessionRecord] = []
            for index in 0..<510 {
                let start = bounds.start.addingTimeInterval(3_600 + Double(index * 60))
                let seconds: TimeInterval = index == 0 ? 120 : 60
                records.append(SessionRecord(
                    name: "Focus \(index)",
                    workType: index == 0 ? .learning : .deepWork,
                    start: start, end: start.addingTimeInterval(seconds),
                    workSeconds: seconds))
            }
            let archive = makeArchive(clock, records: records, calendar: calendar)
            let usage = makeUsageArchive(clock, sessions: [],
                                         accurateFrom: bounds.start)
            let persistence = PersistenceStore(
                defaults: MemoryDefaults.suite(named: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview(period: .week)

            expect(store.reviewFocusSessions.count == 510,
                   "full focus evidence remains available to summaries", &problems)
            expect(store.reviewFocusSessionRows.count == 500,
                   "focus presentation is capped at 500 rows", &problems)
            expect(store.reviewFocusSessionRows.first?.name == "Focus 509"
                       && store.reviewFocusSessionRows.last?.name == "Focus 10",
                   "bounded rows retain the deterministic newest 500", &problems)
            expect(store.reviewFocusRowsOmitted == 10,
                   "the omitted row count is exact", &problems)
            expect(store.reviewFocusRowsQualification
                       == "Showing newest 500 of 510 stretches",
                   "the row cap is stated plainly", &problems)

            expect(store.reviewFocusSessionCount == 510
                       && store.reviewSummaryLine.contains("510 focus sessions"),
                   "session summary remains uncapped", &problems)
            expectClose(store.reviewFocusSessions.reduce(0) { $0 + $1.seconds },
                        511 * 60, "full focused total", &problems)
            expect(store.reviewLongestFocusName == "Focus 0"
                       && store.reviewLongestFocusSeconds == 120,
                   "the omitted oldest row can still be the true longest", &problems)
            expect(store.reviewWorkTypeShares.contains {
                $0.workType == .learning && $0.seconds == 120
            }, "work-type evidence includes an omitted row", &problems)
            return problems
        }
    }

    /// Search copy promises app names. The displayed name can be unrelated to
    /// the bundle ID, so matching only the identifier breaks that promise.
    static func testHistorySearchesDisplayedAppName() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(base)
            let day = Calendar.current.startOfDay(for: clock.value)
            let usage = makeUsageArchive(clock, sessions: [
                AppUsageSession(bundleID: "org.example.product", appName: "Quill Writer",
                                start: day.addingTimeInterval(600),
                                end: day.addingTimeInterval(1_200))
            ], accurateFrom: day)
            let persistence = PersistenceStore(
                defaults: MemoryDefaults.suite(named: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(
                store: persistence, archive: makeArchive(clock),
                ownBundleID: "com.example.self", schedulesDwell: false,
                now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()
            store.setHistoryQuery("quill writer")

            expect(!"org.example.product".contains("quill"),
                   "fixture name remains independent of its bundle ID", &problems)
            expect(store.filteredHistoryDays.map(\.date) == [day],
                   "History query matches the stable displayed app name", &problems)
            return problems
        }
    }

    /// One malformed decoded record must not allocate hundreds of derived day
    /// rows. Ordinary cross-midnight evidence still clips exactly to both days.
    static func testHistoryBoundsMalformedSpans() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let firstDay = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2024, month: 1, day: 1)),
              let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay),
              let malformedStart = calendar.date(byAdding: .day, value: -500,
                                                  to: firstDay) else {
            return ["could not build malformed History fixture"]
        }
        let crossingStart = firstDay.addingTimeInterval(23 * 3_600 + 50 * 60)
        let crossingEnd = secondDay.addingTimeInterval(10 * 60)
        let usage = [
            AppUsageSession(bundleID: "org.example.normal", appName: "Normal",
                            start: crossingStart, end: crossingEnd),
            AppUsageSession(bundleID: "org.example.malformed", appName: "Malformed",
                            start: malformedStart, end: secondDay.addingTimeInterval(12 * 3_600))
        ]
        let records = [
            SessionRecord(name: "Normal focus", workType: .deepWork,
                          start: crossingStart, end: crossingEnd,
                          workSeconds: 20 * 60),
            SessionRecord(name: "Malformed focus", workType: .admin,
                          start: malformedStart,
                          end: secondDay.addingTimeInterval(12 * 3_600),
                          workSeconds: 501 * 86_400)
        ]

        let result = HistoryStats.build(sessionRecords: records, usage: usage,
                                        calendar: calendar)
        let days = result.days
        expect(days.map(\.date) == [secondDay, firstDay],
               "malformed distant records add no derived days", &problems)
        if days.count == 2 {
            expectClose(days[0].tracked, 10 * 60,
                        "midnight usage after boundary", &problems)
            expectClose(days[1].tracked, 10 * 60,
                        "midnight usage before boundary", &problems)
            expectClose(days[0].focused, 10 * 60,
                        "midnight focus after boundary", &problems)
            expectClose(days[1].focused, 10 * 60,
                        "midnight focus before boundary", &problems)
        }
        expect(usage.count == 2 && records.count == 2,
               "derived bounding never mutates source records", &problems)
        expect(result.droppedUsageSpans == 1,
               "the omitted span-bound usage record is counted for disclosure", &problems)
        expect(result.droppedFocusSpans == 1 && result.droppedRestSpans == 0,
               "the omitted span-bound focus record is counted for disclosure", &problems)
        return problems
    }

    /// History keeps legacy evidence visible, but it must qualify its recording
    /// guarantee and disclose every record omitted only from the bounded derived
    /// index. Neither notice permits mutation of the preserved source archives.
    static func testHistoryDisclosesLegacyAndDroppedSpans() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchoredNow())
        let clock = TestClock(today.addingTimeInterval(12 * 3_600))
        guard let legacyDay = calendar.date(byAdding: .day, value: -2, to: today),
              let malformedStart = calendar.date(byAdding: .day, value: -500, to: today),
              let accurateFrom = calendar.date(byAdding: .day, value: -1, to: today)?
                .addingTimeInterval(12 * 3_600) else {
            return ["could not build History disclosure dates"]
        }
        let legacyStart = legacyDay.addingTimeInterval(9 * 3_600)
        let malformedEnd = today.addingTimeInterval(10 * 3_600)
        let usageSessions = [
            AppUsageSession(bundleID: "org.example.legacy", appName: "Legacy",
                            start: legacyStart, end: legacyStart.addingTimeInterval(30 * 60)),
            AppUsageSession(bundleID: "org.example.malformed", appName: "Malformed",
                            start: malformedStart, end: malformedEnd)
        ]
        let sessionRecords = [
            SessionRecord(name: "Legacy focus", workType: .learning,
                          start: legacyStart, end: legacyStart.addingTimeInterval(30 * 60),
                          workSeconds: 30 * 60),
            SessionRecord(name: "Malformed focus", workType: .deepWork,
                          start: malformedStart, end: malformedEnd,
                          workSeconds: 500 * 86_400),
            SessionRecord(name: "Malformed break", workType: .breakTime,
                          start: malformedStart.addingTimeInterval(60),
                          end: malformedEnd,
                          workSeconds: 500 * 86_400)
        ]
        let usage = makeUsageArchive(clock, sessions: usageSessions,
                                     accurateFrom: accurateFrom)
        let archive = makeArchive(clock, records: sessionRecords, calendar: calendar)
        let persistence = PersistenceStore(
            defaults: MemoryDefaults.suite(named: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.refreshReview()

        expect(store.historyIntegrityNotices.contains {
            $0.contains(Tokens.longDate(accurateFrom))
                && $0.localizedCaseInsensitiveContains("legacy")
        }, "History qualifies preserved pre-accuracy app usage", &problems)
        expect(store.historyIntegrityNotices.contains {
            $0.contains("1 app-usage record") && $0.contains("1 focus record")
                && $0.contains("1 rest record")
                && $0.localizedCaseInsensitiveContains("source records remain preserved")
        }, "History distinguishes focus/rest span omissions and source preservation",
               &problems)
        expect(usage.sessions == usageSessions && archive.records == sessionRecords,
               "History disclosure never rewrites either source archive", &problems)
        return problems
    }
}
