import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 40

    /// Two defects found by tracing what happens across a sleep.
    static func testSleepWakeTracking() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        // Zero idle throughout: the user is actively typing.
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })

        // An active stretch flushed while the user is typing must NOT be labelled
        // .idle. Comparing a trimmed end against a freshly sampled now() made that
        // true by microseconds, so every stretch claimed to be idle.
        tracker.appActivated(bundleID: "com.a", name: "Alpha")
        clock.advance(600)
        tracker.flush()
        expect(usage.sessions.last?.endReason == .stillOpen,
               "an active flush is .stillOpen, got "
               + "\(String(describing: usage.sessions.last?.endReason))", &problems)

        // Flushing repeatedly must not double-count the same seconds.
        clock.advance(300)
        tracker.flush()
        clock.advance(300)
        tracker.flush()
        let total = usage.sessions.filter { $0.bundleID == "com.a" }
            .reduce(0.0) { $0 + $1.seconds }
        expectClose(total, 1_200, "repeated flushes sum to the real elapsed time",
                    &problems)

        // Sleeping closes the stretch; waking into the SAME app must reopen it,
        // because no activation notification fires in that case.
        tracker.suspend()
        clock.advance(8 * 3_600)
        expect(tracker.currentBundleID == nil, "sleep closes the stretch", &problems)
        tracker.resume(bundleID: "com.a", name: "Alpha")
        expect(tracker.currentBundleID == "com.a",
               "waking into the same app reopens tracking", &problems)
        clock.advance(600)
        tracker.flush()
        let afterWake = usage.sessions.filter { $0.start >= base.addingTimeInterval(8 * 3_600) }
        expect(!afterWake.isEmpty, "work after waking is recorded", &problems)
        expect(afterWake.allSatisfy { $0.seconds <= 601 },
               "the overnight gap is not counted as usage", &problems)

        // resume() must not clobber an already-open stretch or track ourselves.
        tracker.resume(bundleID: "com.b", name: "Beta")
        expect(tracker.currentBundleID == "com.a",
               "resume does not replace an open stretch", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 41

    static func testPeriodStats() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)

        func use(_ daysAgo: Int, hours: Double) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return
            }
            let start = day.addingTimeInterval(10 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start,
                                         end: start.addingTimeInterval(hours * 3_600)))
        }
        use(0, hours: 2)
        use(1, hours: 1)

        let stats = PeriodStats(sessions: sessions, usage: usage, now: { clock.value })

        let week = stats.days(for: .week, containing: base)
        expect(week.count == 7, "a week has seven days, got \(week.count)", &problems)
        expectClose(week.reduce(0) { $0 + $1.tracked }, 3 * 3_600,
                    "the week's bars sum to the tracked total", &problems)

        let summary = stats.summary(for: .week, containing: base)
        expect(summary.activeDays == 2, "two active days, got \(summary.activeDays)",
               &problems)
        // Averaging a five-day week over seven understates every working day.
        expectClose(summary.averagePerActiveDay, 1.5 * 3_600,
                    "the average divides by active days", &problems)
        expectClose(summary.tracked, 3 * 3_600, "period total", &problems)
        expect(summary.totalDays == 7, "seven calendar days", &problems)

        let month = stats.days(for: .month, containing: base)
        expect(month.count >= 28 && month.count <= 31,
               "a month has 28 to 31 days, got \(month.count)", &problems)
        expect(stats.days(for: .day, containing: base).count == 1,
               "day is one day", &problems)

        // An empty period must be empty, never NaN.
        let emptyStats = PeriodStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                              now: { clock.value }),
                                     usage: AppUsageArchive(directory: scratchDirectory(),
                                                            now: { clock.value }),
                                     now: { clock.value })
        let emptySummary = emptyStats.summary(for: .week, containing: base)
        expect(emptySummary.activeDays == 0, "no active days", &problems)
        expectClose(emptySummary.averagePerActiveDay, 0, "average is 0, never NaN", &problems)
        expect(emptySummary.longest == nil, "no longest session", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    /// A period bar is one tracked-time fact. Focus composition belongs to the
    /// separate Work type donut and must not determine the bar's height.
    static func testPeriodChartUsesTrackedTime() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let sessions = SessionArchive(directory: directory, now: { clock.value })

        usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                     start: day.addingTimeInterval(9 * 3_600),
                                     end: day.addingTimeInterval(11 * 3_600)))
        sessions.append(SessionRecord(name: "Focused edit", workType: .deepWork,
                                      start: day.addingTimeInterval(9 * 3_600),
                                      end: day.addingTimeInterval(9.75 * 3_600),
                                      workSeconds: 45 * 60))

        let rollup = PeriodStats(sessions: sessions, usage: usage,
                                 calendar: calendar, now: { clock.value })
            .rollup(for: .day, containing: day)
        guard !rollup.days.isEmpty else {
            return ["the day rollup must contain one chart day"]
        }

        let points = PeriodChartData.tracked(rollup.days)
        expect(points.count == 1, "one selected day produces one period bar", &problems)
        expectClose(points.first?.seconds ?? -1, 2 * 3_600,
                    "the period chart point is exactly two tracked hours", &problems)
        expectClose(rollup.summary.averagePerActiveDay, 2 * 3_600,
                    "the tracked average is exactly two hours", &problems)
        return problems
    }

    /// Correcting an open checkpoint keeps the archive count unchanged. The
    /// cache must therefore key on revision, or it serves the old duration.
    static func testDashboardDaySliceInvalidatesOnRevision() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = Calendar.current.startOfDay(for: base)
        let identity = UUID()
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let sessions = SessionArchive(directory: directory, now: { clock.value })
        let original = AppUsageSession(id: identity, bundleID: "com.example.editor",
                                       appName: "Editor", start: day.addingTimeInterval(9 * 3_600),
                                       end: day.addingTimeInterval(10 * 3_600),
                                       endReason: .stillOpen)
        usage.checkpoint(original)
        let stats = DashboardStats(sessions: sessions, usage: usage,
                                   now: { clock.value })
        expectClose(stats.trackedTotal(for: day), 3_600,
                    "the initial day slice is one hour", &problems)

        let corrected = AppUsageSession(id: identity, bundleID: original.bundleID,
                                        appName: original.appName, start: original.start,
                                        end: day.addingTimeInterval(10.5 * 3_600),
                                        endReason: .stillOpen)
        usage.checkpoint(corrected)
        expect(usage.sessions.count == 1,
               "the corrected checkpoint keeps the archive count at one", &problems)
        expectClose(stats.trackedTotal(for: day), 1.5 * 3_600,
                    "the revised day slice is rebuilt to ninety minutes", &problems)
        return problems
    }
}
