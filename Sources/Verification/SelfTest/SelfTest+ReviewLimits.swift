import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Row presentation retains the newest 500, while exact period aggregates
    /// remain separately available from all source sessions. A bound must never
    /// silently turn Top Apps into "Top apps among the newest rows".
    static func testPeriodLogRetainsNewestLimit() -> [String] {
        var problems: [String] = []
        // The calendar Review reads months in. A fixture laid out in UTC put
        // 1 November's first sessions on 31 October west of Greenwich.
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2023, month: 11, day: 1)),
              let recentDay = calendar.date(byAdding: .day, value: 28, to: monthStart),
              let anchor = calendar.date(byAdding: .hour, value: 12, to: recentDay) else {
            return ["could not build the bounded period fixture"]
        }
        let clock = TestClock(anchor)
        var stretches: [AppUsageSession] = []
        for index in 0..<500 {
            let dayOffset = index / 18
            let slot = index % 18
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: monthStart),
                  let start = calendar.date(byAdding: .minute, value: slot * 10, to: day) else {
                return ["could not build old period usage"]
            }
            stretches.append(AppUsageSession(
                bundleID: "org.example.archive", appName: "Archive",
                start: start, end: start.addingTimeInterval(60)))
        }
        for slot in 0..<10 {
            guard let start = calendar.date(byAdding: .minute, value: slot * 10,
                                            to: recentDay) else {
                return ["could not build recent period usage"]
            }
            stretches.append(AppUsageSession(
                bundleID: "org.example.current", appName: "Current",
                start: start, end: start.addingTimeInterval(60)))
        }

        let usage = makeUsageArchive(clock, sessions: stretches, accurateFrom: monthStart)
        let archive = SessionArchive(directory: scratchDirectory(), calendar: calendar,
                                     now: { clock.value })
        let stats = PeriodStats(sessions: archive, usage: usage,
                                calendar: calendar, now: { clock.value })
        let rollup = stats.rollup(for: .month, containing: anchor)
        let separateLog = stats.log(for: .month, containing: anchor)

        expect(rollup.log.count == 500,
               "period rollup retains exactly 500 entries, got \(rollup.log.count)", &problems)
        expect(Array(rollup.log.prefix(10)).allSatisfy {
            $0.session.bundleID == "org.example.current"
        }, "the newest ten sessions survive the cap", &problems)
        expect(separateLog == rollup.log,
               "standalone log and rollup retain the identical set", &problems)
        expect(rollup.totalLogEntries == 510 && rollup.logRowsOmitted == 10,
               "the bounded row model carries its exact full-period count", &problems)
        expectClose(rollup.dayTotals.values.reduce(0, +),
                    rollup.log.reduce(0) { $0 + $1.session.attended },
                   "retained day totals", &problems)
        let groups = rollup.exactAppGroups
        expectClose(groups.first(where: { $0.bundleID == "org.example.current" })?.total ?? -1,
                    10 * 60, "recent app exact total", &problems)
        expectClose(groups.first(where: { $0.bundleID == "org.example.archive" })?.total ?? -1,
                    500 * 60, "old app exact full-period total", &problems)
        expectClose(groups.reduce(0) { $0 + $1.total }, 510 * 60,
                    "exact app groups remain separate from bounded rows", &problems)

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
        store.reviewAnchor = anchor
        store.refreshReview(period: .month)
        expect(store.reviewLog.count == 500 && store.reviewLogTotalEntries == 510
                   && store.reviewLogRowsOmitted == 10,
               "Review publishes bounded rows beside the exact source count", &problems)
        expect(store.reviewLogRowsQualification
                   == "Showing newest 500 of 510 app-session rows",
               "Review labels the bounded chronological rows", &problems)
        expect(store.reviewAppAggregateQualification
                   == "Exact full period · 510 app sessions",
               "Review labels Top Apps as an exact full-period aggregate", &problems)
        expectClose(store.reviewAppGroups.reduce(0) { $0 + $1.total }, 510 * 60,
                    "Review Top Apps consumes every full-period session", &problems)
        guard let oldDayDetail = store.reviewDayDetail(for: monthStart, calendar: calendar) else {
            return problems + ["oldest dense-period day should open a Review detail"]
        }
        expect(oldDayDetail.appEntries.count == 18,
               "selected-day app detail retains every old-day entry beyond the period log cap",
               &problems)
        expectClose(oldDayDetail.appEntries.reduce(0) { $0 + $1.session.attended }, 18 * 60,
                    "selected-day app detail retains the old day's exact tracked evidence",
                    &problems)
        return problems
    }

    /// A dense period log is intentionally capped at 500 chronological rows,
    /// but selecting a day must still expose every app session that belongs to
    /// that literal day. If detail reads the capped period list, one real app
    /// disappears as soon as the period reaches 501 rows.
    static func testReviewDetailRetainsUncappedDayEntries() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(anchoredNow())
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: clock.value)
            let start = day.addingTimeInterval(3_600)
            let sessions = (0...500).map { index in
                AppUsageSession(bundleID: "org.example.day.\(index)",
                                appName: "Day app \(index)",
                                start: start,
                                end: start.addingTimeInterval(60))
            }
            let usage = makeUsageArchive(clock, sessions: sessions, accurateFrom: day)
            let persistence = PersistenceStore(
                defaults: MemoryDefaults.suite(named: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: makeArchive(clock),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview(period: .month)

            expect(store.reviewLog.count == 500 && store.reviewLogTotalEntries == 501,
                   "the chronological Review log applies its 500-row display cap", &problems)
            guard let detail = store.reviewDayDetail(for: day, calendar: calendar) else {
                return problems + ["the dense selected day should derive a Review detail"]
            }
            expect(detail.appEntries.count == 501,
                   "selected-day app detail retains all 501 canonical entries", &problems)
            expect(Set(detail.appEntries.map(\.session.bundleID)).count == 501,
                   "selected-day app detail loses no app identity beyond the cap", &problems)
            expectClose(detail.appEntries.reduce(0) { $0 + $1.session.attended }, 501 * 60,
                        "selected-day app detail retains exact tracked evidence", &problems)
            return problems
        }
    }

    /// Tracked time can legitimately be absent while the archive still contains
    /// focus records. Review must keep that evidence visible and label the
    /// missing tracked series rather than replacing the whole period with empty.
    static func testReviewFocusOnlyPeriodEvidence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(base)
            let calendar = Calendar.current
            guard let bounds = calendar.weeksFromMonday.dateInterval(of: .weekOfYear,
                                                      for: clock.value) else {
                return ["could not build focus-only Review bounds"]
            }
            let archive = makeArchive(clock)
            let focusThread = UUID()
            archive.append(SessionRecord(
                name: "Write proposal", workType: .deepWork,
                start: bounds.start.addingTimeInterval(2 * 3_600),
                end: bounds.start.addingTimeInterval(2 * 3_600 + 45 * 60),
                workSeconds: 45 * 60, threadID: focusThread))
            archive.append(SessionRecord(
                name: "Write proposal", workType: .deepWork,
                start: bounds.start.addingTimeInterval(6 * 3_600),
                end: bounds.start.addingTimeInterval(6 * 3_600 + 15 * 60),
                workSeconds: 15 * 60, threadID: focusThread))
            archive.append(SessionRecord(
                name: "Lunch", workType: .breakTime,
                start: bounds.start.addingTimeInterval(4 * 3_600),
                end: bounds.start.addingTimeInterval(5 * 3_600),
                workSeconds: 60 * 60))
            let usage = makeUsageArchive(clock, sessions: [], accurateFrom: bounds.start)
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

            expect(store.reviewSummary.tracked == 0
                       && store.reviewSummary.activeDays == 0,
                   "focus-only fixture has no tracked series", &problems)
            expect(store.reviewHasRelevantEvidence,
                   "focus-only archive evidence defeats Review empty", &problems)
            expect(store.reviewFocusSessions.count == 2,
                   "both focus stretches remain available to Review", &problems)
            expect(store.reviewFocusSessions.allSatisfy {
                $0.name == "Write proposal" && $0.workType == .deepWork
            }, "focus-only stretches keep their name and type", &problems)
            expectClose(store.reviewFocusSessions.reduce(0) { $0 + $1.seconds },
                        60 * 60, "focus-only session duration", &problems)
            expect(store.reviewSummaryLine.contains("No tracked time")
                       && store.reviewSummaryLine.contains("1 focus session"),
                   "focus-only summary counts the shared thread once", &problems)
            return problems
        }
    }
}
