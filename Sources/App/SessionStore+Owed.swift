import Foundation

/// Doing what corrections owe beyond the archive (`OwedWork`): right after their records are written, and again
/// on each refresh, and so at launch, until the journal can drop it.
extension SessionStore {
    /// The one whose failure was last logged, so a sidecar that stays unwritable is said once, not on each refresh.
    private static var lastOwedFailure: String?

    func owedWork(_ steps: [OwedStep]) -> [OwedWork] { steps.isEmpty ? [] : [OwedWork(steps: steps)] }

    /// Does the work owed by corrections whose records are written, oldest first. Work that fails is kept, and so
    /// is any later work on a record it touches, which may rest on it; work on others goes on, so a sidecar
    /// that stays unwritable never holds back what is owed the remembered choices. What was done is then dropped
    /// from the journal. Returns the records whose owed work is still not done.
    @discardableResult
    func settleOwedWork() -> Set<UUID> {
        let owed = engine.decisionHistory.owed(in: engine.archive)
        guard !owed.isEmpty else { return [] }
        var done = Set<UUID>(), blocked = Set<UUID>()
        for work in owed {
            if !blocked.isDisjoint(with: work.recordIDs) { blocked.formUnion(work.recordIDs); continue }
            if let why = perform(work) { noteOwedFailure(why); blocked.formUnion(work.recordIDs); continue }
            done.insert(work.id)
        }
        if let why = engine.decisionHistory.settle(done) { noteOwedFailure(why) }
        return blocked
    }

    /// A split, a join or an Undo works out its own steps from the sidecar, so it waits while an earlier change
    /// still owes these records work: true, with the reason published, when it has to.
    func waitsForOwedWork(on ids: Set<UUID>, blocked: Set<UUID>) -> Bool {
        guard !blocked.isDisjoint(with: ids) else { return false }
        publishCorrectionError("An earlier change to this session could not be saved yet, so this has to wait. Try again once it is saved.")
        return true
    }

    private func perform(_ work: OwedWork) -> String? {
        for step in work.steps { if let why = perform(step) { return why } }
        return nil
    }

    private func perform(_ step: OwedStep) -> String? {
        let result: SessionMetadataWriteResult
        switch step {
        case .link(let record, let link): result = metadataArchive.saveSplitLink(link, for: record)
        case .summary(let record, let shape): result = metadataArchive.replaceActivityShape(shape, for: record)
        case .headSummary(let tail, let shape): result = metadataArchive.setAsideHeadSummary(shape, on: tail)
        case .movePower(let from, let to, let boundary):
            result = metadataArchive.reassignPower(from: from, to: to, atOrAfter: boundary)
        case .forget(let sequence, let filings):
            return forgetRemembered(sequence: sequence, filings: filings)
        }
        if case .failed(let why) = result { return why }
        return nil
    }

    private func noteOwedFailure(_ why: String) {
        guard Self.lastOwedFailure != why else { return }
        Self.lastOwedFailure = why
        Diagnostics.log("A correction's follow-up work was not finished, and is kept to try again: \(why)")
    }
}
