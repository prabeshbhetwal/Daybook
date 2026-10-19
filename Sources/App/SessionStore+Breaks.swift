import SwiftUI
import AppKit
import Combine

extension SessionStore {
    // MARK: - Break reminders

    /// Continuous computer use, session or not: the case that hurts is grinding
    /// for hours without ever pressing Start.
    func refreshBreak() {
        // A break being taken is the answer to a reminder, and nothing is due
        // while one runs.
        guard !isOnBreak,
              let usageSnapshot = effectiveUsageSnapshot,
              engine.store.remindersEnabled,
              remindersPausedByCategory == nil else {
            breakCountdown = 0
            isBreakDue = false
            nextBreakTier = nil
            return
        }
        let moment = now()
        let tiers = BreakTier.allCases.filter(engine.store.enabledBreakTiers.contains)
        let kept = engine.store.breakClock
        let result = BreakReminder.evaluate(usageSnapshot.sessions, now: moment,
                                            last: engine.store.lastBreakNotice,
                                            tiers: tiers, clock: kept)
        // `evaluate` ignores a Later that belongs to a break that is over, but
        // only in its own copy. The drop is made here too, or the next Later of
        // a new run would be counted on top of the old ones.
        if kept.snooze != nil, result.clock.snooze == nil {
            var cleared = kept
            cleared.snooze = nil
            engine.store.breakClock = cleared
        }
        breakLog.noteRhythm(BreakRhythmSnapshot.fromTiers(Set(tiers)), on: moment)
        breakCountdown = result.next?.seconds ?? 0
        nextBreakTier = result.next?.tier
        isBreakDue = result.due != nil

        guard let prompt = result.prompt else { return }
        // Only a reminder that reached the screen is a reminder given: logged,
        // and written down so it is not repeated for the whole of its tier. One
        // that could not be shown (the screen out of reach, or no one listening
        // yet at launch) is asked again at the next pass.
        guard onBreakDue?(prompt) == true else { return }
        engine.store.lastBreakNotice = BreakNotice(tier: prompt.tier, at: moment)
        logShown(prompt, at: moment)
    }

    /// Eyes prompts are counted by day; every other kind is listed, under the
    /// id of this showing. A prompt that returns after a Later is a new one.
    private func logShown(_ prompt: BreakPrompt, at moment: Date) {
        guard prompt.tier != .micro else {
            breakLog.noteEyesPrompt(at: moment)
            return
        }
        let overdue = max(0, prompt.worked - prompt.tier.workThreshold)
        breakLog.recordShown(BreakPromptEntry(id: prompt.id, kind: BreakPromptKind.of(prompt.tier),
                                              due: moment.addingTimeInterval(-overdue), shown: moment))
    }

    // Settings are written by `SettingsModel`; these are the read side the
    // surfaces still need.
    var remindersEnabled: Bool { engine.store.remindersEnabled }

    /// The running category that has asked not to be interrupted, or nil.
    var remindersPausedByCategory: WorkType? {
        guard engine.state != .idle, !engine.activeWorkType.remindsBreaks else { return nil }
        return engine.activeWorkType
    }

    /// How long an absence has to be before the app asks about it rather than
    /// quietly leaving it out.
    var breakThreshold: TimeInterval { engine.breakThreshold }

    /// And how long before it stops asking and simply ends the session.
    var longAwayCap: TimeInterval { engine.store.longAwayCap }

    /// `Look away in 3m`, or `Break due` once one is. Names the kind of break so
    /// a thirty-second look-away is not mistaken for a quarter of an hour off.
    var breakLabel: String {
        guard remindersEnabled else { return "Reminders off" }
        if let paused = remindersPausedByCategory { return "No reminders during \(paused.displayName)" }
        if isBreakDue { return "Break due" }
        guard let tier = nextBreakTier else { return "No break due" }
        return "\(tier.shortLabel) in \(Tokens.preciseDuration(breakCountdown))"
    }
}
