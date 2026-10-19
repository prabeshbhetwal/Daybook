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
    mutating func skip(_ tier: BreakTier, at moment: Date) {
        floors[tier] = moment
        if snooze?.tier == tier { snooze = nil }
    }

    mutating func later(_ tier: BreakTier, at moment: Date) {
        let length = tier == .ultradian ? Self.stretchGuardLaterLength : Self.laterLength
        let count = snooze?.tier == tier ? (snooze?.count ?? 0) + 1 : 1
        snooze = BreakSnooze(tier: tier, until: moment.addingTimeInterval(length), count: count)
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
