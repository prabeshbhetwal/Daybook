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
    private let usageAccurateFrom: Date?
    private let running: (start: Date, end: Date)?
    private let runningWork: TimeInterval?
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - usage: hands-on stretches, already idle-trimmed and system-filtered.
    ///     Empty means the goal reads zero, which is correct: with no record of
    ///     anyone at the keyboard there is no evidence of work.
    ///   - running: the in-flight session's span, or nil when idle.
    private let windowDays: Int

    init(archive: SessionArchive,
         goal: TimeInterval,
         usage: [AppUsageSession] = [],
         usageAccurateFrom: Date? = nil,
         running: (start: Date, end: Date)? = nil,
         runningWork: TimeInterval? = nil,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init,
         windowDays: Int = FocusConstants.goalMedianWindowDays) {
        self.windowDays = max(1, windowDays)
        self.archive = archive
        self.goal = goal
        self.usage = usage
        self.usageAccurateFrom = usageAccurateFrom
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

    /// Median focused-active seconds reached by this same hour of day, over
    /// the trailing `goalMedianWindowDays`. A pace sample requires both an
    /// active focused interval and usage recorded after its authoritative
    /// epoch; a historical raw session is not evidence for this comparison.
    private func typicalByNow() -> TimeInterval? {
        let current = now()
        var reached: [TimeInterval] = []
        guard let firstAccurateDay = firstCompleteAccurateDay() else { return nil }

        for offset in 1...windowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else {
                continue
            }
            let dayStart = calendar.startOfDay(for: day)
            // The migration day can contain old checkpoint semantics before
            // `accurateFrom`, so the next complete calendar day is the first
            // fair historical comparator.
            guard dayStart >= firstAccurateDay else { continue }
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }
            let fullDay = FocusedActiveTime.seconds(
                in: DateInterval(start: dayStart, end: dayEnd),
                records: archive.records, usage: usage, running: nil)
            guard fullDay > 0 else { continue }

            // Eligibility is full-day focused activity; the stored sample is
            // the same local clock-time interval and may validly be zero.
            let cutoff = historicalCutoff(on: dayStart, ending: dayEnd, matching: current)
            reached.append(FocusedActiveTime.seconds(
                in: DateInterval(start: dayStart, end: cutoff),
                records: archive.records, usage: usage, running: nil))
        }

        guard reached.count >= FocusConstants.goalMedianMinimumDays else { return nil }
        return median(of: reached)
    }

    /// `accurateFrom` is a point within the migration calendar day, not a
    /// licence to combine its old and new checkpoint semantics. Start with the
    /// following full local day regardless of the migration time.
    private func firstCompleteAccurateDay() -> Date? {
        guard let usageAccurateFrom else { return nil }
        return calendar.date(byAdding: .day, value: 1,
                             to: calendar.startOfDay(for: usageAccurateFrom))
    }

    /// The historical interval ends at today's local wall-clock time. `nextTime`
    /// resolves a missing spring-forward time, `.first` chooses the first
    /// repeated fall-back time, and clamping prevents a short DST day spilling
    /// into its successor.
    private func historicalCutoff(on dayStart: Date, ending dayEnd: Date,
                                  matching current: Date) -> Date {
        var time = calendar.dateComponents([.hour, .minute, .second], from: current)
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        let candidate = calendar.nextDate(
            after: dayStart.addingTimeInterval(-1), matching: time,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first,
            direction: .forward) ?? dayEnd
        return min(max(candidate, dayStart), dayEnd)
    }

    private func median(of values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        guard sorted.count.isMultiple(of: 2) else { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}
