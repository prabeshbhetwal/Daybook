import Foundation

/// A session cut in two, and two cut halves joined again. Written the way an away correction is: staged
/// through `prepareCorrection`, committed through `commitCorrection` as one journalled transaction over
/// the whole records, with one correction entry that `undoLastCorrection()` reverses.
extension SessionEngine {
    /// Cuts the ended record `id` at `moment`: the head keeps it and the tail is a new record from `moment`
    /// to its end under `tail`. False, with `awayDecisionError` saying why, when `moment` is not inside the
    /// record's work or the write is refused; nothing is changed then. `tailID` lets the caller know the new
    /// record in advance. `owing`: what the cut owes the sidecar, journalled with it.
    @discardableResult
    func splitRecord(id: UUID, at moment: Date, tail: SplitTail, tailID: UUID = UUID(), owing: [OwedWork] = []) -> Bool {
        guard prepareCorrection() else { return false }
        guard let record = archive.records.first(where: { $0.id == id }),
              !(state != .idle && id == activeRecordID),
              let cut = record.split(at: moment, tail: tail, tailID: tailID) else {
            awayDecisionError = "That moment is not inside this session's work, so it can't be split there. Reopen the day and try again."
            return false
        }
        return commitRestructure(name: record.name, removing: [record], adding: [cut.head, cut.tail], owing: owing)
    }

    /// Joins `tail` back onto `head` when they touch, in that order: one record again, the head's. False,
    /// with the reason in `awayDecisionError`, when they do not or the write is refused.
    @discardableResult
    func mergeRecords(head headID: UUID, tail tailID: UUID, owing: [OwedWork] = []) -> Bool {
        guard prepareCorrection() else { return false }
        guard let head = archive.records.first(where: { $0.id == headID }),
              let tail = archive.records.first(where: { $0.id == tailID }),
              let joined = SessionRecord.merged(head: head, tail: tail) else {
            awayDecisionError = "Those two parts no longer follow one another, so they can't be merged. Reopen the day and try again."
            return false
        }
        return commitRestructure(name: head.name, removing: [head, tail], adding: [joined], owing: owing)
    }

    /// Writes ended records back changed under their own ids, all as one correction, so one Undo puts every
    /// one back exactly as it was. False, with the reason in `awayDecisionError`, when one is no longer in
    /// the archive or is the running stretch, or the write is refused; nothing is changed then. `filings`: what
    /// the change taught the remembered choices, kept on its receipt so its Undo takes them back.
    @discardableResult
    func rewriteRecords(_ changed: [SessionRecord], remembering filings: [RememberedFiling] = []) -> Bool {
        guard prepareCorrection() else { return false }
        let originals = changed.compactMap { next in archive.records.first { $0.id == next.id } }
        guard !changed.isEmpty, originals.count == changed.count,
              !(state != .idle && changed.contains { $0.id == activeRecordID }) else {
            awayDecisionError = "Those sessions changed since. Reopen the day and try again."
            return false
        }
        return commitRestructure(name: originals[0].name, removing: originals, adding: changed, owing: [],
                                 remembering: filings)
    }

    /// Saved as a removal that also holds what it wrote in, so an older build still reads the history.
    private func commitRestructure(name: String, removing: [SessionRecord], adding: [SessionRecord],
                                   owing: [OwedWork], remembering filings: [RememberedFiling] = []) -> Bool {
        let before = snapshot()
        var receipt = SessionStoreCorrectionState(
            sequence: (before.correctionGeneration ?? 0) + 1, threadID: removing[0].threadID, correction: .removed,
            archiveSnapshot: nil, originalFields: .init(name: name, workType: removing[0].workType),
            archiveRecordIDs: Set((removing + adding).map(\.id)))
        receipt.removedRecords = removing
        receipt.addedRecords = adding
        receipt.madeAt = now()
        receipt.remembered = filings.isEmpty ? nil : filings
        return commitCorrection(before: before, removing: removing, adding: adding,
                                fields: fieldCorrections + [receipt], owing: owing)
    }
}
