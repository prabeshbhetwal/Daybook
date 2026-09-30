import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    static func testReviewHistoryFiltersAndDayRouting() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(periodAnchor())
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: clock.value)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) else {
                return ["could not build Review fixture dates"]
            }

            let archive = makeArchive(clock)
            archive.append(SessionRecord(
                name: "Plan", workType: .admin,
                start: twoDaysAgo.addingTimeInterval(30 * 60),
                end: twoDaysAgo.addingTimeInterval(38 * 60),
                workSeconds: 8 * 60))
            archive.append(SessionRecord(
                name: "Stand-up", workType: .meetings,
                start: yesterday.addingTimeInterval(60 * 60),
                end: yesterday.addingTimeInterval(75 * 60),
                workSeconds: 15 * 60))
            archive.append(SessionRecord(
                name: "Parser", workType: .deepWork,
                start: today.addingTimeInterval(2 * 3_600),
                end: today.addingTimeInterval(2 * 3_600 + 25 * 60),
                workSeconds: 25 * 60))

            let usage = AppUsageArchive(directory: scratchDirectory(), now: { clock.value })
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: twoDaysAgo.addingTimeInterval(30 * 60),
                end: twoDaysAgo.addingTimeInterval(40 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.browser", appName: "Browser",
                start: yesterday.addingTimeInterval(60 * 60),
                end: yesterday.addingTimeInterval(80 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: today.addingTimeInterval(2 * 3_600),
                end: today.addingTimeInterval(2 * 3_600 + 45 * 60)))

            let week = PeriodStats(sessions: archive, usage: usage,
                                   calendar: calendar, now: { clock.value })
                .rollup(for: .week, containing: today)
            let month = PeriodStats(sessions: archive, usage: usage,
                                    calendar: calendar, now: { clock.value })
                .rollup(for: .month, containing: today)
            let expectedTracked: [Date: TimeInterval] = [
                twoDaysAgo: 10 * 60,
                yesterday: 20 * 60,
                today: 45 * 60
            ]
            for point in PeriodChartData.tracked(week.days) {
                expectClose(point.seconds, expectedTracked[point.date] ?? 0,
                            "Week bar for \(point.date)", &problems)
            }
            for point in PeriodChartData.tracked(month.days) {
                expectClose(point.seconds, expectedTracked[point.date] ?? 0,
                            "Month bar for \(point.date)", &problems)
            }
            expectClose(week.summary.averagePerActiveDay, 25 * 60,
                        "Week average from the three tracked bars", &problems)
            expectClose(month.summary.averagePerActiveDay, 25 * 60,
                        "Month average from the three tracked bars", &problems)

            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()

            expect(store.historyDays.map(\.date) == [today, yesterday, twoDaysAgo],
                   "History is reverse chronological across usage and archive evidence",
                   &problems)
            if store.historyDays.count == 3 {
                expectClose(store.historyDays[0].tracked, 45 * 60,
                            "today History tracked", &problems)
                expectClose(store.historyDays[0].focused, 25 * 60,
                            "today History focused", &problems)
                expect(store.historyDays[0].sessions == 1,
                       "today History counts one thread", &problems)
            }
            expectClose(store.reviewLongestFocusSeconds, 25 * 60,
                        "Review longest focus stretch", &problems)
            expect(store.reviewLongestFocusName == "Parser",
                   "Review names the longest focus stretch", &problems)

            let query = HistoryFilter(query: "browser")
                .apply(to: store.historyDays)
            expect(query.map(\.date) == [yesterday],
                   "query matches the day's app evidence", &problems)

            let intersection = HistoryFilter(
                query: "browser",
                appBundleID: "com.example.browser",
                workType: .meetings
            ).apply(to: store.historyDays)
            expect(intersection.map(\.date) == [yesterday],
                   "query, app and work-type filters intersect", &problems)

            let impossibleIntersection = HistoryFilter(
                query: "browser",
                appBundleID: "com.example.browser",
                workType: .deepWork
            ).apply(to: store.historyDays)
            expect(impossibleIntersection.isEmpty,
                   "a day must satisfy every active History filter", &problems)

            guard let routedDate = PeriodChartData.tracked(week.days)
                .first(where: { $0.date == yesterday })?.date else {
                return problems + ["Week chart did not contain yesterday's literal date"]
            }
            let navigation = MainWindowModel(opening: .review)
            navigation.openHistory(day: routedDate)
            expect(navigation.workspace == .history,
                   "a selected Review bar keeps the user in History", &problems)
            expect(calendar.isDate(navigation.reviewSelectedDate ?? base,
                                   inSameDayAs: yesterday),
                   "a selected Review bar selects its literal date in Review", &problems)
            expect(navigation.requestedDate == nil,
                   "selecting a bar does not request a Today day", &problems)
            expect(calendar.isDate(store.selectedDay, inSameDayAs: today),
                   "the Review selection leaves Today's own selected day alone", &problems)
            return problems
        }
    }
}
