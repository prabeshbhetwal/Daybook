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
        return runs.compactMap { run in
            guard let first = run.first?.start, let end = run.last?.end, case let start = max(first, after),
                  end.timeIntervalSince(start) >= ActivityConstants.leisureMinRun,
                  now.timeIntervalSince(end) >= 2 * bridge else { return nil }
            // A held second is the holder's: the app in front (Mail under a film) only had the focus.
            let holder = mostNamed(beats.filter { $0.end > first && ActivityCredit.opening($0) < end }
                .flatMap { $0.watchedApps ?? [] })
            var seconds: [String: TimeInterval] = [:]
            for slice in run {
                seconds[slice.state == .held ? holder ?? slice.app : slice.app, default: 0] += slice.end.timeIntervalSince(slice.start)
            }
            return LeisureBlock(id: UUID(), start: start, end: end, bundleID: mostNamed(seconds) ?? "", activity: .media)
        }
    }

    /// The key with the largest count, the first in sorted order on a tie.
    private static func mostNamed(_ counts: [String: TimeInterval]) -> String? {
        counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    private static func mostNamed(_ names: [String]) -> String? {
        mostNamed(names.reduce(into: [String: TimeInterval]()) { $0[$1, default: 0] += 1 })
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
