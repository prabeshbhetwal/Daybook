import Foundation

/// Cutting an ended session in two and joining the halves again. The records change through the engine,
/// as one journalled correction each; here the sidecar follows (the link, the shape, the power readings)
/// and the surfaces are told. Nothing here moves a total: the halves add up to the record.
extension SessionStore {
    /// Cuts the ended record `recordID` at `moment`; the tail begins as `choice` says. One correction,
    /// reversed by Undo. False, with the reason published, when the moment is not inside the session's work
    /// or the write is refused, and then nothing was changed.
    @discardableResult
    func splitSession(recordID: UUID, at moment: Date, tail choice: SplitTail) -> Bool {
        guard !hasUnresolvedAwayDecision else {
            publishCorrectionError("Answer the away question first."); return false
        }
        guard let record = engine.archive.records.first(where: { $0.id == recordID }),
              let cut = record.split(at: moment, tail: choice) else {
            publishCorrectionError("That moment is not inside this session's work, so it can't be split there.")
            return false
        }
        guard engine.splitRecord(id: recordID, at: moment, tail: choice, tailID: cut.tail.id) else {
            publishCorrectionError(engine.awayDecisionError)
            correctionRetry = .correction(threadID: record.threadID, correction: .split)
            return false
        }
        logSidecar(metadataArchive.saveSplitLink(SplitLink(head: cut.head, tail: cut.tail), for: cut.tail.id), "split link")
        // Beats may have expired: the tail then reads the part of the summary the whole kept that falls in it.
        if let kept = metadataArchive.metadata(for: record.id)?.activityShape {
            logSidecar(metadataArchive.saveActivityShape(kept.clipped(to: DateInterval(start: moment, end: record.end)),
                                                   for: cut.tail.id), "tail summary")
        }
        movePower(head: record.id, tail: cut.tail, toTail: true)
        finishRestructure()
        return true
    }

    /// The tail of a split, offered Merge Back: it touches its head, neither has been renamed or filed
    /// elsewhere since the cut, and the person has written nothing on the tail.
    func canMergeBack(recordID: UUID) -> Bool { mergePair(tailID: recordID) != nil }

    /// Joins the tail of a split back onto its head: one correction, reversed by Undo.
    @discardableResult
    func mergeBack(tailID: UUID) -> Bool {
        guard let pair = mergePair(tailID: tailID) else {
            publishCorrectionError("This session was changed after it was split, so it can't be merged back. Undo the change first.")
            return false
        }
        guard engine.mergeRecords(head: pair.head.id, tail: tailID) else {
            publishCorrectionError(engine.awayDecisionError)
            correctionRetry = .correction(threadID: pair.head.threadID, correction: .merge)
            return false
        }
        movePower(head: pair.head.id, tail: pair.tail, toTail: false)
        finishRestructure()
        return true
    }

    func mergePair(tailID: UUID) -> (head: SessionRecord, tail: SessionRecord)? {
        let records = engine.archive.records
        guard !engine.archive.isReadOnly, !hasUnresolvedAwayDecision,
              let entry = metadataArchive.metadata(for: tailID), let link = entry.splitFrom, entry.note == nil,
              let tail = records.first(where: { $0.id == tailID }),
              let head = records.first(where: { $0.id == link.head }),
              link.holds(head: head, tail: tail) else { return nil }
        return (head, tail)
    }

    /// Undo of a correction that swapped whole records: a removal, a split or a merge. The records it wrote
    /// in come out and the ones it took out go back, whole, provided nothing has since taken their identity
    /// and the ones to come out are still as it wrote them (the archive checks that).
    func undoRestoringRecords(_ state: SessionStoreCorrectionState, before: PersistedState) -> Bool {
        let back = state.removedRecords ?? [], out = state.addedRecords ?? []
        let present = Set(engine.archive.records.map(\.id)).subtracting(out.map(\.id))
        guard !back.isEmpty, back.allSatisfy({ !present.contains($0.id) }) else {
            publishCorrectionError("That session is already back, or its stretches were rewritten since. Reopen the day to see it.")
            return false
        }
        guard engine.commitCorrection(before: before, removing: out, adding: back,
                                      fields: corrections.filter { $0.id != state.id }) else {
            publishCorrectionError(engine.awayDecisionError)
            correctionRetry = .undo(state)
            return false
        }
        if let parts = state.restructuredParts { movePower(head: parts.head, tail: parts.tail, toTail: state.correction == .merge) }
        publishCanUndoCorrection(!corrections.isEmpty || engine.canUndoAwayDecision)
        publishCorrectionError(nil)
        correctionRetry = nil
        refresh()
        return true
    }

    private func finishRestructure() {
        publishCanUndoCorrection(true)
        publishCorrectionError(nil)
        correctionRetry = nil
        refresh()
    }

    /// The power readings from the cut on belong to the tail, and come back to the head when it is joined.
    private func movePower(head: UUID, tail: SessionRecord, toTail: Bool) {
        logSidecar(toTail ? metadataArchive.reassignPower(from: head, to: tail.id, atOrAfter: tail.start)
                    : metadataArchive.reassignPower(from: tail.id, to: head, atOrAfter: tail.start), "power readings")
    }

    /// A sidecar write that failed costs the link or the readings, never the split: said in the log only.
    private func logSidecar(_ result: SessionMetadataWriteResult, _ what: String) {
        if case .failed(let why) = result { Diagnostics.log("Split: the \(what) were not saved: \(why)") }
    }
}

extension SessionStoreCorrectionState {
    /// The head's id and the tail's record, for a split or a merge.
    var restructuredParts: (head: UUID, tail: SessionRecord)? {
        let removed = removedRecords ?? [], added = addedRecords ?? []
        switch correction {
        case .split:
            guard let head = removed.first?.id, let tail = added.first(where: { $0.id != head }) else { return nil }
            return (head, tail)
        case .merge:
            guard let head = added.first?.id, let tail = removed.first(where: { $0.id != head }) else { return nil }
            return (head, tail)
        case .rename, .workType, .removed:
            return nil
        }
    }

    /// What the day's notice says of a correction that swapped whole records.
    var restructureTitle: String {
        switch correction {
        case .split: return "Session split"
        case .merge: return "Sessions merged"
        case .rename, .workType, .removed: return "Session removed"
        }
    }
}
