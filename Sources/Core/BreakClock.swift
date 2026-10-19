import Foundation

/// A Later: this tier's reminder is held back until `until`.
struct BreakSnooze: Codable, Equatable {
    let tier: BreakTier
    var until: Date
    /// How many times this due break has been put off, so it cannot be put
    /// off for ever.
    var count: Int
}

/// What the person has told each reminder, beside the usage record.
///
/// Usage alone cannot say that someone skipped a break or took one away from
/// the Mac, so each tier's work counts only from its floor: the last moment
/// the person answered it. The usage record itself is never edited.
struct BreakClock: Codable, Equatable {
    /// Work before a tier's floor no longer counts towards that tier.
    var floors: [BreakTier: Date] = [:]
    var snooze: BreakSnooze?

    static let maxLaters = 2
    static let laterLength: TimeInterval = 600
    /// The long-stretch prompt is the one hardest to ignore, so it waits longer.
    static let stretchGuardLaterLength: TimeInterval = 900

    /// A rest that counted: every reminder starts again.
    mutating func credit(at moment: Date) {
        for tier in BreakTier.allCases { floors[tier] = moment }
        snooze = nil
    }

    /// Restarts that reminder only. Records no rest.
    ///
    /// The long-stretch guard is the exception: it resets on a rest that
    /// counted and on nothing else, so skipping it does nothing.
    mutating func skip(_ tier: BreakTier, at moment: Date) {
        guard tier != .ultradian else { return }
        floors[tier] = moment
        if snooze?.tier == tier { snooze = nil }
    }

    mutating func later(_ tier: BreakTier, at moment: Date) {
        // Clamped first: a damaged stored count must not overflow the `+ 1`.
        let count = snooze?.tier == tier ? min(snooze?.count ?? 0, Self.maxLaters) + 1 : 1
        snooze = BreakSnooze(tier: tier, until: moment.addingTimeInterval(Self.length(of: tier)),
                             count: count)
    }

    static func length(of tier: BreakTier) -> TimeInterval {
        tier == .ultradian ? stretchGuardLaterLength : laterLength
    }

    /// No Later is longer than this.
    static let longestLater: TimeInterval = 1_800

    /// What can be believed at `now`. A floor in the future, or a Later that
    /// ends further ahead than any Later lasts, comes from a clock that ran
    /// ahead or a damaged value, and would silence a reminder for as long as
    /// it stays wrong.
    func sanitized(now: Date) -> BreakClock {
        var kept = self
        kept.floors = floors.filter { $0.value <= now }
        if let held = snooze, held.until.timeIntervalSince(now) > Self.longestLater {
            kept.snooze = nil
        }
        return kept
    }

    /// A Later is for the break that was due when it was pressed. It does not
    /// apply when that tier is no longer due, or when the run now due began
    /// after the Later — a rest came between, and this is a new break.
    mutating func dropStaleSnooze(due: BreakTier?, runStart: Date?) {
        guard let held = snooze else { return }
        let pressed = held.until.addingTimeInterval(-Self.length(of: held.tier))
        if let due, due >= held.tier, let runStart, runStart <= pressed { return }
        snooze = nil
    }

    /// A Later belongs to a break that is still due. Once nothing is due, or
    /// only something shallower, the break it put off is over.
    mutating func clearSnoozeIfNotDue(_ due: BreakTier?) {
        guard let held = snooze?.tier else { return }
        if let due, due >= held { return }
        snooze = nil
    }

    /// `ordered` (newest end first) with work before `floor` cut away: whole
    /// stretches before it are dropped and one straddling it keeps only the
    /// part after.
    static func clip(_ ordered: [AppUsageSession], at floor: Date?) -> [AppUsageSession] {
        guard let floor else { return ordered }
        return ordered.prefix { $0.end > floor }.map { stretch in
            var kept = stretch
            kept.start = max(stretch.start, floor)
            return kept
        }
    }
}
