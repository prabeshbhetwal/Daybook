import Foundation

/// What the reminders follow at one moment: a rhythm for the main break (nil
/// on a "No reminders" day), the Eyes add-on and the long-stretch guard.
///
/// The reminder engine reads every number from here. The three `BreakTier`s
/// are its slots: `.micro` is Eyes, `.cognitive` the main rhythm and
/// `.ultradian` the guard; the tier's own numbers are Steady's defaults.
struct BreakPlan: Equatable {
    var rhythm: BreakRhythm?
    var eyes: Bool
    /// Continuous work that brings the guard due; nil when it is off.
    var guardLength: TimeInterval?
    /// The kind of override that chose this plan, if one did.
    var override: BreakOverrideKind?

    /// Eyes comes due after this much use, and is quiet this close to a main
    /// break or the guard.
    static let eyesInterval: TimeInterval = 1_200
    static let eyesQuietBefore: TimeInterval = 300
    /// The guard is set in minutes, between these.
    static let guardRange = 60...180
    static let defaultGuardMinutes = 90
    /// The break the guard offers, at least; a longer rhythm break wins.
    static let guardBreak: TimeInterval = 900
    /// A guard set at or past the rhythm's work block comes due no sooner than
    /// this long after the block, or it would race the main break for the
    /// same moment.
    static let guardAfterWork: TimeInterval = 900

    /// Steady, Eyes on, a 90-minute guard: what someone who never touched
    /// settings gets.
    static let standard = BreakPlan(rhythm: BreakRhythm(.steady), eyes: true,
                                    guardLength: TimeInterval(defaultGuardMinutes * 60), override: nil)

    /// The plan for `moment`: the schedule's preset for that day (nil is "No
    /// reminders", which turns the main rhythm off and nothing else), the
    /// Eyes switch and the guard's minutes, kept inside `guardRange`.
    static func resolve(schedule: BreakSchedule, eyes: Bool, guardMinutes: Int?, on moment: Date,
                        calendar: Calendar) -> BreakPlan {
        let day = schedule.preset(on: moment, calendar: calendar)
        let minutes = guardMinutes.map { min(max($0, guardRange.lowerBound), guardRange.upperBound) }
        return BreakPlan(rhythm: day.preset.map { BreakRhythm($0, custom: schedule.custom) },
                         eyes: eyes,
                         guardLength: minutes.map { TimeInterval($0 * 60) },
                         override: day.override)
    }

    var isFlow: Bool { rhythm?.preset == .flow }

    /// The reminders in play, shallowest first: a tier has a work length
    /// exactly when it is on.
    var tiers: [BreakTier] { BreakTier.allCases.filter { workLength($0) != nil } }

    /// Continuous work that brings `tier` due, nil when that reminder is off
    /// (Flow has no main one). A guard set at or past a fixed work block
    /// waits until `guardAfterWork` after the block.
    func workLength(_ tier: BreakTier) -> TimeInterval? {
        switch tier {
        case .micro:
            return eyes ? Self.eyesInterval : nil
        case .cognitive:
            return rhythm?.work
        case .ultradian:
            guard let guardLength else { return nil }
            guard let block = rhythm?.work else { return guardLength }
            return guardLength < block ? guardLength : max(guardLength, block + Self.guardAfterWork)
        }
    }

    /// The gap that counts as a rest: the rhythm's break, never under the idle
    /// cutoff below which the usage record cannot tell rest from noise. With
    /// no rhythm it is `BreakLength.standard`; Flow has none, its rest depends
    /// on the work before it (`BreakCycles.flowRun`).
    var creditGap: TimeInterval? {
        guard !isFlow else { return nil }
        return max(rhythm?.breakLength ?? BreakLength.standard, AppUsageTracker.idleCutoff)
    }

    /// The gap that restarts `tier`'s count. Eyes restarts at the idle cutoff.
    func rest(_ tier: BreakTier) -> TimeInterval {
        tier == .micro ? AppUsageTracker.idleCutoff : (creditGap ?? BreakRhythm.flowLongest)
    }

    /// The longest rest in play, so the latest run is read as far as any count
    /// here can reach.
    var reach: TimeInterval { creditGap ?? BreakRhythm.flowLongest }

    /// The break a prompt for `tier` offers after `worked`; nil for Eyes, which
    /// keeps its own thirty seconds.
    func offeredBreak(for tier: BreakTier, worked: TimeInterval) -> TimeInterval? {
        switch tier {
        case .micro: return nil
        case .cognitive: return rhythm?.breakLength
        case .ultradian:
            guard !isFlow else { return BreakRhythm.flowSuggestion(after: worked) }
            return max(Self.guardBreak, rhythm?.breakLength ?? 0)
        }
    }

    /// What Start break begins with right now. Under Flow `flowWork` is the
    /// run the suggestion follows.
    func breakLength(flowWork: TimeInterval) -> TimeInterval {
        isFlow ? BreakRhythm.flowSuggestion(after: flowWork) : (rhythm?.breakLength ?? BreakLength.standard)
    }

    /// The rhythm in force, as the break log records it. Minutes are whole.
    var snapshot: BreakRhythmSnapshot {
        func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }
        return BreakRhythmSnapshot(workMinutes: rhythm?.work.map(minutes),
                                   breakMinutes: rhythm?.breakLength.map(minutes),
                                   eyes: eyes,
                                   guardMinutes: guardLength.map(minutes),
                                   override: override?.rawValue,
                                   preset: rhythm?.preset.rawValue ?? "off",
                                   longEvery: rhythm?.longEvery,
                                   longMinutes: rhythm?.longLength.map(minutes))
    }
}

extension BreakPlan {
    /// The plan the phase-1 switches amount to: the main tier is Steady, the
    /// eyes tier is Eyes and the long tier is a 90-minute guard.
    init(tiers: Set<BreakTier>) {
        self.init(rhythm: tiers.contains(.cognitive) ? BreakRhythm(.steady) : nil,
                  eyes: tiers.contains(.micro),
                  guardLength: tiers.contains(.ultradian)
                      ? TimeInterval(Self.defaultGuardMinutes * 60) : nil,
                  override: nil)
    }
}
