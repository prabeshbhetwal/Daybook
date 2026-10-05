import Foundation

/// One hour of the day's rhythm: how long the Mac was in use, and which app
/// (by its day rank) took most of it. Pure, so the chart can be tested without
/// a window.
struct RhythmHour: Identifiable, Equatable {
    let hour: Date
    let seconds: TimeInterval
    /// The dominant app's palette index for the hour; 6 (Other) when nothing
    /// was recorded, which the chart draws as an empty slot.
    let colorIndex: Int
    var id: Date { hour }
}

enum Rhythm {
    /// Splits the day's segments across hour boundaries and sums them per hour
    /// inside `window`. Capped at 48 hours: a window is at most one day plus
    /// its overhang.
    static func hours(segments: [TimelineSegment],
                      window: (start: Date, end: Date),
                      calendar: Calendar = .current) -> [RhythmHour] {
        guard window.end > window.start,
              var cursor = calendar.dateInterval(of: .hour, for: window.start)?.start
        else { return [] }
        var result: [RhythmHour] = []
        while cursor < window.end && result.count < 48 {
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            var byColor: [Int: TimeInterval] = [:]
            var total: TimeInterval = 0
            for segment in segments {
                let start = max(segment.start, cursor)
                let end = min(segment.end, next)
                guard end > start else { continue }
                let seconds = end.timeIntervalSince(start)
                total += seconds
                byColor[segment.colorIndex, default: 0] += seconds
            }
            let dominant = byColor.max { left, right in
                left.value == right.value ? left.key > right.key : left.value < right.value
            }?.key ?? 6
            result.append(RhythmHour(hour: cursor, seconds: total, colorIndex: dominant))
            cursor = next
        }
        return result
    }

    /// Twenty-four clock hours, 12 am to 11 pm, for figures summed over many
    /// days. They sit on a fixed day with no clock change: on a day whose
    /// clocks go forward, start of day plus 2 hours is 3 am, and every label
    /// after it reads an hour late.
    static func clockHours(colorIndex: Int, calendar: Calendar,
                           seconds: (Int) -> TimeInterval) -> [RhythmHour] {
        var reference = DateComponents()
        reference.calendar = calendar
        reference.timeZone = calendar.timeZone
        reference.year = 2001
        reference.month = 1
        reference.day = 15
        let start = calendar.date(from: reference) ?? Date(timeIntervalSince1970: 0)
        return (0..<24).compactMap { hour -> RhythmHour? in
            guard let date = calendar.date(byAdding: .hour, value: hour, to: start) else { return nil }
            return RhythmHour(hour: date, seconds: seconds(hour), colorIndex: colorIndex)
        }
    }

    /// `4–6am` for the busiest run of consecutive hours, or nil when nothing was
    /// recorded. A single busiest hour reads `4am`.
    static func peakLabel(_ hours: [RhythmHour], formatter: (Date) -> String) -> String? {
        guard let max = hours.map(\.seconds).max(), max > 0 else { return nil }
        // Hours within 80% of the peak that sit next to each other form the run.
        let threshold = max * 0.8
        var bestRun: [RhythmHour] = []
        var run: [RhythmHour] = []
        for hour in hours {
            if hour.seconds >= threshold {
                run.append(hour)
            } else {
                if run.count > bestRun.count { bestRun = run }
                run = []
            }
        }
        if run.count > bestRun.count { bestRun = run }
        guard let first = bestRun.first, let last = bestRun.last else { return nil }
        if first.hour == last.hour { return formatter(first.hour) }
        let end = last.hour.addingTimeInterval(3_600)
        return "\(formatter(first.hour))–\(formatter(end))"
    }
}
