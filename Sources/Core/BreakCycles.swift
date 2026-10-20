import Foundation

/// Work counted for one reminder: the seconds, and when the run began (nil when
/// there is none).
typealias BreakRun = (seconds: TimeInterval, start: Date?)

/// Rest rules that depend on how much was worked, not on one fixed length.
enum BreakCycles {

    /// Flow's run of work. Flow has no break length of its own: a gap is a rest
    /// when it reaches the suggestion for the work just before it (a fifth of
    /// it, 5 to 20 minutes), so a longer stretch needs a longer rest to count.
    ///
    /// `ordered` is newest end first and already clipped at the reminder's
    /// floor. The run is taken back to the first gap no suggestion can be
    /// longer than, then walked oldest first, starting the sum again at each
    /// gap that reaches the suggestion for the sum before it. The gap from the
    /// last stretch to `now` is tested the same way.
    static func flowRun(_ ordered: [AppUsageSession], now: Date) -> BreakRun {
        var newestFirst: [AppUsageSession] = []
        var boundary = now
        for stretch in ordered {
            if boundary.timeIntervalSince(stretch.end) >= BreakRhythm.flowLongest { break }
            newestFirst.append(stretch)
            boundary = stretch.start
        }
        var seconds: TimeInterval = 0
        var start: Date?
        var previousEnd: Date?
        for stretch in newestFirst.reversed() {
            if let previousEnd,
               stretch.start.timeIntervalSince(previousEnd) >= BreakRhythm.flowSuggestion(after: seconds) {
                (seconds, start) = (0, nil)
            }
            seconds += stretch.seconds
            start = start ?? stretch.start
            previousEnd = stretch.end
        }
        if let previousEnd,
           now.timeIntervalSince(previousEnd) >= BreakRhythm.flowSuggestion(after: seconds) {
            return (0, nil)
        }
        return (seconds, start)
    }

    /// Pomodoro cycles finished since the last long rest.
    ///
    /// `ordered` is newest end first and not clipped at any floor: Skip is not
    /// a rest. The run is taken back to the first gap of at least `longRest`,
    /// which started the count over, then walked oldest first. A gap is a
    /// credited rest when it reaches `rest` or holds a credit (a break ended
    /// early, so the record shows a shorter gap); one that comes after at
    /// least `work` since the one before is a cycle. The gap from the last
    /// stretch to `now` is tested the same way.
    static func completedCycles(_ ordered: [AppUsageSession], now: Date, credits: [Date],
                                work: TimeInterval, rest: TimeInterval, longRest: TimeInterval) -> Int {
        var newestFirst: [AppUsageSession] = []
        var boundary = now
        for stretch in ordered {
            if boundary.timeIntervalSince(stretch.end) >= longRest { break }
            newestFirst.append(stretch)
            boundary = stretch.start
        }
        func rested(_ from: Date, _ to: Date) -> Bool {
            to.timeIntervalSince(from) >= rest || credits.contains { $0 >= from && $0 <= to }
        }
        var cycles = 0
        var worked: TimeInterval = 0
        var previousEnd: Date?
        for stretch in newestFirst.reversed() {
            if let previousEnd, rested(previousEnd, stretch.start) {
                if worked >= work { cycles += 1 }
                worked = 0
            }
            worked += stretch.seconds
            previousEnd = stretch.end
        }
        if let previousEnd, rested(previousEnd, now), worked >= work { cycles += 1 }
        return cycles
    }

    /// The long break the main prompt becomes, when the rhythm has one and the
    /// cycles since the last long rest say it is next: all but the last of
    /// `longEvery` are done. More than that still reads as next, so a long
    /// break put off stays owed until a long rest is taken.
    static func longBreakNext(plan: BreakPlan, ordered: [AppUsageSession], now: Date,
                              credits: [Date]) -> TimeInterval? {
        guard let rhythm = plan.rhythm, let every = rhythm.longEvery, let length = rhythm.longLength,
              let work = rhythm.work, let rest = plan.creditGap else { return nil }
        let done = completedCycles(ordered, now: now, credits: credits,
                                   work: work, rest: rest, longRest: length)
        return done >= every - 1 ? length : nil
    }
}
