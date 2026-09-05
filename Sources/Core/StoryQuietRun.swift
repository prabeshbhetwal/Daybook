import Foundation

/// A run of consecutive moments that record no deliberate work: unrecorded
/// intervals and app use outside any session.
///
/// A day with light focus but continuous app use produces far more of these
/// than sessions — the demo day was eleven quiet rows around two sessions —
/// which buries the work the story is about. Grouping them keeps every minute
/// available without letting it outnumber the day's actual content.
struct StoryQuietRun: Equatable {
    let moments: [StoryMoment]
    /// App use outside a session, in seconds.
    let recordedSeconds: TimeInterval
    /// Time the recording ended for want of input, in seconds.
    let idleSeconds: TimeInterval
    /// Time nothing was recorded at all, in seconds.
    let unrecordedSeconds: TimeInterval
    let appUseCount: Int
    let gapCount: Int

    init(moments: [StoryMoment], recordedSeconds: TimeInterval, idleSeconds: TimeInterval = 0,
         unrecordedSeconds: TimeInterval, appUseCount: Int, gapCount: Int) {
        self.moments = moments
        self.recordedSeconds = recordedSeconds
        self.idleSeconds = idleSeconds
        self.unrecordedSeconds = unrecordedSeconds
        self.appUseCount = appUseCount
        self.gapCount = gapCount
    }

    var span: DateInterval? {
        guard let first = moments.first, let last = moments.last else { return nil }
        return DateInterval(start: first.start, end: max(first.start, last.end))
    }

    var id: String { moments.first?.id ?? "quiet" }

    /// What the collapsed row says. States each part only when it happened, so
    /// a run of pure gaps never claims app use and vice versa.
    var summary: String {
        var parts: [String] = []
        if recordedSeconds > 0 {
            parts.append("\(StoryQuietRun.duration(recordedSeconds)) outside sessions")
        }
        if idleSeconds > 0 {
            parts.append("\(StoryQuietRun.duration(idleSeconds)) no input")
        }
        if unrecordedSeconds > 0 {
            parts.append("\(StoryQuietRun.duration(unrecordedSeconds)) not recorded")
        }
        if parts.isEmpty { parts.append("Nothing recorded") }
        let intervals = appUseCount + gapCount
        parts.append(intervals == 1 ? "1 interval" : "\(intervals) intervals")
        return parts.joined(separator: " · ")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = (total % 3600) / 60
        guard hours > 0 else { return "\(minutes)m" }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}

enum StoryQuietGrouping {
    /// Sessions and rests are the day's content; a rest was named by the user
    /// and is not noise.
    static func isQuiet(_ moment: StoryMoment) -> Bool {
        switch moment {
        case .entry: return false
        case .appUse, .unrecorded: return true
        }
    }

    static func run(from moments: [StoryMoment]) -> StoryQuietRun {
        var recorded: TimeInterval = 0
        var idle: TimeInterval = 0
        var unrecorded: TimeInterval = 0
        var appUses = 0
        var gaps = 0
        for moment in moments {
            switch moment {
            case .appUse(_, let seconds):
                recorded += max(0, seconds)
                appUses += 1
            case .unrecorded(let span, let reason):
                if reason == .idle { idle += span.duration } else { unrecorded += span.duration }
                gaps += 1
            case .entry:
                continue
            }
        }
        return StoryQuietRun(moments: moments, recordedSeconds: recorded, idleSeconds: idle,
                             unrecordedSeconds: unrecorded,
                             appUseCount: appUses, gapCount: gaps)
    }
}
