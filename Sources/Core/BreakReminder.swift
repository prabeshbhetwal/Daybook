import Foundation

/// The three kinds of fatigue continuous computer work produces, each with its
/// own onset time and its own recovery cost. They are not a single "take a
/// break" rule at three sizes: a thirty-second look-away genuinely fixes eye
/// strain and genuinely does nothing for a brain ninety minutes into a task.
///
/// Ordered by depth, and evaluated deepest-first, so a due ultradian reset is
/// never reported as a stretch break.
enum BreakTier: Int, CaseIterable, Comparable {

    /// 20-minute mark. Musculoskeletal and visual strain — the 20-20-20 rule.
    case micro = 0
    /// 50-minute mark. Cognitive load; attention degrades and needs a reset.
    case cognitive = 1
    /// 90-minute mark. The ultradian trough, where the body starts drawing on
    /// reserves and analytical efficiency falls away.
    case ultradian = 2

    static func < (lhs: BreakTier, rhs: BreakTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Continuous work that brings this tier due.
    var workThreshold: TimeInterval {
        switch self {
        case .micro: return 20 * 60
        case .cognitive: return 50 * 60
        case .ultradian: return 90 * 60
        }
    }

    /// Rest this tier prescribes.
    var breakLength: TimeInterval {
        switch self {
        case .micro: return 30
        case .cognitive: return 5 * 60
        case .ultradian: return 15 * 60
        }
    }

    /// The gap in recorded use that resets this tier's clock, which is *not* the
    /// same as the rest it prescribes.
    ///
    /// Using `breakLength` directly made the twenty-minute tier unreachable, and
    /// the whole feature silently dead. Two reasons. Looking away from the
    /// screen for thirty seconds produces no gap at all — the app is still
    /// frontmost, so nothing is recorded differently. And below the idle cutoff
    /// the data is pure noise: an archive of ordinary use is full of one- to
    /// twelve-second holes where a sub-minimum segment was dropped or a system
    /// process took the foreground. A thirty-second reset tripped on those
    /// constantly, so "continuous work" never accumulated past a few minutes.
    ///
    /// Three minutes is the shortest gap this app can actually observe, because
    /// that is when idle trimming starts cutting stretches short.
    var restGap: TimeInterval {
        max(breakLength, AppUsageTracker.idleCutoff)
    }

    var title: String {
        switch self {
        case .micro: return "Look away for 30 seconds"
        case .cognitive: return "Take 5 minutes"
        case .ultradian: return "Step away for 15 minutes"
        }
    }

    var symbolName: String {
        switch self {
        case .micro: return "eye"
        case .cognitive: return "cup.and.saucer.fill"
        case .ultradian: return "figure.walk"
        }
    }

    /// Why this break exists, in the plainest words that are still true. Shown
    /// to the user, so no jargon survives here that a non-specialist would have
    /// to look up.
    var reason: String {
        switch self {
        case .micro:
            return "Focus on something far away and let your shoulders drop. "
                + "This is for your eyes and your posture, not your "
                + "concentration — it is over before you lose your thread."
        case .cognitive:
            return "Attention wears down after about this long and a short rest "
                + "restores it. Stand up if you can. Scrolling your phone uses "
                + "the same part of the brain you are trying to rest."
        case .ultradian:
            return "You are past the point where pushing on costs more than it "
                + "returns. A real break away from the screen is what resets "
                + "this — email and messages do not count as one."
        }
    }

    /// Short label for the menu bar countdown.
    var shortLabel: String {
        switch self {
        case .micro: return "Look away"
        case .cognitive: return "Break"
        case .ultradian: return "Long break"
        }
    }
}

/// A break that has come due, with the words to say about it.
struct BreakPrompt: Equatable {
    let tier: BreakTier
    /// Continuous work behind it. The real figure, not the tier's threshold —
    /// a reminder that fires late must not claim you have worked less than you
    /// have.
    let worked: TimeInterval
    /// The app that took a majority of that time, when one did.
    let appName: String?
    /// How much of the stretch that app took, 0…1. Decides whether the app
    /// can carry the figure or only colour it.
    var appShare: Double = 1

    var title: String { tier.title }

    /// The figure is continuous time at the Mac. It belongs to an app only
    /// when the app had nearly all of it: "You have been in Vorssaint for
    /// 20m" was written for a stretch Vorssaint had half of, after a login
    /// during which the person had also been in Dia, Claude and Finder — one
    /// true number attached to the wrong noun. Now the noun matches the
    /// number: the whole stretch names the app; a majority names it as
    /// "mostly"; anything less names the Mac.
    ///
    /// The title already says what to do and for how long, so the body says
    /// only why now. "Stretch" stays: a notification shows no reason text.
    var body: String {
        let spent = BreakPrompt.phrase(worked)
        switch tier {
        case .micro:
            return "You have been \(place) for \(spent)\(mostly). Stretch while you do."
        case .cognitive:
            return "You have been \(place) for \(spent)\(mostly)."
        case .ultradian:
            return "\(spent.prefix(1).uppercased() + spent.dropFirst()) \(place) "
                + "without a real break\(mostly)."
        }
    }

    /// Nearly all of the stretch in one app is the app's stretch.
    static let wholeShare = 0.9

    private var place: String {
        if let appName, appShare >= BreakPrompt.wholeShare { return "in \(appName)" }
        return "at the Mac"
    }

    private var mostly: String {
        guard let appName, appShare < BreakPrompt.wholeShare else { return "" }
        return ", mostly in \(appName)"
    }

    /// Whole minutes, because "52m 13s" is not information anybody wants here.
    /// Below a minute it says seconds instead: the micro tier prescribes thirty
    /// seconds, and rounding that up to "1m" doubled the ask everywhere the
    /// figure appeared.
    static func phrase(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds.rounded())))s" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

/// What was said last, so the same nudge is not repeated every second.
struct BreakNotice: Equatable {
    let tier: BreakTier
    let at: Date
}

/// Continuous computer use, measured from the usage stretches rather than from
/// session time: the case that actually hurts is grinding for hours without
/// ever pressing Start. The usage tracker already excludes idle time, so this is
/// real work, not a frontmost app on an untouched machine.
///
/// Pure and headless. Every threshold rule is tested against an injected clock.
struct BreakReminder {

    /// Two prompts closer together than this are noise, whatever the tiers say.
    /// Guards the boundary case where the deepest due tier flickers between two
    /// levels as a gap ages past one tier's reset length but not another's.
    static let minimumSpacing: TimeInterval = 60

    /// Everything the surfaces need, from one sort of the archive.
    ///
    /// The pieces below are each cheap once the stretches are ordered — every
    /// walk stops at the first qualifying gap, so it touches only the current
    /// run — but the sort is not, and this runs on a timer. Calling `dueTier`,
    /// `next` and `prompt` separately re-sorted twenty thousand records three
    /// times a tick.
    struct Evaluation {
        let due: BreakTier?
        let next: (tier: BreakTier, seconds: TimeInterval)?
        let prompt: BreakPrompt?
    }

    static func evaluate(_ stretches: [AppUsageSession],
                         now: Date,
                         last: BreakNotice?,
                         tiers: [BreakTier] = BreakTier.allCases) -> Evaluation {
        let ordered = latestRun(stretches, now: now,
                                reaching: tiers.map(\.restGap).max() ?? 0)
        var done: [BreakTier: TimeInterval] = [:]
        for tier in tiers {
            done[tier] = worked(sorted: ordered, now: now, restingAtLeast: tier.restGap)
        }
        let due = tiers.reversed()
            .first { (done[$0] ?? 0) >= $0.workThreshold }

        // Written out rather than chained: the inferred tuple type defeats the
        // type checker inside a `map`/`min` pipeline.
        var next: (tier: BreakTier, seconds: TimeInterval)?
        for tier in tiers {
            let remaining: TimeInterval = max(0, tier.workThreshold - (done[tier] ?? 0))
            guard let best = next else {
                next = (tier: tier, seconds: remaining)
                continue
            }
            // Ties go to the deeper tier: reaching both at once means the
            // serious one, not the thirty-second one.
            if remaining < best.seconds || (remaining == best.seconds && tier > best.tier) {
                next = (tier: tier, seconds: remaining)
            }
        }
        return Evaluation(due: due, next: next,
                          prompt: prompt(ordered: ordered, now: now, last: last,
                                         due: due, worked: done[due ?? .micro] ?? 0))
    }

    /// How far back the walks below are expected to reach. A person rests
    /// within a day; a run that does not is still read in full, just slower.
    static let runLookback: TimeInterval = 24 * 3600

    /// The stretches newest-end first, as far as any walk here can read them.
    ///
    /// Every walk stops at the first gap of at least its rest, and none rests
    /// longer than `rest`, so the walks only ever read the latest run. History
    /// is uncapped: sorting all of it every five seconds grew without bound,
    /// about 43 ms a check at 80,000 records. Only the last day is sorted, and
    /// the whole history only when the run could reach past it. Filtering
    /// keeps the original order, so a tie sorts exactly as it would in full.
    private static func latestRun(_ stretches: [AppUsageSession], now: Date,
                                  reaching rest: TimeInterval) -> [AppUsageSession] {
        let horizon = now.addingTimeInterval(-runLookback)
        let recent = stretches.filter { $0.end >= horizon }.sorted { $0.end > $1.end }
        var boundary = now
        for stretch in recent {
            if boundary.timeIntervalSince(stretch.end) >= rest { return recent }
            boundary = stretch.start
        }
        // Everything left ends before the horizon, so a gap at least this long
        // follows the run and every walk stops inside it.
        if boundary.timeIntervalSince(horizon) >= rest { return recent }
        return stretches.sorted { $0.end > $1.end }
    }

    /// Walks backwards from now, summing attended time, stopping at the first
    /// gap long enough to count as rest at this depth. Gap time is never added —
    /// only work is.
    static func worked(_ stretches: [AppUsageSession],
                       now: Date,
                       restingAtLeast rest: TimeInterval) -> TimeInterval {
        worked(sorted: stretches.sorted { $0.end > $1.end }, now: now, restingAtLeast: rest)
    }

    private static func worked(sorted ordered: [AppUsageSession],
                               now: Date,
                               restingAtLeast rest: TimeInterval) -> TimeInterval {
        var total: TimeInterval = 0
        var boundary = now
        for stretch in ordered {
            if boundary.timeIntervalSince(stretch.end) >= rest { break }
            total += stretch.seconds
            boundary = stretch.start
        }
        return total
    }

    private static func prompt(ordered: [AppUsageSession],
                               now: Date,
                               last: BreakNotice?,
                               due: BreakTier?,
                               worked: TimeInterval) -> BreakPrompt? {
        guard let tier = due else { return nil }
        if let last {
            let since = now.timeIntervalSince(last.at)
            if since < minimumSpacing { return nil }
            if tier <= last.tier, since < tier.workThreshold { return nil }
        }
        let leader = dominant(ordered, now: now, within: tier.restGap)
        return BreakPrompt(tier: tier, worked: worked,
                           appName: leader?.name, appShare: leader?.share ?? 0)
    }

    // The three below are conveniences over `evaluate`, not second copies of it.
    // Writing them out again is how the goal bar and the archive ended up with
    // two versions of one rule that disagreed; there is one implementation here
    // and these are windows onto it.

    /// The deepest tier currently due, or nil.
    static func dueTier(_ stretches: [AppUsageSession], now: Date) -> BreakTier? {
        evaluate(stretches, now: now, last: nil).due
    }

    /// The prompt to show, or nil when nothing is due or it was said recently.
    ///
    /// Escalation is immediate — reaching ninety minutes should not wait out the
    /// fifty-minute tier's quiet period — but anything at or below the last tier
    /// waits for that tier's own interval to pass. A tier that fires, is
    /// ignored, and stays due therefore repeats at its own cadence rather than
    /// continuously.
    static func prompt(_ stretches: [AppUsageSession],
                       now: Date,
                       last: BreakNotice?) -> BreakPrompt? {
        evaluate(stretches, now: now, last: last).prompt
    }

    /// Whichever app took a majority of the continuous stretch, and how much
    /// of it. A scattered stretch with no majority names nothing rather than
    /// picking whatever happened to be frontmost when the timer expired — and
    /// "most" means more than half, not the 40% it used to mean.
    static func dominantApp(_ stretches: [AppUsageSession],
                            now: Date,
                            within rest: TimeInterval) -> String? {
        dominant(stretches, now: now, within: rest)?.name
    }

    static func dominant(_ stretches: [AppUsageSession],
                         now: Date,
                         within rest: TimeInterval) -> (name: String, share: Double)? {
        let ordered = stretches.sorted { $0.end > $1.end }
        var totals: [String: (name: String, seconds: TimeInterval)] = [:]
        var boundary = now
        var overall: TimeInterval = 0
        for stretch in ordered {
            if boundary.timeIntervalSince(stretch.end) >= rest { break }
            let existing = totals[stretch.bundleID]
            totals[stretch.bundleID] = (stretch.appName,
                                        (existing?.seconds ?? 0) + stretch.seconds)
            overall += stretch.seconds
            boundary = stretch.start
        }
        guard overall > 0,
              // Deterministic on a tie, so the same stretch never names two
              // different apps on two consecutive evaluations.
              let top = totals.max(by: {
                  ($0.value.seconds, $1.key) < ($1.value.seconds, $0.key)
              }),
              top.value.seconds / overall > 0.5 else { return nil }
        let name = top.value.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.lowercased() != "unknown" else { return nil }
        return (name, top.value.seconds / overall)
    }

    /// The next tier to come due and how long until it does — for the menu bar
    /// countdown. The soonest one, which is not always the shallowest: after a
    /// short pause the eye-strain clock has restarted while the deeper ones
    /// have not, so the deeper break is the one arriving first.
    static func next(_ stretches: [AppUsageSession],
                     now: Date) -> (tier: BreakTier, seconds: TimeInterval)? {
        evaluate(stretches, now: now, last: nil).next
    }
}
