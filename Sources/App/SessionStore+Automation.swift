import SwiftUI
import AppKit
import Combine

extension SessionStore {
    /// True while the running session was started by the detector rather than
    /// by hand — the popover labels it, and only these may be undone.
    var isAutoSession: Bool { state != .idle && engine.activeIsAuto }

    var activityOwnership: ActivityOwnership {
        guard engine.state != .idle else { return .none }
        if engine.activeIsAuto,
           let automaticActivityRecord,
           automaticActivityRecord.resultingRecordID == engine.activeRecordID {
            return .automatic(ruleID: automaticActivityRecord.action.ruleID,
                              recordID: engine.activeRecordID)
        }
        return .manual(activityName: engine.sessionName, workType: engine.activeWorkType)
    }

    var hasPendingManualActivityState: Bool {
        hasUnresolvedAwayDecision || engine.state.isPaused
    }

    func presentActivityChoice(_ choice: ActivityQuietChoice?) {
        pendingActivityChoice = choice
    }

    func chooseActivity(ruleID: UUID) { onActivityChoiceSelected?(ruleID) }

    @discardableResult
    func applyAutomaticActivity(_ action: ActivityAutomaticAction) -> AutomaticActivityRecord? {
        guard !hasUnresolvedAwayDecision,
              engine.store.automationMode == .activityRules,
              engine.store.activityRuleVersion == action.ruleVersion,
              engine.store.activityRuleCooldownUntil.map({ now() >= $0 }) ?? true,
              engine.store.activityRules.contains(where: {
                $0.id == action.ruleID && $0.isEnabled && $0.name == action.ruleName
                    && $0.workType == action.workType
              }) else { return nil }

        let applied: Bool
        if let expected = action.expectedRecordID {
            applied = engine.switchAutomatically(action: action, expectedRecordID: expected)
        } else {
            applied = engine.startAutomatically(action: action)
        }
        guard applied else {
            activityAutomationError = engine.awayDecisionError
                ?? "The automatic activity could not be saved. Current work was preserved."
            refresh()
            return nil
        }
        let record = AutomaticActivityRecord(action: action,
                                             resultingRecordID: engine.activeRecordID)
        automaticActivityRecord = record
        activityAutomationError = engine.awayDecisionError
        pendingActivityChoice = nil
        refresh()
        return record
    }

    @discardableResult
    func undoAutomaticActivity(expectedRecordID: UUID) -> Bool {
        guard let record = automaticActivityRecord,
              record.acceptsUndo(for: expectedRecordID),
              engine.activeRecordID == expectedRecordID,
              engine.activeIsAuto, !hasUnresolvedAwayDecision else { return false }
        guard engine.discard() else {
            activityAutomationError = engine.awayDecisionError
                ?? "The automatic activity could not be undone. Current work was preserved."
            refresh()
            return false
        }
        engine.store.activityRuleCooldownUntil = now()
            .addingTimeInterval(FocusConstants.defaultWorkInterval)
        automaticActivityRecord = nil
        activityAutomationError = nil
        refresh()
        return true
    }

    /// The authoritative action boundary for every ordinary session mutation.
    /// Views hide controls while an Away question is pending, but global
    /// shortcuts and future non-visual callers must be rejected here as well.
    /// Read the engine first because its callback publishes `state` on an async
    /// main-queue hop; `pendingAway` additionally covers the side-effect-free
    /// preview route used by the visual harness.
    var hasUnresolvedAwayDecision: Bool {
        if case .awaitingUserDecision = engine.state { return true }
        return pendingAway != nil
    }

    /// Starts a session on the detector's behalf, backdated to when the
    /// qualifying stretch actually began.
    func startAutomatically(workType: WorkType, name: String, backdatedTo: Date,
                            because: String) {
        guard !hasUnresolvedAwayDecision else { return }
        guard replaceSession(workType: workType, intent: name, isAuto: true) else { return }
        engine.backdate(to: backdatedTo)
        refresh()
    }

    @discardableResult
    func undoAutoSession(resumeTracking: Bool = false) -> Bool {
        guard isAutoSession, !hasUnresolvedAwayDecision else { return false }
        let origin = (engine.activeThreadID, engine.sessionStartDate)
        let discarded = engine.discard()
        if let error = engine.awayDecisionError {
            publishCorrectionError(error)
            correctionRetry = .discarding(threadID: origin.0, sessionStart: origin.1, resumeTracking: resumeTracking)
        } else {
            publishCorrectionError(nil)
            correctionRetry = nil
        }
        guard discarded else { refresh(); return false }
        onAutoSessionUndone?()
        if resumeTracking { onAwayEnded?() }
        refresh()
        return true
    }

    /// The Focus correction controls sit at the App boundary because declared
    /// Away owns a coordinator side effect as well as an engine transition.
    /// Resume tracking first, exactly as `I'm back` does, then preserve the
    /// existing adopt/reclassify semantics of `start()`.
    func applyAutomaticSessionCorrection() {
        guard isAutoSession, !hasUnresolvedAwayDecision else { return }
        isNamingAutomaticSession = false
        // A name spelled like a category is that category (see SessionNaming).
        (intent, workType) = SessionNaming.resolve(name: intent, workType: workType)
        if isAway {
            // `endAway()` refreshes `workType` from the still-active session.
            // Preserve the user's pending correction across that required
            // tracking-resume path before asking `start()` to apply it.
            let requestedIntent = intent
            let requestedWorkType = workType
            endAway()
            intent = requestedIntent
            workType = requestedWorkType
        }
        // This is a correction of the detector-owned current stretch, not the
        // ordinary Start action. It deliberately claims a same-type automatic
        // stretch even when the person supplies its first real name.
        if engine.wouldAdopt(workType: workType) {
            engine.adopt(intent: intent)
        } else {
            guard replaceSession(workType: workType, intent: intent) else { return }
        }
        engine.store.rememberActivity(name: intent, workType: workType)
        intent = ""
        refresh()
    }

    /// Undo rejects the app's detected session wholesale. Applying
    /// `endAway()` first would legitimately archive long work/Away stretches
    /// and clear automatic ownership before discard can act. Remember only
    /// whether tracking was suspended, discard while ownership is intact, then
    /// resume the App-level tracker exactly once.
    func undoAutomaticSessionCorrection() {
        guard isAutoSession, !hasUnresolvedAwayDecision else { return }
        isNamingAutomaticSession = false
        _ = undoAutoSession(resumeTracking: isAway)
    }
}
