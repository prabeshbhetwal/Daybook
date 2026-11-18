import Foundation

/// "Split here?" on a finished session that held two pieces of work: the moment, what the tail would
/// begin as, and what it mostly was, for the words. An offer is a read; nothing is written until the
/// person says Split.
struct SplitOffer: Equatable {
    let recordID: UUID
    let at: Date
    let choice: SplitTailChoice
    /// What the part after the cut mostly was, when the evidence says.
    let purpose: AppPurpose?
    let topApp: String?
}

/// "Merge back" on the tail of a split, naming the session it was cut from.
struct MergeBackOffer: Equatable {
    let tailID: UUID
    let headName: String
}

/// Who may split (spec section 4): the person's own sessions and a rule's are offered the cut, and only
/// the cut; an automatic session splits itself (`SessionStore+SplitAutomatic`) unless the person has made
/// it theirs, which gets the offer instead (ruling B11).
extension SessionStore {
    func splitOffer(for session: DaySession) -> SplitOffer? {
        guard !session.isRunning, !hasUnresolvedAwayDecision, !engine.archive.isReadOnly else { return nil }
        let records = engine.archive.records.filter { session.recordIDs.contains($0.id) }.sorted { $0.start < $1.start }
        for record in records where !record.splitsItself {
            if let moment = splitMoment(in: record) { return tailProposal(for: record, at: moment) }
        }
        return nil
    }

    func mergeBackOffer(for session: DaySession) -> MergeBackOffer? {
        guard !session.isRunning else { return nil }
        for id in session.recordIDs {
            if let pair = mergePair(tailID: id) { return MergeBackOffer(tailID: id, headName: pair.head.name) }
        }
        return nil
    }

    /// Split: the tail begins as Daybook chose, or as `picked` when the offer asked the person to pick,
    /// which makes the category theirs.
    @discardableResult
    func acceptSplit(_ offer: SplitOffer, as picked: WorkType? = nil) -> Bool {
        guard let record = engine.archive.records.first(where: { $0.id == offer.recordID }) else { return false }
        let (type, source): (WorkType, DecisionSource)
        switch offer.choice {
        case .chosen(let chosen, let from): (type, source) = (chosen, from)
        case .ask(let preset): (type, source) = (picked ?? preset, .user)
        }
        let tail = SplitTail(after: record, workType: type, source: source, purpose: offer.purpose, topApp: offer.topApp)
        return splitSession(recordID: offer.recordID, at: offer.at, tail: tail)
    }

    /// Keep Together: this moment is not offered again for this session.
    func declineSplit(_ offer: SplitOffer) {
        if case .failed(let why) = metadataArchive.declineSplit(at: offer.at, for: offer.recordID) {
            Diagnostics.log("Split: the answer to keep a session together was not saved: \(why)")
        }
    }
}
