import Foundation

/// What a category change of the person's teaches: the category, when it was chosen, and for each kind of
/// stretch the session held (its shape's fingerprint) the category it was in, unless the person had chosen
/// that one. Kept in memory with a change refused before its write, so Retry can teach it when it lands.
struct CategoryFiling {
    typealias Kind = (fingerprint: ActivityFingerprint, left: String?)
    let workType: WorkType
    let kinds: [Kind]
    let moment: Date
}

/// How the person files a kind of session, remembered and offered back (spec section 6). An offer is
/// a read: no stored record changes. A record changes only when the person takes the offer, through
/// the same path as any category change of theirs, which writes the category as theirs.
extension SessionStore {
    /// The category the person usually files this kind of session under. Offered only for a record whose
    /// category Daybook chose (`builtIn`: what the person or a rule chose is never second-guessed), only
    /// while it is a category they can still start, and never the one the record already has.
    func correctionSuggestion(for recordID: UUID) -> WorkType? {
        guard let record = engine.archive.records.first(where: { $0.id == recordID }),
              record.effectiveCategorySource == .builtIn,
              let fingerprint = metadataArchive.metadata(for: recordID)?.activityShape?.fingerprint,
              let remembered = categoryCorrections.suggestion(for: fingerprint, now: now()) else { return nil }
        let offered = WorkType(rawValue: remembered)
        return offered != record.workType && WorkType.startable.contains(offered) ? offered : nil
    }

    /// A finished session's offer: one only when every stretch of it has that same one.
    func correctionSuggestion(for session: DaySession) -> WorkType? {
        guard !session.isRunning else { return nil }
        let offers = session.recordIDs.map { correctionSuggestion(for: $0) }
        guard let first = offers.first, first != nil, offers.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// The person's own category change on a session: the ordinary correction, and the choice kept for
    /// next time. Kept once per kind of stretch however many stretches share it, and only for a finished
    /// session whose stretches have a stored shape, the one thing that says what kind of session it was.
    /// What it adds to the remembered choices travels with the correction, so Undo can take it back.
    @discardableResult
    func fileSession(_ session: DaySession, as workType: WorkType) -> Bool {
        let ids = Set(session.recordIDs)
        let before = session.isRunning ? [] : engine.archive.records.filter { ids.contains($0.id) }
        var seen = Set<ActivityFingerprint>(), kinds: [CategoryFiling.Kind] = []
        for record in before {
            guard let fingerprint = metadataArchive.metadata(for: record.id)?.activityShape?.fingerprint,
                  seen.insert(fingerprint).inserted else { continue }
            // Leaving a category the person chose themselves is no veto of it.
            let left = record.effectiveCategorySource == .user ? nil : record.workType.rawValue
            kinds.append((fingerprint: fingerprint, left: left))
        }
        return applyFiling(CategoryFiling(workType: workType, kinds: kinds, moment: now()),
                           threadID: session.threadID, claims: true)
    }

    /// The change `filing` stands for, and what it teaches, worked out against what is remembered now. A change
    /// refused before its write keeps the filing on its Retry, which comes back here and teaches it when it lands.
    func applyFiling(_ filing: CategoryFiling, threadID: UUID, claims: Bool) -> Bool {
        var next = categoryCorrections.corrections
        let filings = filing.kinds.map {
            next.record(fingerprint: $0.fingerprint, chosen: filing.workType.rawValue, vetoed: $0.left, at: filing.moment)
        }
        let correction = SessionCorrection.workType(filing.workType)
        let applied = applyCorrection(threadID: threadID, correction: correction, claims: claims, remembering: filings)
        guard !filings.isEmpty else { return applied }
        // A change that landed with only its journal save refused keeps its receipt, and Retry finishes that
        // save without filing anything: the choice is kept here, once.
        if applied || corrections.contains(where: { $0.remembered == filings }) {
            if let why = categoryCorrections.save(next, at: now()) {
                Diagnostics.log("Category choice not remembered: \(why)")
            }
        } else if case .correction(threadID, correction, let held, _)? = correctionRetry {
            correctionRetry = .correction(threadID: threadID, correction: correction, claims: held, filing: filing)
        }
        return applied
    }

    /// Retry of a correction refused before its write: done again, with what it teaches when it is a category change.
    func retryCorrection(threadID: UUID, correction: SessionCorrection, claims: Bool, filing: CategoryFiling?) -> Bool {
        guard let filing else { return applyCorrection(threadID: threadID, correction: correction, claims: claims) }
        return applyFiling(filing, threadID: threadID, claims: claims)
    }

    /// Undo of a category change takes back what it taught: that kind of session is no longer offered
    /// the category on its account. The choices to fall back to are the filings of the corrections made
    /// before this one that still stand, so one undone out of order is not revived.
    func forgetRemembered(of state: SessionStoreCorrectionState) {
        guard let filings = state.remembered, !filings.isEmpty else { return }
        let standing = corrections.filter { $0.sequence < state.sequence }.flatMap { $0.remembered ?? [] }
        guard let why = categoryCorrections.forget(filings, standing: standing, at: now()) else { return }
        Diagnostics.log("Category choice not forgotten: \(why)")
    }

    /// An undo whose write was refused: the error and Retry stay. When its records changed and only the
    /// journal save is owed (the correction is already gone from `corrections`), what the change taught is
    /// taken back now, once: Retry then only finishes the save and never comes back here.
    func undoRefused(_ state: SessionStoreCorrectionState) -> Bool {
        publishCorrectionError(engine.awayDecisionError)
        correctionRetry = .undo(state)
        if !corrections.contains(where: { $0.id == state.id }) { forgetRemembered(of: state) }
        return false
    }
}
