import Foundation

/// App stretches sorted by start, so the stretches inside a span are found by
/// bisection instead of a walk over the whole record.
struct SortedUsage {
    /// Every stretch History can draw, in start order.
    let stretches: [AppUsageSession]
    /// Stretches up to `shortLimit`: a span looks back only that far for one
    /// that reaches into it.
    private let short: [AppUsageSession]
    /// The rare longer ones, checked against every span. Looking back as far
    /// as the longest stretch made one day-long stretch slow every search.
    private let long: [AppUsageSession]

    static let shortLimit: TimeInterval = 2 * 3_600

    init(_ usage: [AppUsageSession]) {
        // A stretch longer than History draws any record is damaged, and is
        // refused here as `HistoryStats` refuses it.
        let bound = TimeInterval(HistoryStats.maximumCalendarDaysPerRecord) * 86_400
        let drawable = usage.filter { (stretch: AppUsageSession) -> Bool in
            stretch.end > stretch.start && stretch.seconds <= bound
        }
        stretches = drawable.sorted { $0.start < $1.start }
        short = stretches.filter { $0.seconds <= Self.shortLimit }
        long = stretches.filter { $0.seconds > Self.shortLimit }
    }

    /// Seconds each app was in front inside the spans, by bundle ID.
    func seconds(within spans: [DateInterval]) -> [String: TimeInterval] {
        var totals: [String: TimeInterval] = [:]
        forEachOverlap(spans) { stretch, piece in totals[stretch.bundleID, default: 0] += piece.duration }
        return totals
    }

    /// Each stretch's part inside each span, with the stretch it came from.
    func forEachOverlap(_ spans: [DateInterval], _ body: (AppUsageSession, DateInterval) -> Void) {
        func visit(_ stretch: AppUsageSession, _ span: DateInterval) {
            let start = max(stretch.start, span.start)
            let end = min(stretch.end, span.end)
            if end > start { body(stretch, DateInterval(start: start, end: end)) }
        }
        for span in spans {
            var index = firstIndex(startingAtOrAfter: span.start.addingTimeInterval(-Self.shortLimit))
            while index < short.count, short[index].start < span.end {
                visit(short[index], span)
                index += 1
            }
            for stretch in long where stretch.start < span.end { visit(stretch, span) }
        }
    }

    private func firstIndex(startingAtOrAfter date: Date) -> Int {
        var low = 0
        var high = short.count
        while low < high {
            let middle = (low + high) / 2
            if short[middle].start < date { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
