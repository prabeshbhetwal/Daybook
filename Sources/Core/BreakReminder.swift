import Foundation

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
        /// The clock the answer was worked from: the one passed in, less the
        /// floors and the Later that could not be believed. A caller that keeps
        /// the clock compares it with its own to keep what was dropped dropped.
        let clock: BreakClock
        /// What Start break would begin with right now.
        let breakLength: TimeInterval
    }

    /// What is due and what to say about it, under `plan`: every length and
    /// rest comes from the plan, none from the tier.
    ///
    /// Eyes (`.micro`) restarts after a gap at the idle cutoff; the main
    /// rhythm (`.cognitive`) and the guard (`.ultradian`) after a credited
    /// rest, or under Flow after a gap that reaches the suggestion for the
    /// work before it. Skip and Later live in the clock.
    static func evaluate(_ stretches: [AppUsageSession],
                         now: Date,
                         last: BreakNotice?,
                         plan: BreakPlan = .standard,
                         clock: BreakClock = BreakClock()) -> Evaluation {
        // Floors and a Later that cannot be genuine are dropped here, not
        // left to the caller: see `BreakClock.sanitized`.
        var clock = clock.sanitized(now: now)
        let tiers = plan.tiers
        let ordered = latestRun(stretches, now: now, reaching: plan.reach)
        var counted: [BreakTier: BreakRun] = [:]
        var left: [BreakTier: TimeInterval] = [:]
        for tier in tiers {
            let found = count(tier, plan: plan, ordered: ordered, clock: clock, now: now)
            counted[tier] = found
            left[tier] = max(0, (plan.workLength(tier) ?? 0) - found.seconds)
        }
        // Eyes keeps out of the way of a main break or the guard that is due or
        // about to be: for this answer it counts as off, neither due nor next.
        var live = tiers
        if tiers.contains(.micro), tiers.contains(where: {
            $0 != .micro && (left[$0] ?? .infinity) <= BreakPlan.eyesQuietBefore
        }) {
            live.removeAll { $0 == .micro }
        }
        let due = live.reversed().first { left[$0] == 0 }
        clock.dropStaleSnooze(due: due, runStart: clock.snooze.flatMap { counted[$0.tier]?.start })

        // Written out rather than chained: the inferred tuple type defeats the
        // type checker inside a `map`/`min` pipeline.
        var next: (tier: BreakTier, seconds: TimeInterval)?
        for tier in live {
            let remaining: TimeInterval = left[tier] ?? 0
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
        // Flow suggests its break from the guard's run, whether or not the
        // guard itself is on.
        let flowWork = plan.isFlow
            ? (counted[.ultradian] ?? count(.ultradian, plan: plan, ordered: ordered, clock: clock, now: now)).seconds
            : 0
        // Pomodoro's long break, once enough cycles are behind.
        let longBreak = BreakCycles.longBreakNext(plan: plan, ordered: ordered, now: now,
                                                  credits: clock.credits)
        var shown: BreakPrompt?
        if let tier = due, let found = counted[tier] {
            shown = prompt(for: tier, run: found, plan: plan, ordered: ordered,
                           now: now, last: last, clock: clock, longBreak: longBreak)
        }
        return Evaluation(due: due, next: next, prompt: shown, clock: clock,
                          breakLength: longBreak ?? plan.breakLength(flowWork: flowWork))
    }

    /// What `tier` has counted since its floor, up to the first gap that
    /// restarts it. The guard under Flow follows Flow's own rest rule.
    private static func count(_ tier: BreakTier, plan: BreakPlan, ordered: [AppUsageSession],
                              clock: BreakClock, now: Date) -> BreakRun {
        let mine = BreakClock.clip(ordered, at: clock.floors[tier])
        if tier == .ultradian, plan.isFlow { return BreakCycles.flowRun(mine, now: now) }
        return run(sorted: mine, now: now, restingAtLeast: plan.rest(tier))
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
        run(sorted: ordered, now: now, restingAtLeast: rest).seconds
    }

    /// The work behind `worked` and when that unbroken run began, nil when
    /// there is none.
    private static func run(sorted ordered: [AppUsageSession],
                            now: Date,
                            restingAtLeast rest: TimeInterval) -> BreakRun {
        var total: TimeInterval = 0
        var boundary = now
        var start: Date?
        for stretch in ordered {
            if boundary.timeIntervalSince(stretch.end) >= rest { break }
            total += stretch.seconds
            boundary = stretch.start
            start = stretch.start
        }
        return (total, start)
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
