import Foundation

/// The hours of the day Ask's app time names, read from what the screen draws.
extension SessionStore {
    /// Seconds an app was in front in each clock hour of the period: History's
    /// per-app lens over the app's use clipped to it, in sessions and out.
    /// History's own app filter is neither read nor set.
    func askAppHours(bundleID: String, in interval: DateInterval) -> [TimeInterval] {
        let clipped = historySortedUsage().stretches.compactMap { stretch -> AppUsageSession? in
            guard stretch.bundleID == bundleID else { return nil }
            var piece = stretch
            piece.start = max(stretch.start, interval.start)
            piece.end = min(stretch.end, interval.end)
            return piece.end > piece.start ? piece : nil
        }
        let lens = appLens(bundleID: bundleID, usage: SortedUsage(clipped))
        return (0..<24).map { lens.hoursInSession[$0] + lens.hoursOutside[$0] }
    }

    /// Seconds recorded in each clock hour of one day: the hours the Story
    /// rail draws for it.
    func askRailHours(on day: Date) -> [TimeInterval] {
        var hours = Array(repeating: TimeInterval(0), count: 24)
        for hour in storyRailDay(on: day).rhythm {
            hours[Calendar.current.component(.hour, from: hour.hour)] += hour.seconds
        }
        return hours
    }
}
