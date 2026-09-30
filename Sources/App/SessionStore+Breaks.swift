import SwiftUI
import AppKit
import Combine

extension SessionStore {
    // MARK: - Break reminders

    /// Continuous computer use, session or not: the case that hurts is grinding
    /// for hours without ever pressing Start.
    func refreshBreak() {
        guard let usageSnapshot = effectiveUsageSnapshot,
              engine.store.remindersEnabled,
              remindersPausedByCategory == nil else {
            breakCountdown = 0
            isBreakDue = false
            nextBreakTier = nil
            return
        }
        let moment = Date()
        let result = BreakReminder.evaluate(usageSnapshot.sessions, now: moment,
                                            last: engine.store.lastBreakNotice,
                                            tiers: BreakTier.allCases.filter(engine.store.enabledBreakTiers.contains))
        breakCountdown = result.next?.seconds ?? 0
        nextBreakTier = result.next?.tier
        isBreakDue = result.due != nil

        guard let prompt = result.prompt else { return }
        engine.store.lastBreakNotice = BreakNotice(tier: prompt.tier, at: moment)
        onBreakDue?(prompt)
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
