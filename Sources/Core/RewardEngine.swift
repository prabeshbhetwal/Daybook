import Foundation

/// What kind of moment a `Reward` is marking. The raw value is the persistence
/// key in the caller's `log`, so renaming a case would silently orphan history —
/// treat these as stable identifiers, not display strings.
enum RewardKind: String, CaseIterable, Equatable {
    case milestone, streakRecord, goalReached, goalPace, mediaEnded, workWithMusic
}

struct Reward: Equatable {
    let kind: RewardKind
    let title: String
    let detail: String
    let symbolName: String
}

/// Everything a candidate reward might cite. Every field the copy could quote is
/// optional on purpose — a nil means the caller has nothing defensible to say,
/// not zero, so the matching candidate is skipped rather than watered down.
struct RewardContext {
    let focusedToday: TimeInterval
    let sameWeekdayLastWeek: TimeInterval?
    let streak: Int
    let bestStreak: Int
    let goal: GoalProgress
    let endedMedia: (appName: String, seconds: TimeInterval)?
    let musicPairing: TimeInterval?
    let isSessionRunning: Bool
}

/// Picks at most one reward per call from a fixed priority list, gated by data
/// availability and rate limits. A pure value type: it never fires anything
/// itself, it just answers "what, if anything, is worth saying right now" —
/// the caller shows the HUD and persists the log `recording(_:)` returns.
///
/// Mirrors `DashboardStats.insights`: every candidate is gated on real data
/// existing, and a missing figure removes the candidate entirely rather than
/// producing a vaguer version of it. The rate limits exist for the opposite
/// failure mode — a mechanically correct message shown too often stops reading
/// as a reward and starts reading as noise, which is worse than saying nothing.
struct RewardEngine {

    private let log: [String: Date]
    private let now: () -> Date
    private let calendar: Calendar

    init(log: [String: Date], now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.log = log
        self.now = now
        self.calendar = calendar
    }

    /// Cheap enough to ask on every event. Gathering a `RewardContext` walks
    /// the whole archive, so the caller must be able to find out that nothing
    /// can fire *before* paying for the evidence that nothing would have.
    var isRateLimited: Bool { dailyCapReached() || inCooldown() }

    func next(for context: RewardContext) -> Reward? {
        guard !dailyCapReached(), !inCooldown() else { return nil }
        return candidates(for: context).first { !firedToday($0.kind) }
    }

    /// The engine holds no state of its own; the caller persists whatever this
    /// returns and passes it back into the next `RewardEngine` it constructs.
    func recording(_ reward: Reward) -> [String: Date] {
        var updated = log
        updated[reward.kind.rawValue] = now()
        return updated
    }

    // MARK: - Candidates, evaluated in priority order

    private func candidates(for context: RewardContext) -> [Reward] {
        [goalReached(context), streakRecord(context), milestone(context),
         goalPace(context), mediaEnded(context), workWithMusic(context)]
            .compactMap { $0 }
    }

    private func goalReached(_ context: RewardContext) -> Reward? {
        guard context.goal.isMet else { return nil }
        return Reward(kind: .goalReached,
                      title: "\(DurationText.compact(context.goal.goal)) goal reached",
                      detail: "You've focused \(DurationText.compact(context.goal.achieved)) today.",
                      symbolName: "checkmark.seal.fill")
    }

    private func streakRecord(_ context: RewardContext) -> Reward? {
        // >= 2 excludes the trivial "day one" case, where every streak is
        // automatically a new record and the message would mean nothing.
        guard context.streak > context.bestStreak, context.streak >= 2 else { return nil }
        return Reward(kind: .streakRecord,
                      title: "New streak record",
                      detail: "\(context.streak) days in a row, past your best of "
                            + "\(context.bestStreak).",
                      symbolName: "flame.fill")
    }

    private func milestone(_ context: RewardContext) -> Reward? {
        guard context.isSessionRunning, context.focusedToday >= 3_600 else { return nil }
        let hours = Int(context.focusedToday / 3_600)
        let todayPhrase = DurationText.compact(context.focusedToday)
        let detail: String
        // The comparison is only ever printed when there is a real number behind
        // it — a hidden fallback like "last week" without a value would look
        // like a comparison while being none.
        if let lastWeek = context.sameWeekdayLastWeek {
            let delta = context.focusedToday - lastWeek
            let direction = delta >= 0 ? "more" : "less"
            detail = "\(todayPhrase) focused today, \(DurationText.compact(abs(delta))) \(direction) "
                   + "than the same day last week"
        } else {
            detail = "\(todayPhrase) focused today"
        }
        return Reward(kind: .milestone,
                      title: "\(hours)-hour mark",
                      detail: detail,
                      symbolName: "clock.fill")
    }

    private func goalPace(_ context: RewardContext) -> Reward? {
        // `typicalByNow` is guarded even though `DailyGoal` only ever produces
        // `aheadBy` alongside it — the contract here is "cite it or skip",
        // never "assume it and force-unwrap".
        guard let aheadBy = context.goal.aheadBy, aheadBy > 15 * 60,
              let typical = context.goal.typicalByNow else { return nil }
        return Reward(kind: .goalPace,
                      title: "Ahead of your usual pace",
                      detail: "\(DurationText.compact(context.goal.achieved)) today vs "
                            + "\(DurationText.compact(typical)) typical by now — \(DurationText.compact(aheadBy)) ahead.",
                      symbolName: "hare.fill")
    }

    private func mediaEnded(_ context: RewardContext) -> Reward? {
        // A ten-minute floor: a trailer or a skipped track is not a break worth
        // remarking on.
        guard let media = context.endedMedia, media.seconds >= 600 else { return nil }
        return Reward(kind: .mediaEnded,
                      title: "Welcome back",
                      detail: "\(DurationText.compact(media.seconds)) with \(media.appName) — "
                            + "ready when you are.",
                      symbolName: "arrow.uturn.backward.circle.fill")
    }

    private func workWithMusic(_ context: RewardContext) -> Reward? {
        guard let pairing = context.musicPairing,
              pairing >= FocusConstants.musicPairingDwell else { return nil }
        return Reward(kind: .workWithMusic,
                      title: "In the zone",
                      detail: "\(DurationText.compact(pairing)) of focused work with music playing.",
                      symbolName: "music.note")
    }

    // MARK: - Rate limits

    /// Daily cap. Counts by calendar day rather than a rolling 24h window so
    /// the budget resets at midnight the same way the rest of the app's daily
    /// figures do.
    private func dailyCapReached() -> Bool {
        let reference = now()
        let firedToday = log.values.filter { calendar.isDate($0, inSameDayAs: reference) }
        return firedToday.count >= FocusConstants.rewardsPerDay
    }

    /// Blocks a second reward too soon after the last one, regardless of kind —
    /// two different congratulations five minutes apart still reads as nagging.
    private func inCooldown() -> Bool {
        guard let mostRecent = log.values.max() else { return false }
        return abs(now().timeIntervalSince(mostRecent)) < FocusConstants.rewardCooldown
    }

    private func firedToday(_ kind: RewardKind) -> Bool {
        guard let firedAt = log[kind.rawValue] else { return false }
        return calendar.isDate(firedAt, inSameDayAs: now())
    }
}
