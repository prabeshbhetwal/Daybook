import Foundation

/// A session cut in two, and two cut halves joined again. Written the way an away correction is: staged
/// through `prepareCorrection`, committed through `commitCorrection` as one journalled transaction over
/// the whole records, with one correction entry that `undoLastCorrection()` reverses.
extension SessionEngine {
    /// Cuts the ended record `id` at `moment`: the head keeps it and the tail is a new record from `moment`
    /// to its end under `tail`. False, with `awayDecisionError` saying why, when `moment` is not inside the
    /// record's work or the write is refused; nothing is changed then. `tailID` lets the caller know the new
    /// record in advance.
    @discardableResult
    func splitRecord(id: UUID, at moment: Date, tail: SplitTail, tailID: UUID = UUID()) -> Bool {
        guard prepareCorrection() else { return false }
        guard let record = archive.records.first(where: { $0.id == id }),
              !(state != .idle && id == activeRecordID),
              let cut = record.split(at: moment, tail: tail, tailID: tailID) else {
            awayDecisionError = "That moment is not inside this session's work, so it can't be split there. Reopen the day and try again."
            return false
        }
        return commitRestructure(.split, name: record.name, removing: [record], adding: [cut.head, cut.tail])
    }

    /// Joins `tail` back onto `head` when they touch, in that order: one record again, the head's. False,
    /// with the reason in `awayDecisionError`, when they do not or the write is refused.
    @discardableResult
    func mergeRecords(head headID: UUID, tail tailID: UUID) -> Bool {
        guard prepareCorrection() else { return false }
        guard let head = archive.records.first(where: { $0.id == headID }),
              let tail = archive.records.first(where: { $0.id == tailID }),
              let joined = SessionRecord.merged(head: head, tail: tail) else {
            awayDecisionError = "Those two parts no longer follow one another, so they can't be merged. Reopen the day and try again."
            return false
        }
        return commitRestructure(.merge, name: head.name, removing: [head, tail], adding: [joined])
    }

    private func commitRestructure(_ kind: SessionCorrection, name: String, removing: [SessionRecord],
                                   adding: [SessionRecord]) -> Bool {
        let before = snapshot()
        var receipt = SessionStoreCorrectionState(
            sequence: (before.correctionGeneration ?? 0) + 1, threadID: removing[0].threadID, correction: kind,
            archiveSnapshot: nil, originalFields: .init(name: name, workType: removing[0].workType),
            archiveRecordIDs: Set((removing + adding).map(\.id)))
        receipt.removedRecords = removing
        receipt.addedRecords = adding
        receipt.madeAt = now()
        return commitCorrection(before: before, removing: removing, adding: adding,
                                fields: fieldCorrections + [receipt])
    }
}
