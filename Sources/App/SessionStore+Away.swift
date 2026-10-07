import SwiftUI
import AppKit
import Combine

extension SessionStore {
    /// "I am stepping away." The one thing the app never has to guess at, and
    /// the answer to the question it would otherwise ask on your return.
    /// Unlike Pause this also stops background recording — a paused session
    /// still leaves you sitting at the Mac, being away does not.
    func markAway() {
        engine.transition(on: .markedAway)
        onAwayBegan?()
        refresh()
    }

    /// Ends a declared away. Any real activity ends it too, through the ordinary
    /// app-activation path; this is the explicit version for coming back to a
    /// Mac that was left on a session that has no work app to return to.
    func endAway() {
        engine.transition(on: .manualResume)
        if applyLongAwayResult(resumeTracking: true) != false { onAwayEnded?() }
        refresh()
    }

    @discardableResult
    func applyLongAwayResult(resumeTracking: Bool = false) -> Bool? {
        guard let result = engine.lastLongAwayTransition else { return nil }
        let shouldResumeTracking: Bool
        if case .longAway(let current, let retained)? = correctionRetry, current == result.request {
            shouldResumeTracking = resumeTracking || retained
        } else {
            shouldResumeTracking = resumeTracking
        }
        switch result.outcome {
        case .completed:
            if case .longAway(let current, _)? = correctionRetry, current == result.request {
                publishCorrectionError(nil)
                correctionRetry = nil
            }
        case .pendingFinalisation(let error), .refused(let error):
            publishCorrectionError(error)
            correctionRetry = .longAway(result.request, resumeTracking: shouldResumeTracking)
        }
        return result.outcome.applied
    }

    /// True while the user has declared themselves away, as opposed to having
    /// paused a session they are still sitting in front of.
    ///
    /// Read from the engine, not the published `state`: that copy arrives on
    /// an async main-queue hop, and a discard made inside the hop decided
    /// "not away" and never resumed tracking.
    var isAway: Bool {
        if case .paused(.away) = engine.state { return true }
        return false
    }

    /// `label` names a break in the user's words ("dinner"); it is ignored for
    /// any other answer.
    @discardableResult
    func resolve(_ decision: UserDecision, label: String? = nil, expectedID: UUID? = nil) -> Bool {
        applyAwayDecision(decision, label: label, reviewing: false, expectedID: expectedID)
    }

    var pendingAwaySaveError: String? {
        guard case .awayDecision(_, _, let reviewing, let id)? = correctionRetry,
              !reviewing, engine.pendingDecisionID == id else { return nil }
        return correctionError
    }

    @discardableResult
    func retryPendingAwayDecision(expectedID: UUID?) -> Bool {
        guard let expectedID, engine.pendingDecisionID == expectedID,
              case .awayDecision(let decision, let label, let reviewing, let id)? = correctionRetry,
              !reviewing, id == expectedID else { return false }
        return applyAwayDecision(decision, label: label, reviewing: false, expectedID: expectedID)
    }

    @discardableResult
    func applyAwayDecision(_ decision: UserDecision, label: String? = nil, reviewing: Bool,
                           expectedID: UUID? = nil) -> Bool {
        let currentID = reviewing ? (expectedID.flatMap { engine.awayDecision(id: $0)?.id }
            ?? (expectedID == nil ? engine.lastAwayDecision?.id : nil)) : engine.pendingDecisionID
        guard let id = currentID, expectedID == nil || expectedID == id else {
            if reviewing || expectedID != nil {
                publishCorrectionError("That interval was retired or changed. The current record was not changed.")
                correctionRetry = nil
            }
            return false
        }
        let saved = reviewing ? engine.reviseAwayDecision(decision, label: label, expectedID: id)
            : engine.decide(decision, label: label)
        guard saved else {
            if let error = engine.awayDecisionError {
                publishCorrectionError(error)
                // Offered again only while it can still land: its interval
                // stands, or its answer waits in the journal to be finalised.
                // One that newer saved history replaced could only fail a Retry.
                let retry = SessionCorrectionRetry.awayDecision(decision, label: label,
                                                                reviewing: reviewing, expectedID: id)
                let stands = reviewing ? engine.awayDecision(id: id) != nil : engine.pendingDecisionID == id
                correctionRetry = stands || engine.decisionHistory.document.pending.map(retry.matches) == true
                    ? retry : nil
            }
            return false
        }
        correctionRetry = nil
        publishCorrectionError(nil)
        publishCanUndoCorrection(engine.lastAwayDecision?.isResolved == true)
        apply(engine.state)
        return true
    }

    @discardableResult
    func undoAwayDecision(expectedID: UUID? = nil) -> Bool {
        guard let id = expectedID.flatMap({ engine.awayDecision(id: $0)?.id })
            ?? (expectedID == nil ? engine.lastAwayDecision?.id : nil) else {
            if expectedID != nil {
                publishCorrectionError("That Undo belongs to an earlier action. The current record was not changed.")
                correctionRetry = nil
            }
            return false
        }
        guard engine.undoAwayDecision(expectedID: id) else {
            publishCorrectionError(engine.awayDecisionError ?? "Finish the current away decision before undoing an earlier one.")
            correctionRetry = .awayUndo(id)
            return false
        }
        correctionRetry = nil
        publishCorrectionError(nil)
        publishCanUndoCorrection(false)
        apply(engine.state)
        return true
    }

    /// Names the break a resolved away decision wrote, and republishes the day.
    @discardableResult
    func nameBreak(decisionID: UUID, titled name: String) -> Bool {
        guard engine.nameBreak(decisionID: decisionID, to: name) else {
            publishCorrectionError(engine.awayDecisionError ?? "The break could not be renamed.")
            return false
        }
        publishCorrectionError(nil)
        apply(engine.state)
        return true
    }

    /// `--preview-away card` only: fakes a pending question so the popover and
    /// dashboard cards can be looked at without staging an absence. Touches
    /// nothing in the engine; answering resolves nothing and simply clears it.
    func previewPendingAway(_ away: TimeInterval) {
        pendingAwayRange = (start: Date().addingTimeInterval(-away), end: Date())
        pendingAway = away
    }
}
