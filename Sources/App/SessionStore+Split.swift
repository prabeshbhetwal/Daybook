import Foundation

/// Cutting an ended session in two and joining the halves again. The records change through the engine,
/// as one journalled correction each; here the sidecar follows (the link, the shape, the power readings)
/// and the surfaces are told. Nothing here moves a total: the halves add up to the record.
extension SessionStore {
    /// Cuts the ended record `recordID` at `moment`; the tail begins as `choice` says. One correction,
    /// reversed by Undo. False, with the reason published, when the moment is not inside the session's work
    /// or the write is refused, and then nothing was changed. A write that landed with only its journal
    /// save refused returns false too, with the error and Retry shown, and has its link and readings.
    @discardableResult
    func splitSession(recordID: UUID, at moment: Date, tail choice: SplitTail, tailID: UUID = UUID()) -> Bool {
        guard !hasUnresolvedAwayDecision else {
            publishCorrectionError("Answer the away question first."); return false
        }
        guard let record = engine.archive.records.first(where: { $0.id == recordID }),
              let cut = record.split(at: moment, tail: choice, tailID: tailID) else {
            publishCorrectionError("That moment is not inside this session's work, so it can't be split there.")
            return false
        }
        let done = engine.splitRecord(id: recordID, at: moment, tail: choice, tailID: tailID)
        let landed = done || engine.archive.records.contains { $0.id == tailID }
        if landed {
            logSidecar(metadataArchive.saveSplitLink(SplitLink(head: cut.head, tail: cut.tail), for: tailID), "split link")
            // Beats may have expired: the tail then reads the part of the summary the whole kept that falls in it.
            if let kept = metadataArchive.metadata(for: record.id)?.activityShape {
                logSidecar(metadataArchive.saveActivityShape(kept.clipped(to: DateInterval(start: moment, end: record.end)),
                                                       for: tailID), "tail summary")
            }
            movePower(head: record.id, tail: cut.tail, toTail: true)
        }
        return finishRestructure(done: done, landed: landed,
                                 retry: .split(threadID: record.threadID, recordID: recordID, at: moment,
                                               tail: choice, tailID: tailID))
    }

    /// The tail of a split, offered Merge Back: it touches its head, neither has been renamed or filed
    /// elsewhere since the cut, the person has written nothing on the tail, and it has not been cut again
    /// (a later part of it is joined back first).
    func canMergeBack(recordID: UUID) -> Bool { mergePair(tailID: recordID) != nil }

    /// Joins the tail of a split back onto its head: one correction, reversed by Undo.
    @discardableResult
    func mergeBack(tailID: UUID) -> Bool {
        guard let pair = mergePair(tailID: tailID) else {
            publishCorrectionError(hasLaterPart(of: tailID)
                ? "This session was split again, so it can't be merged back yet. Merge its later part back first."
                : "This session was changed after it was split, so it can't be merged back. Undo the change first.")
            return false
        }
        let done = engine.mergeRecords(head: pair.head.id, tail: tailID)
        let landed = done || !engine.archive.records.contains { $0.id == tailID }
        if landed {
            movePower(head: pair.head.id, tail: pair.tail, toTail: false)
            joinSummaries(head: pair.head, tail: pair.tail, keepingHead: true)
        }
        return finishRestructure(done: done, landed: landed,
                                 retry: .merge(threadID: pair.head.threadID, tailID: tailID))
    }

    /// Retry of a cut or a join refused before its records changed: done again, with the same arguments. One
    /// that landed with only its journal save refused never gets here while that journal is pending, which
    /// finishes it. If another write finished the journal first and left this Retry behind, the cut or the
    /// join stands (its tail is in the archive, or gone) and there is nothing to do but clear the error.
    func retryRestructure(_ retry: SessionCorrectionRetry) -> Bool {
        func tailExists(_ id: UUID) -> Bool { engine.archive.records.contains { $0.id == id } }
        switch retry {
        case .split(_, let recordID, let moment, let tail, let tailID):
            if tailExists(tailID) { return restructureStands() }
            return splitSession(recordID: recordID, at: moment, tail: tail, tailID: tailID)
        case .merge(_, let tailID):
            if !tailExists(tailID) { return restructureStands() }
            return mergeBack(tailID: tailID)
        default:
            return false
        }
    }

    private func restructureStands() -> Bool {
        publishCorrectionError(nil)
        correctionRetry = nil
        return true
    }

    func mergePair(tailID: UUID) -> (head: SessionRecord, tail: SessionRecord)? {
        let records = engine.archive.records
        guard !engine.archive.isReadOnly, !hasUnresolvedAwayDecision,
              let entry = metadataArchive.metadata(for: tailID), let link = entry.splitFrom, entry.note == nil,
              let tail = records.first(where: { $0.id == tailID }),
              let head = records.first(where: { $0.id == link.head }),
              link.holds(head: head, tail: tail), !hasLaterPart(of: tailID) else { return nil }
        return (head, tail)
    }

    /// Whether a record still in the archive was cut from this one. Its link names this record as the head, so
    /// joining this one to its own head first would take away the record that link points at. Any such link
    /// counts, held or not: a part renamed since can be joined again once the rename is undone.
    private func hasLaterPart(of recordID: UUID) -> Bool {
        engine.archive.records.contains { metadataArchive.metadata(for: $0.id)?.splitFrom?.head == recordID }
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
        // The second part's note lives in the sidecar and goes with its record; Merge Back refuses such a part too.
        if state.restructure == .split, let tail = state.restructuredParts?.tail,
           metadataArchive.metadata(for: tail.id)?.note != nil {
            publishCorrectionError("The second part of this session has a note, so undoing the split would lose it. Remove the note first.")
            return false
        }
        let done = engine.commitCorrection(before: before, removing: out, adding: back,
                                           fields: corrections.filter { $0.id != state.id })
        let landed = done || back.allSatisfy { engine.archive.records.contains($0) }
        if landed, let parts = state.restructuredParts {
            movePower(head: parts.head, tail: parts.tail, toTail: state.restructure == .merge)
            summariesFollowUndo(of: state, parts: parts)
        }
        return finishRestructure(done: done, landed: landed, retry: .undo(state))
    }

    /// How a restructure ended. One whose archive write landed with only its journal save refused shows the
    /// change and keeps the error and Retry. Retry finishes that save and does no more, so the link and the
    /// readings are written before it, never left to it.
    private func finishRestructure(done: Bool, landed: Bool, retry: SessionCorrectionRetry) -> Bool {
        publishCorrectionError(done ? nil : engine.awayDecisionError)
        correctionRetry = done ? nil : retry
        if landed {
            publishCanUndoCorrection(!corrections.isEmpty || engine.canUndoAwayDecision)
            refresh()
        }
        return done
    }

    /// The power readings from the cut on belong to the tail, and come back to the head when it is joined.
    private func movePower(head: UUID, tail: SessionRecord, toTail: Bool) {
        logSidecar(toTail ? metadataArchive.reassignPower(from: head, to: tail.id, atOrAfter: tail.start)
                    : metadataArchive.reassignPower(from: tail.id, to: head, atOrAfter: tail.start), "power readings")
    }

    /// A sidecar write that failed costs the link or the readings, never the split: said in the log only.
    func logSidecar(_ result: SessionMetadataWriteResult, _ what: String) {
        if case .failed(let why) = result { Diagnostics.log("Split: the \(what) were not saved: \(why)") }
    }
}

extension SessionStoreCorrectionState {
    /// The head's id and the tail's record, for a split or a merge.
    var restructuredParts: (head: UUID, tail: SessionRecord)? {
        let removed = removedRecords ?? [], added = addedRecords ?? []
        switch restructure {
        case .split?:
            guard let head = removed.first?.id, let tail = added.first(where: { $0.id != head }) else { return nil }
            return (head, tail)
        case .merge?:
            guard let head = added.first?.id, let tail = removed.first(where: { $0.id != head }) else { return nil }
            return (head, tail)
        case .removal?, nil:
            return nil
        }
    }

    /// What the day's notice says of a correction that swapped whole records.
    var restructureTitle: String {
        switch restructure {
        case .split?: return "Session split"
        case .merge?: return "Sessions merged"
        case .removal?, nil: return "Session removed"
        }
    }
}
