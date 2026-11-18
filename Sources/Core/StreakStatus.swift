import Foundation

/// The streak tile's one line: whether today has counted yet and, if not, what
/// keeps the run going. Printed minutes are subtracted, so "12m" and "13m
/// more" always add up to the "25m" minimum beside them.
enum StreakStatus {
    /// - Parameters:
    ///   - streak: the published streak, which includes today once it counts.
    ///   - today: today's focus so far, a running session included.
    static func line(streak: Int, today: TimeInterval, minimum: TimeInterval) -> String {
        guard today < minimum else { return "Today counts. Keep it going tomorrow." }
        let left = max(1, minutes(minimum) - minutes(today))
        let next = streak + 1
        return "\(DurationText.precise(TimeInterval(left * 60))) more focus today makes it "
            + (next == 1 ? "1 day." : "\(next) days.")
    }

    /// Whether the streak runs past the dots on screen, so the tile must say
    /// it shows only part of it. Today's dot is a counted one only once today
    /// counts; until then the streak is all in the earlier dots.
    static func outrunsDots(streak: Int, todayCounts: Bool, dots: Int) -> Bool {
        streak > (todayCounts ? dots : dots - 1)
    }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        (DurationText.wholeSeconds(seconds) ?? 0) / 60
    }
}
