import Foundation

/// What a correction owes beyond the archive (`OwedWork`) is done as soon as its records are written, and done
/// again on each refresh, and so at launch, until the journal can drop it. A crash or a refused write between
/// the records and the sidecar then leaves it owed, never lost. Every step sets a value, so doing one twice
/// changes nothing.
extension SessionStore {
    /// The one whose failure was last logged, so a sidecar that stays unwritable is said once, not on each refresh.
    private static var lastOwedFailure: String?

    func owedWork(_ steps: [OwedStep]) -> [OwedWork] { steps.isEmpty ? [] : [OwedWork(steps: steps)] }

    /// Does the work owed by corrections whose records are written, oldest first. Work that fails is kept, and so
    /// is any later work on a record it touches, which may rest on it; work on others goes on, so a sidecar
    /// that stays unwritable never holds back what is owed the remembered choices. What was done is then dropped
    /// from the journal.
    func settleOwedWork() {
        let owed = engine.decisionHistory.owed(in: engine.archive)
        guard !owed.isEmpty else { return }
        var done = Set<UUID>(), blocked = Set<UUID>()
        for work in owed {
            if !blocked.isDisjoint(with: work.recordIDs) { blocked.formUnion(work.recordIDs); continue }
            if let why = perform(work) { noteOwedFailure(why); blocked.formUnion(work.recordIDs); continue }
            done.insert(work.id)
        }
        if let why = engine.decisionHistory.settle(done) { noteOwedFailure(why) }
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
