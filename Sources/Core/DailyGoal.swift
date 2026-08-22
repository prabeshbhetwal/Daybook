import Foundation

/// One day's progress toward a personal focus target. `share` is left
/// uncapped (not clamped to 1) so the UI can render "160% of your goal";
/// `isMet` is the boolean it branches on instead.
struct GoalProgress: Equatable {
    let goal: TimeInterval
    let achieved: TimeInterval
    let share: Double
    let isMet: Bool
    let typicalByNow: TimeInterval?
    let aheadBy: TimeInterval?

    /// One place where the four derived figures are worked out, so a caller
    /// rebuilding this every second from a cached median cannot drift from one
    /// built the slow way.
    init(goal: TimeInterval, achieved: TimeInterval, typical: TimeInterval?) {
        self.goal = goal
        self.achieved = achieved
        self.share = goal > 0 ? achieved / goal : 0
        self.isMet = achieved >= goal
        self.typicalByNow = typical
        self.aheadBy = typical.map { achieved - $0 }
    }
}

/// Judges progress against the user's own history rather than the clock.
/// A goal set for an 8-hour day looks "behind" at 10am on every single day
/// if judged against the full target, so `typicalByNow` instead answers
/// "what did I usually have by this same hour?" — the fair comparison.
struct DailyGoal {

    private let archive: SessionArchive
    private let goal: TimeInterval
    private let usage: [AppUsageSession]
    private let running: (start: Date, end: Date)?
    private let runningWork: TimeInterval?
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - usage: hands-on stretches, already idle-trimmed and system-filtered.
    ///     Empty means the goal reads zero, which is correct: with no record of
    ///     anyone at the keyboard there is no evidence of work.
    ///   - running: the in-flight session's span, or nil when idle.
    init(archive: SessionArchive,
         goal: TimeInterval,
         usage: [AppUsageSession] = [],
         running: (start: Date, end: Date)? = nil,
         runningWork: TimeInterval? = nil,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.archive = archive
        self.goal = goal
        self.usage = usage
        self.running = running
        self.runningWork = runningWork
        self.calendar = calendar
        self.now = now
    }

    func progress() -> GoalProgress {
        GoalProgress(goal: goal, achieved: achievedToday(), typical: typicalByNow())
    }

    /// The part that changes every second, separated from the fourteen-day walk
    /// that does not. The store recomputes this at 1 Hz and reuses a cached
    /// median, because the bar sitting frozen while the timer beneath it ticked
    /// was itself a reported defect.
    /// Deliberately not `archive.workSeconds(on:)`: a session that ran is a fact,
    /// and `todayTotal`, the week chart and the streak all rightly report it.
    /// The goal is a different kind of claim — it asserts effort — and only the
    /// intersection with hands-on time can carry that.
    func achievedToday() -> TimeInterval {
        FocusedActiveTime.seconds(on: now(), records: archive.records,
                                  usage: usage, running: running,
                                  runningWork: runningWork,
                                  calendar: calendar)
    }

    func typical() -> TimeInterval? { typicalByNow() }

    // MARK: - Personal median

    /// Median focused seconds reached by this same hour of day, over the
    /// trailing `goalMedianWindowDays` — counting only active days, for the
    /// same reason `PeriodStats.averagePerActiveDay` divides by active days
    /// rather than calendar days: folding zeros in understates every real
    /// working day. Below `goalMedianMinimumDays` active days there is no
    /// median worth quoting, so this returns nil rather than fabricate one.
    private func typicalByNow() -> TimeInterval? {
        let current = now()
        let cutoffSeconds = secondsSinceMidnight(current)
        var reached: [TimeInterval] = []

        for offset in 1...FocusConstants.goalMedianWindowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else {
                continue
            }
            // Day-split, so a day whose work was donated to its successor is no
            // longer mistaken for a day off. Friday used to vanish from this
            // median entirely because the session covering it happened to be
            // stopped on Saturday.
            guard archive.workSeconds(on: day) > 0 else { continue }
            reached.append(secondsByCutoff(archive.records(on: day),
                                           dayStart: calendar.startOfDay(for: day),
                                           cutoffSeconds: cutoffSeconds))
        }

        guard reached.count >= FocusConstants.goalMedianMinimumDays else { return nil }
        let value = median(of: reached)
        // A zero median is an artefact, not a fact about the user: someone who
        // works one long session a day has nothing *ended* before the cutoff on
        // most days. Reporting it would say "2h 30m ahead of usual" to somebody
        // having an ordinary morning.
        return value > 0 ? value : nil
    }

    /// Elapsed seconds since local midnight — the cutoff applied to every day
    /// in the comparison, so "by this hour" means the same clock time on each.
    private func secondsSinceMidnight(_ date: Date) -> TimeInterval {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }

    /// Work done on this day *before* the matching clock time.
    ///
    /// This used to weight each record by how much of its whole span fell before
    /// the cutoff, on top of the archive's end-day rule — two different guesses
    /// stacked. A record covering a night then reported most of its work as
    /// having happened by mid-afternoon of the following day. Now the day
    /// window and the cutoff are one range, and `workSeconds(in:)` is the single
    /// rule that splits a record.
    private func secondsByCutoff(_ records: [SessionRecord],
                                 dayStart: Date,
                                 cutoffSeconds: TimeInterval) -> TimeInterval {
        let cutoff = dayStart.addingTimeInterval(cutoffSeconds)
        guard cutoff > dayStart else { return 0 }
        return records.reduce(0) { $0 + $1.workSeconds(in: (dayStart, cutoff)) }
    }

    private func median(of values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        guard sorted.count.isMultiple(of: 2) else { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}
