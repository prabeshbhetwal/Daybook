import Foundation

/// The rail's figures in whole minutes, as they are printed. Each total is
/// the sum of its printed parts and each difference is taken between printed
/// figures, so what the reader adds up on screen always adds up. Seconds
/// rounded separately had a goal of 4h 43m beside "In a focus session 4h 44m"
/// and a "5h" beside parts summing to 4h 59m.
enum StoryRailFigures {
    /// Whole minutes, rounded down as `Tokens.preciseDuration` prints them. A
    /// length no session can have reads as none rather than trapping.
    static func minutes(_ seconds: TimeInterval) -> Int {
        (DurationText.wholeSeconds(seconds) ?? 0) / 60
    }

    /// "5h 16m logged − 33m with no app use recorded": how the goal's figure
    /// comes from the headline's. Nil when nothing was taken away.
    static func goalEquation(logged: TimeInterval, counted: TimeInterval) -> String? {
        let gap = minutes(logged) - minutes(counted)
        guard gap > 0 else { return nil }
        return "\(Tokens.duration(TimeInterval(minutes(logged) * 60))) logged − "
            + "\(Tokens.duration(TimeInterval(gap * 60))) with no app use recorded"
    }

    struct MacRows: Equatable {
        /// The goal's own figure: app use that counted as focus.
        let duringFocus: Int
        /// App use inside a session's span that did not count: its pauses.
        let duringPauses: Int
        let outside: Int
        var total: Int { duringFocus + duringPauses + outside }
    }

    /// Recorded app use split three ways that add up to the whole.
    static func macRows(tracked: TimeInterval, insideSessions: TimeInterval,
                        countedFocus: TimeInterval) -> MacRows {
        let focus = min(countedFocus, insideSessions)
        return MacRows(duringFocus: minutes(focus),
                       duringPauses: minutes(max(0, insideSessions - focus)),
                       outside: minutes(max(0, tracked - insideSessions)))
    }
}
