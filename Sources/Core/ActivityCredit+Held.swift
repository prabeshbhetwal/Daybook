import Foundation

/// Rule 2, held: an app holds the screen awake and quiet has lasted past `watchGrace`.
/// The whole quiet stretch is then held from its start, the way the engine backdates a pause.
extension ActivityCredit {
    struct HeldRun {
        let interval: DateInterval
        let purpose: AppPurpose
    }

    /// Held runs in time order. A quiet stretch is counted time with no engaged slice.
    /// Inside one, a held run is a maximal run of beats not read empty (`[]`; nil, not
    /// yet read, does not end it) holding a non-empty beat that reaches past the grace.
    /// A beat reaches past it when its end (clipped to the stretch) is more than
    /// `watchGrace` after the quiet began: the grace is measured at the beat's end, so a
    /// beat read held across the grace's edge holds the stretch, one beat earlier than
    /// measuring at its start would. It is credited from its first beat, clipped to the
    /// stretch, to the end of its last non-empty beat.
    static func heldRuns(beats: [Beat], counted: [DateInterval], engaged: [DateInterval],
                         firstStart: Date, overrides: [String: String], signals: Set<SignalKind>) -> [HeldRun] {
        var runs: [HeldRun] = []
        for span in counted {
            for stretch in cut(span, by: engaged) where stretch.by == nil {
                let quietSince = engaged.last { $0.end <= stretch.part.start }?.end ?? firstStart
                let inside = beats.filter { opening($0) < stretch.part.end && $0.end > stretch.part.start }
                runs += inside.split { $0.watchedApps == [] }.compactMap {
                    heldRun($0, in: stretch.part, quietSince: quietSince, overrides: overrides, signals: signals)
                }
            }
        }
        return runs
    }

    private static func heldRun(_ run: ArraySlice<Beat>, in stretch: DateInterval, quietSince: Date,
                                overrides: [String: String], signals: Set<SignalKind>) -> HeldRun? {
        let read = run.filter { !($0.watchedApps ?? []).isEmpty }
        guard let first = run.first, let last = read.last, read.contains(where: {
            min($0.end, stretch.end).timeIntervalSince(quietSince) > ActivityConstants.watchGrace
        }), let purpose = heldPurpose(of: run, overrides: overrides, signals: signals) else { return nil }
        let start = max(opening(first), stretch.start), end = min(last.end, stretch.end)
        guard purpose != .utility, start < end else { return nil }
        return HeldRun(interval: DateInterval(start: start, end: end), purpose: purpose)
    }

    /// The engine's watching pauses, in time order. The engine backdates a watching pause to
    /// the last input, after the beats in that stretch were already written as quiet or
    /// watched; `.watchPause` beats begin only at the idle threshold. So each run of them
    /// reaches back over the contiguous beats before it that are not wholly counted (stopping
    /// at a `.paused` beat), and starts no earlier than the last counted second before it. Its
    /// holder is read over those beats too, since none may be written during the pause itself.
    /// Purpose nil when no holder was read or a utility holds it. `atStart` is true for a run
    /// that reaches back to the first beat.
    static func watchPauses(_ beats: [Beat], counted: [DateInterval], overrides: [String: String],
                            signals: Set<SignalKind> = [])
        -> [(span: DateInterval, purpose: AppPurpose?, atStart: Bool)] {
        var pauses: [(span: DateInterval, purpose: AppPurpose?, atStart: Bool)] = []
        var index = 0
        while index < beats.count {
            guard beats[index].presence == .watchPause else { index += 1; continue }
            var last = index
            while last + 1 < beats.count, beats[last + 1].presence == .watchPause { last += 1 }
            var lead = index
            while lead > 0, beats[lead - 1].presence != .paused,
                  beats[lead - 1].end.timeIntervalSince(opening(beats[lead])) >= -1,
                  !whollyCounted(beats[lead - 1], counted) { lead -= 1 }
            let countedEnd = counted.map(\.end).filter { $0 <= opening(beats[index]) }.max() ?? .distantPast
            let start = max(opening(beats[lead]), countedEnd), end = beats[last].end
            let purpose = heldPurpose(of: beats[lead...last], overrides: overrides, signals: signals)
            if start < end {
                pauses.append((DateInterval(start: start, end: end), purpose == .utility ? nil : purpose, lead == 0))
            }
            index = last + 1
        }
        return pauses
    }

    private static func whollyCounted(_ beat: Beat, _ counted: [DateInterval]) -> Bool {
        let span = beat.end.timeIntervalSince(opening(beat))
        let inside = counted.reduce(0.0) {
            $0 + max(0, min($1.end, beat.end).timeIntervalSince(max($1.start, opening(beat))))
        }
        return inside >= span - 0.5
    }

    /// What a run of beats was held for: its holder's purpose, nil when no holder was read.
    /// No microphone is read, so a browser holding the screen is watching, refined only by site kind
    /// (`heldBrowserPurpose`).
    static func heldPurpose(of run: ArraySlice<Beat>, overrides: [String: String],
                            signals: Set<SignalKind>) -> AppPurpose? {
        let read = run.filter { !($0.watchedApps ?? []).isEmpty }
        guard !read.isEmpty else { return nil }
        let heldBy = holder(of: read, front: Set(run.flatMap { $0.slices.map(\.app) }))
        return holdsAsBrowser(heldBy, in: run, overrides: overrides, signals: signals)
            ? heldBrowserPurpose(heldBy, in: run, signals: signals)
            : PurposeMap.purpose(for: heldBy, activity: .passive, overrides: overrides)
    }

    /// The app named in the most non-empty beats. A tie goes to a tied app that was in
    /// front during the run, else to the first in sorted order.
    private static func holder(of read: [Beat], front: Set<String>) -> String {
        var tally: [String: Int] = [:]
        for beat in read {
            for app in Set(beat.watchedApps ?? []) { tally[app, default: 0] += 1 }
        }
        let most = tally.values.max() ?? 0
        let tied = tally.filter { $0.value == most }.map(\.key).sorted()
        return tied.first(where: front.contains) ?? tied[0]
    }
}
