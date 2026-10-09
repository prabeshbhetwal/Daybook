import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The inline Review detail is a projection of values Review has already
    /// published. It must never recompute time, never reach past the selected
    /// local day, and never survive a period or filter that no longer contains
    /// its date.
    static func testReviewSelectedDayDetail() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(periodAnchor())
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: clock.value)
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  let longAgo = calendar.date(byAdding: .day, value: -400, to: today),
                  let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday),
                  let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) else {
                return ["could not build Review detail fixture dates"]
            }

            // Early-morning offsets so every fixture moment stays in the past
            // whatever hour the suite runs at.
            let archive = makeArchive(clock)
            archive.append(SessionRecord(
                name: "Parser", workType: .deepWork,
                start: today.addingTimeInterval(3_600),
                end: today.addingTimeInterval(3_600 + 25 * 60),
                workSeconds: 25 * 60))
            archive.append(SessionRecord(
                name: "Lunch", workType: .breakTime,
                start: today.addingTimeInterval(2 * 3_600),
                end: today.addingTimeInterval(2 * 3_600 + 30 * 60),
                workSeconds: 30 * 60))
            archive.append(SessionRecord(
                name: "Stand-up", workType: .meetings,
                start: yesterday.addingTimeInterval(3_600),
                end: yesterday.addingTimeInterval(3_600 + 15 * 60),
                workSeconds: 15 * 60))
            archive.append(SessionRecord(
                name: "Night hand-off", workType: .deepWork,
                start: yesterday.addingTimeInterval(23 * 3_600 + 50 * 60),
                end: today.addingTimeInterval(10 * 60),
                workSeconds: 20 * 60))

            let usage = AppUsageArchive(directory: scratchDirectory(), now: { clock.value })
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: today.addingTimeInterval(3_600),
                end: today.addingTimeInterval(3_600 + 45 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.browser", appName: "Browser",
                start: today.addingTimeInterval(2 * 3_600 + 30 * 60),
                end: today.addingTimeInterval(2 * 3_600 + 50 * 60)))
            usage.record(AppUsageSession(
                bundleID: "com.example.editor", appName: "Editor",
                start: yesterday.addingTimeInterval(3_600),
                end: yesterday.addingTimeInterval(3_600 + 30 * 60)))

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
            store.refreshReview()

            guard let detail = store.reviewDayDetail(for: today, calendar: calendar) else {
                return problems + ["selected Review day should derive a detail"]
            }
            expect(calendar.isDate(detail.day.date, inSameDayAs: today),
                   "detail keeps the literal day", &problems)
            expectClose(detail.day.tracked, 65 * 60,
                        "detail uses canonical History tracked time", &problems)
            expectClose(detail.day.focused, 35 * 60,
                        "detail uses canonical History focused time", &problems)
            expect(detail.appEntries.allSatisfy { calendar.isDate($0.day, inSameDayAs: today) },
                   "detail log contains only the selected local day", &problems)
            expect(detail.appEntries.contains { $0.session.bundleID == "com.example.browser" },
                   "detail log keeps the selected day's own app evidence", &problems)
            expect(detail.focusEntries.allSatisfy { $0.start < endOfToday && $0.end > today },
                   "detail focus rows intersect the selected local day", &problems)
            expect(detail.focusEntries.count == 2
                       && detail.focusEntries.allSatisfy { $0.workType.countsAsFocus },
                   "detail focus rows exclude rest records", &problems)
            expect(detail.periodDay.map { calendar.isDate($0.date, inSameDayAs: today) } ?? false,
                   "detail carries the matching period bar", &problems)

            guard let yesterdayDetail = store.reviewDayDetail(for: yesterday, calendar: calendar),
                  let beforeMidnight = yesterdayDetail.focusEntries.first(where: {
                      $0.name == "Night hand-off"
                  }),
                  let afterMidnight = detail.focusEntries.first(where: {
                      $0.name == "Night hand-off"
                  }) else {
                return problems + ["cross-midnight focus should appear in both selected days"]
            }
            expect(beforeMidnight.start == yesterday.addingTimeInterval(23 * 3_600 + 50 * 60)
                       && beforeMidnight.end == endOfYesterday,
                   "previous-day detail clips a crossing focus range at midnight", &problems)
            expectClose(beforeMidnight.seconds, 10 * 60,
                        "previous-day detail clips a crossing focus duration", &problems)
            expect(afterMidnight.start == today
                       && afterMidnight.end == today.addingTimeInterval(10 * 60),
                   "next-day detail begins a crossing focus range at midnight", &problems)
            expectClose(afterMidnight.seconds, 10 * 60,
                        "next-day detail clips a crossing focus duration", &problems)

            expect(store.reviewDayDetail(for: longAgo, calendar: calendar) == nil,
                   "a day with no canonical History row derives no detail", &problems)
            return problems
        }
    }
}
