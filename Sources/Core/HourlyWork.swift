import Foundation

/// Work filed under the clock hours it happened in.
///
/// The hours are the calendar's real intervals. Setting the hour by number
/// landed on the repeated hour's first pass on the night the clocks go back,
/// behind the cursor, and the walk stopped there with the rest of the day
/// uncounted. The work comes from the caller's pause-aware allocation, so a
/// pause stays in the hours it happened instead of thinning every hour of
/// the span.
enum HourlyWork {
    /// Calls `body` once per clock hour between `start` and `end`, with the
    /// slice's start, its hour of day, and the work `work` puts in it.
    static func forEachHour(from start: Date, to end: Date, calendar: Calendar,
                            work: ((start: Date, end: Date)) -> TimeInterval,
                            _ body: (_ sliceStart: Date, _ hour: Int, _ seconds: TimeInterval) -> Void) {
        var cursor = start
        while cursor < end {
            let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end
            let sliceEnd = min(end, hourEnd.flatMap { $0 > cursor ? $0 : nil }
                               ?? cursor.addingTimeInterval(3_600))
            let seconds = min(sliceEnd.timeIntervalSince(cursor), work((start: cursor, end: sliceEnd)))
            body(cursor, calendar.component(.hour, from: cursor), seconds)
            cursor = sliceEnd
        }
    }
}
