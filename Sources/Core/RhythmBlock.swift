import Foundation

/// Three clock hours of a day: how much app use fell in them, how much of it
/// was during focus, and which app led. Eight of them answer "when did I
/// focus?" where 24 thin hourly bars said only "when was the Mac on?".
struct RhythmBlock: Identifiable, Equatable {
    let start: Date
    let end: Date
    /// All recorded app use in the block.
    let seconds: TimeInterval
    /// The part of `seconds` during focus, as the daily goal counts it.
    let focusSeconds: TimeInterval
    var topBundleID: String?
    var topAppName: String?
    /// Still to come: drawn as an outline, never as an empty block.
    let isAhead: Bool
    var id: Date { start }
    var otherSeconds: TimeInterval { max(0, seconds - focusSeconds) }
}

extension Rhythm {
    /// Eight blocks from midnight, cut at clock hours 0, 3, 6 ... 21 so the
    /// labels stay true on a day whose clocks change. `focus` answers how
    /// much of an interval counted as focus; it is capped at the app use
    /// recorded there, which it can never exceed.
    static func blocks(segments: [TimelineSegment], day: Date, now: Date,
                       calendar: Calendar = .current,
                       focus: (DateInterval) -> TimeInterval) -> [RhythmBlock] {
        let midnight = calendar.startOfDay(for: day)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) else { return [] }
        let starts = stride(from: 0, to: 24, by: 3).compactMap {
            calendar.date(bySettingHour: $0, minute: 0, second: 0, of: midnight)
        }
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : nextMidnight
            var byApp: [String: TimeInterval] = [:]
            var names: [String: String] = [:]
            var total: TimeInterval = 0
            for segment in segments {
                let overlap = min(segment.end, end).timeIntervalSince(max(segment.start, start))
                guard overlap > 0 else { continue }
                total += overlap
                byApp[segment.bundleID, default: 0] += overlap
                if names[segment.bundleID] == nil { names[segment.bundleID] = segment.appName }
            }
            let top = byApp.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
            let focused = total > 0 ? min(total, max(0, focus(DateInterval(start: start, end: end)))) : 0
            return RhythmBlock(start: start, end: end, seconds: total, focusSeconds: focused,
                               topBundleID: top, topAppName: top.flatMap { names[$0] },
                               isAhead: start >= now)
        }
    }

    /// The block to name in the headline: most focus, or, with none, most app
    /// use. Nil when nothing was recorded. Ties go to the earlier block.
    static func standout(_ blocks: [RhythmBlock]) -> (block: RhythmBlock, isFocus: Bool)? {
        if let best = blocks.filter({ $0.focusSeconds >= 60 }).max(by: { $0.focusSeconds < $1.focusSeconds }) {
            return (best, true)
        }
        guard let busiest = blocks.filter({ $0.seconds >= 60 }).max(by: { $0.seconds < $1.seconds }) else {
            return nil
        }
        return (busiest, false)
    }
}
