import Foundation

/// An automatic session that has just ended and held two pieces of work splits itself (spec section 4),
/// as one correction with Undo and Merge Back, and only when Daybook may choose what the tail is: its
/// dominant purpose is focused work (ruling B8). Otherwise the session stays whole and the strip and the
/// report show the detour. A session the person has renamed or filed is theirs and gets the offer.
extension SessionStore {
    /// Each record is judged once, when it first appears: the first pass of a launch only notes what is
    /// already there, so nothing recorded before is ever split behind the person's back.
    func splitFinishedAutomaticSessions() {
        let evidence = activityEvidence
        guard evidence.enabled, !engine.archive.isReadOnly else { return }
        let records = engine.archive.records
        guard evidence.splitSeen != nil else { evidence.splitSeen = Set(records.map(\.id)); return }
        // An open away question refuses every cut: the session is judged once it is answered, not lost.
        guard !hasUnresolvedAwayDecision else { return }
        let moment = now()
        for record in records where record.end <= moment {
            // Read each time: a cut refreshes, and the pass that refresh starts may have judged this record.
            guard evidence.splitSeen?.contains(record.id) == false else { continue }
            // The beat holding its last seconds is still open: judged on a later pass.
            if evidence.recording, record.end > moment.addingTimeInterval(-ActivityConstants.beatLength) { continue }
            evidence.splitSeen?.insert(record.id)
            guard record.splitsItself, let at = splitMoment(in: record) else { continue }
            let proposal = tailProposal(for: record, at: at)
            guard case .chosen = proposal.choice else { continue }
            // Nobody asked for this write: the person's own error and Retry stay as they were, and a refusal
            // is not put in front of them, but turns the cut into an offer (`splitOffer`).
            let error = correctionError, retry = correctionRetry
            if !acceptSplit(proposal, byPerson: false), engine.archive.records.contains(record) {
                evidence.splitRefused.insert(record.id)
            }
            publishCorrectionError(error)
            correctionRetry = retry
        }
    }
}
