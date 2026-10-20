import Foundation

/// A break that has come due, with the words to say about it.
struct BreakPrompt: Equatable {
    /// Which showing this is. A prompt that comes back after a Later is a new
    /// one, so a surface can tell it from the one it already dismissed.
    /// `==` therefore compares ids too: two independently built prompts are
    /// never equal.
    let id: UUID = UUID()
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
    /// False once this break has been put off as often as it may be.
    var canLater = true
    /// The long break that closes a Pomodoro cycle rather than the usual one.
    var isLong = false
    /// The continuous work the plan that raised this prompt asks before it
    /// comes due. Nil reads as the tier's own threshold.
    var dueAfterWork: TimeInterval? = nil
    /// The break this prompt offers. Nil reads as the tier's own length, which
    /// is Eyes' thirty seconds.
    var offeredBreak: TimeInterval? = nil

    /// Which kind of reminder this is, for the log.
    var kind: BreakPromptKind { isLong ? .long : .of(tier) }
    /// The work it came due after; back-dates `due` in the log.
    var threshold: TimeInterval { dueAfterWork ?? tier.workThreshold }
    var breakLength: TimeInterval { offeredBreak ?? tier.breakLength }

    /// Eyes keeps its fixed wording. The others name the break they offer, in
    /// whole minutes.
    var title: String {
        switch kind {
        case .eyes: return tier.title
        case .main, .long: return "Take \(BreakPrompt.minutes(breakLength))"
        case .stretchGuard: return "Step away for \(BreakPrompt.minutes(breakLength))"
        }
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        let whole = max(1, Int((seconds / 60).rounded()))
        return whole == 1 ? "1 minute" : "\(whole) minutes"
    }

    /// The figure is continuous time at the Mac. It belongs to an app only
    /// when the app had nearly all of it: "You have been in Vorssaint for
    /// 20m" was written for a stretch Vorssaint had half of, after a login
    /// during which the person had also been in Dia, Claude and Finder — one
    /// true number attached to the wrong noun. Now the noun matches the
    /// number: the whole stretch names the app; a majority names it as
    /// "mostly"; anything less names the Mac.
    ///
    /// The title already says what to do and for how long, so the body says
    /// only why now. "Stretch" stays: the buttoned reminders show this body and nothing else.
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

extension BreakReminder {
    /// The prompt for the tier now due, or nil while it is held back: Eyes
    /// stays quiet when a main break or the guard is due or within
    /// `BreakPlan.eyesQuietBefore`; a Later holds back its own tier and the
    /// shallower ones; and a tier that was said recently waits for its own
    /// work length before it repeats.
    ///
    /// `left` is the work each reminder in the plan still needs. The prompt
    /// carries the plan's numbers, so what it says is what Start break does.
    static func prompt(for tier: BreakTier, run: BreakRun, plan: BreakPlan,
                       left: [BreakTier: TimeInterval], ordered: [AppUsageSession],
                       now: Date, last: BreakNotice?, clock: BreakClock) -> BreakPrompt? {
        if tier == .micro,
           left.contains(where: { $0.key != .micro && $0.value <= BreakPlan.eyesQuietBefore }) {
            return nil
        }
        let work = plan.workLength(tier) ?? tier.workThreshold
        // A Later holds back its own tier and the shallower ones; once it
        // runs out the break comes straight back, whatever was said last.
        var laters = 0
        var afterLater = false
        if let snooze = clock.snooze {
            if tier <= snooze.tier, now < snooze.until { return nil }
            afterLater = tier == snooze.tier
            laters = afterLater ? snooze.count : 0
        }
        // Only a notice older than the Later's end is overridden by it. One
        // written since — the prompt it brought back — is the repeat guard's.
        if let last, !(afterLater && last.at < (clock.snooze?.until ?? .distantPast)) {
            let since = now.timeIntervalSince(last.at)
            if since < minimumSpacing { return nil }
            if tier <= last.tier, since < work { return nil }
        }
        // The apps are read from the run the figure counted: Flow's run is
        // not the span since the last long gap, so it is cut where it began.
        var stretches = BreakClock.clip(ordered, at: clock.floors[tier])
        if plan.isFlow, tier == .ultradian { stretches = BreakClock.clip(stretches, at: run.start) }
        let leader = dominant(stretches, now: now, within: plan.rest(tier))
        return BreakPrompt(tier: tier, worked: run.seconds,
                           appName: leader?.name, appShare: leader?.share ?? 0,
                           canLater: laters < BreakClock.maxLaters,
                           dueAfterWork: work,
                           offeredBreak: plan.offeredBreak(for: tier, worked: run.seconds))
    }
}
