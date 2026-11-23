import Foundation

/// Watching or listening outside every session (spec section 4, plan ruling B14): its own block on the
/// timeline, kept in `leisure.json` and never in `sessions.json`, so nothing that totals focus, goals, streaks
/// or breaks, in this build or an older one, can read it.
struct LeisureBlock: Codable, Equatable, Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    /// The app that held most of it.
    let bundleID: String
    let activity: AppPurpose

    var interval: DateInterval { DateInterval(start: start, end: end) }
}

/// Finds leisure in beats. Pure: the same beats, sessions and overrides always give the same runs.
enum LeisureFinder {
    /// A glance away shorter than one beat does not end what was being watched.
    private static let bridge = ActivityConstants.beatLength
    /// Quiet counts only as the minute before the sampler reads who holds the screen (Phase C ruling F4).
    private static let leadIn: TimeInterval = 60

    /// Finished runs of media watched or listened to hands off in `beats`, outside every one of `sessions`, at least
    /// `leisureMinRun` long, kept from `after` when it began before. A run with media in the last minute before
    /// `now` may still be going, and waits. Nothing while automatic mode is off.
    static func blocks(beats: [Beat], sessions: [DateInterval], autoModeOn: Bool, after: Date, now: Date,
                       purposeOverrides: [String: String] = [:]) -> [LeisureBlock] {
        guard autoModeOn, let first = beats.map(ActivityCredit.opening).min(),
              let last = beats.map(\.end).max(), last > first else { return [] }
        let outside = free(DateInterval(start: first, end: last), around: sessions)
        let media = ActivityCredit.credit(CreditInput(beats: beats, counted: outside, signals: SignalKind.carried(by: beats),
                                                      purposeOverrides: purposeOverrides))
            // Hands off: held, passive, or the quiet first minute before the sampler reads who holds the screen.
            .filter { $0.state != .engaged && $0.purpose == .media }
            .sorted { $0.start < $1.start }
        var runs: [[CreditedSlice]] = []
        for slice in media {
            if let end = runs.last?.last?.end, slice.start.timeIntervalSince(end) < bridge,
               !sessions.contains(where: { $0.end > end && $0.start < slice.start }) {
                runs[runs.count - 1].append(slice)
            } else {
                runs.append([slice])
            }
        }
        return runs.flatMap(split).compactMap { run in
            // Quiet in a media app proves nothing: a paused player left in front reads the same. A run needs
            // held or passive seconds, and its quiet counts only as the lead-in before the first of them.
            guard let firstSign = run.firstIndex(where: { $0.state != .quietKept }),
                  let lastSign = run.lastIndex(where: { $0.state != .quietKept }) else { return nil }
            let leadFrom = run[firstSign].start.addingTimeInterval(-leadIn)
            let kept = run[...lastSign].filter { $0.end > leadFrom }.map { slice in
                slice.start >= leadFrom ? slice
                    : CreditedSlice(start: leadFrom, end: slice.end, app: slice.app, state: slice.state,
                                    purpose: slice.purpose, site: slice.site, holder: slice.holder)
            }
            // A short quiet tail may be a holder not read yet: wait it out, as for media still playing.
            guard let first = kept.first?.start, let end = kept.last?.end, case let start = max(first, after),
                  let tail = run.last?.end, end.timeIntervalSince(start) >= ActivityConstants.leisureMinRun,
                  now.timeIntervalSince(min(tail, end + leadIn)) >= 2 * bridge else { return nil }
            // A held second is its holder's, as credited: the app in front (Mail under a film) only had the focus.
            var seconds: [String: TimeInterval] = [:]
            for slice in kept {
                seconds[slice.holder ?? slice.app, default: 0] += slice.end.timeIntervalSince(slice.start)
            }
            return LeisureBlock(id: UUID(), start: start, end: end, bundleID: mostNamed(seconds) ?? "", activity: .media)
        }
    }

    /// `run` cut wherever its quiet outlasts the lead-in after some held or passive time: a long pause
    /// between two held stretches was not watched, and the quiet before the second is its lead-in.
    private static func split(_ run: [CreditedSlice]) -> [[CreditedSlice]] {
        var parts: [[CreditedSlice]] = [[]]
        var quietFrom: Int?
        for slice in run {
            if slice.state == .quietKept {
                if quietFrom == nil { quietFrom = parts[parts.count - 1].count }
            } else if let from = quietFrom {
                let part = parts[parts.count - 1]
                if part[..<from].contains(where: { $0.state != .quietKept }),
                   slice.start.timeIntervalSince(part[from].start) > leadIn {
                    parts[parts.count - 1] = Array(part[..<from])
                    parts.append(Array(part[from...]))
                }
                quietFrom = nil
            }
            parts[parts.count - 1].append(slice)
        }
        return parts
    }

    /// The key with the largest count, the first in sorted order on a tie.
    private static func mostNamed(_ counts: [String: TimeInterval]) -> String? {
        counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    /// What the timeline shows of `blocks` beside `sessions`: each trimmed to its longest stretch outside every
    /// session, and dropped when that is under `leisureMinRun`, so a session backdated over a block written
    /// earlier never shows the same minutes twice.
    static func visible(_ blocks: [LeisureBlock], beside sessions: [DateInterval]) -> [LeisureBlock] {
        blocks.compactMap { block in
            guard let longest = free(block.interval, around: sessions).max(by: { $0.duration < $1.duration }),
                  longest.duration >= ActivityConstants.leisureMinRun else { return nil }
            return LeisureBlock(id: block.id, start: longest.start, end: longest.end, bundleID: block.bundleID,
                                activity: block.activity)
        }
    }

    /// `span` less every session.
    static func free(_ span: DateInterval, around sessions: [DateInterval]) -> [DateInterval] {
        var parts: [DateInterval] = []
        var cursor = span.start
        for session in sessions.sorted(by: { $0.start < $1.start }) where session.end > cursor && session.start < span.end {
            if session.start > cursor { parts.append(DateInterval(start: cursor, end: session.start)) }
            cursor = max(cursor, session.end)
        }
        if span.end > cursor { parts.append(DateInterval(start: cursor, end: span.end)) }
        return parts
    }
}
