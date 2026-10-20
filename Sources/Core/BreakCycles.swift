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
}
