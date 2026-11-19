import Foundation

/// A write-ahead journal for narrow corrections. The ordinary session file
/// remains an array, so existing readers and backups remain compatible.
final class DecisionHistory {
    enum Operation: String, Codable {
        case correction, endStretch, discardStretch, automaticSwitch, metadataOnly
        var updatesLiveState: Bool { self != .metadataOnly }
    }
    enum CommitResult {
        case saved, committedAwaitingFinalisation(String), refused(String)
        var didCommit: Bool {
            if case .refused = self { return false }; return true
        }
        var error: String? {
            switch self {
            case .saved: return nil
            case .committedAwaitingFinalisation(let error), .refused(let error): return error
            }
        }
    }
    /// Receipt identity has no authority over the live clock or pause state.
    struct MetadataCheckpoint: Codable {
        let generation: Int
        let awayDecisions: [AwayDecisionReceipt]
        init(_ state: PersistedState) {
            generation = state.correctionGeneration ?? 0
            awayDecisions = state.awayDecisions ?? state.awayDecision.map { [$0] } ?? []
        }
        func applying(to state: PersistedState) -> PersistedState {
            var result = state
            result.correctionGeneration = generation
            result.awayDecisions = awayDecisions
            result.awayDecision = awayDecisions.last
            return result
        }
    }
    struct Transaction: Codable {
        let id: UUID
        let before: PersistedState
        let after: PersistedState
        let removed: [SessionRecord]
        let added: [SessionRecord]
        let fieldsBefore: [SessionStoreCorrectionState]
        let fieldsAfter: [SessionStoreCorrectionState]
        /// Optional for sidecars written before durable retention was explicit.
        var retiredRecordIDs: Set<UUID>? = nil
        /// Missing means the earlier live-authoritative journal contract.
        var operation: Operation? = nil
        /// What the correction owes beyond the archive; it joins the document's once the records are in.
        var owed: [OwedWork]? = nil
        var updatesLiveState: Bool { operation?.updatesLiveState ?? true }
    }
    struct Document: Codable {
        var version = 1
        var checkpoint: PersistedState?
        var metadataCheckpoint: MetadataCheckpoint?
        var fields: [SessionStoreCorrectionState] = []
        var pending: Transaction?
        /// Work owed by corrections whose records are written, until the store says it is done. Missing in
        /// journals written before it, and ignored by a build that does not know it.
        var owed: [OwedWork]?
    }
    private let url: URL
    private let writeOverride: (() -> String?)?
    private(set) var document = Document()
    private(set) var error: String?
    var metadata: MetadataCheckpoint? {
        document.metadataCheckpoint ?? document.checkpoint.map(MetadataCheckpoint.init)
    }
    /// `error` is left out: it refuses corrections (`reconcile`), but an
    /// ending with nothing to journal goes through the archive. With it in,
    /// a history file this build cannot read refused every Stop, Reset and
    /// long-away end, and every relaunch did the same.
    var requiresTerminalCheckpoint: Bool { metadata != nil || document.pending != nil }

    private struct Stamp: Decodable { let version: Int? }

    init(directory: URL, writeOverride: (() -> String?)? = nil, now: Date = Date()) {
        url = directory.appendingPathComponent("correction-history.json")
        self.writeOverride = writeOverride
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try? Data(contentsOf: url)
        // A newer build's file is left exactly as it is and nothing of it is
        // used; corrections stay refused until Daybook is updated.
        if let data, let version = (try? JSONDecoder().decode(Stamp.self, from: data))?.version, version != 1 {
            error = "Correction history was written by a newer version of Daybook. Its file was kept. Update Daybook to read it."
            return
        }
        do {
            document = try JSONDecoder().decode(Document.self, from: data ?? Data(contentsOf: url))
        } catch {
            // Set aside as the other archives do, and start from an empty
            // history. Read-only only when it cannot be moved.
            if UnreadableFile.setAside(url, prefix: "correction-history-corrupt-",
                                       pathExtension: "json", at: now) == nil {
                self.error = "Correction history couldn't be read. \(error.localizedDescription.endingInFullStop) Its file was kept. Reopen Daybook to try again."
            }
        }
    }

    /// No whole-archive snapshot: compare only the exact records this operation
    /// touches. Newer ordinary work is never replaced or removed by recovery.
    func reconcile(archive: SessionArchive) -> String? {
        if let error { return error }
        guard let pending = document.pending else { return nil }
        let ids = Set((pending.removed + pending.added).map(\.id))
        let actual = archive.records.filter { ids.contains($0.id) }
        func matches(_ expected: [SessionRecord]) -> Bool {
            actual.count == expected.count && expected.allSatisfy { actual.contains($0) }
        }
        var next = document
        if matches(pending.added) {
            if pending.updatesLiveState { next.checkpoint = pending.after }
            next.metadataCheckpoint = MetadataCheckpoint(pending.after)
            next.fields = pending.fieldsAfter
            next.owed = Self.owing(next.owed, adding: pending.owed)
        } else if matches(pending.removed) {
            if pending.updatesLiveState { next.checkpoint = pending.before }
            next.metadataCheckpoint = MetadataCheckpoint(pending.before)
            next.fields = pending.fieldsBefore
        } else {
            return "A pending correction conflicts with newer changes. No records were replaced. Review the day, then try again."
        }
        next.pending = nil
        return save(next)
    }

    func commit(before: PersistedState, after: PersistedState,
                removing: [SessionRecord] = [], adding: [SessionRecord] = [],
                fields: [SessionStoreCorrectionState]? = nil,
                archive: SessionArchive, allowsEviction: Bool = false,
                operation: Operation = .correction, owing: [OwedWork] = []) -> CommitResult {
        if let failure = reconcile(archive: archive) { return .refused(failure) }
        // Capacity must be checked before journalling. Initial answers may
        // retain ordinary archive retention; historical corrections may not.
        if let failure = archive.validateEdit(removing: removing, adding: adding,
                                               allowsEviction: allowsEviction) { return .refused(failure) }
        let retired = allowsEviction ? archive.capacityRetirements(removing: removing, adding: adding) : []
        let retiredIDs = Set(retired.map(\.id)), removalIDs = Set(removing.map(\.id))
        let scopedRemovals = removing + archive.records.filter { retiredIDs.contains($0.id) && !removalIDs.contains($0.id) }
        let scopedAdditions = adding.filter { !retiredIDs.contains($0.id) }
        let scopedIDs = Set(scopedRemovals.map(\.id))
        let surviving = archive.records.filter { !scopedIDs.contains($0.id) } + scopedAdditions
        let retained = CorrectionRetention.applying(retired, to: after, fields: fields ?? document.fields, surviving: surviving)
        let transaction = Transaction(id: UUID(), before: before, after: retained.state,
            removed: scopedRemovals, added: scopedAdditions, fieldsBefore: document.fields,
            fieldsAfter: retained.fields, retiredRecordIDs: retiredIDs, operation: operation,
            owed: owing.isEmpty ? nil : owing)
        var prepared = document
        prepared.pending = transaction
        if let failure = save(prepared) { return .refused(failure) }
        if let failure = archive.edit(removing: scopedRemovals, adding: scopedAdditions) {
            return .refused(failure)
        }
        var committed = prepared
        if operation.updatesLiveState { committed.checkpoint = transaction.after }
        committed.metadataCheckpoint = MetadataCheckpoint(transaction.after)
        committed.fields = transaction.fieldsAfter
        committed.owed = Self.owing(committed.owed, adding: transaction.owed)
        committed.pending = nil
        if let failure = save(committed) { return .committedAwaitingFinalisation(failure) }
        return .saved
    }

    /// Work still owed by corrections whose records are written, oldest first: the document's, and what a
    /// transaction that is still pending carries when its records are already in.
    func owed(in archive: SessionArchive) -> [OwedWork] {
        let finished = pendingAfterIsCommitted(in: archive) ? document.pending?.owed : nil
        return Self.owing(document.owed, adding: finished) ?? []
    }

    /// The sidecar entries that work still owed must not outlive: retention keeps them.
    var owedRecordIDs: Set<UUID> {
        (document.owed ?? []).reduce(into: Set(document.pending?.owed?.flatMap(\.recordIDs) ?? [])) {
            $0.formUnion($1.recordIDs)
        }
    }

    /// Drops work the store has done. Nil when saved, or when none of it was in the document.
    func settle(_ ids: Set<UUID>) -> String? {
        guard let held = document.owed, held.contains(where: { ids.contains($0.id) }) else { return nil }
        var next = document
        let rest = held.filter { !ids.contains($0.id) }
        next.owed = rest.isEmpty ? nil : rest
        return save(next)
    }

    private static func owing(_ held: [OwedWork]?, adding more: [OwedWork]?) -> [OwedWork]? {
        let kept = held ?? []
        let added = (more ?? []).filter { work in !kept.contains { $0.id == work.id } }
        return kept.isEmpty && added.isEmpty ? nil : kept + added
    }

    func pendingAfterIsCommitted(in archive: SessionArchive) -> Bool {
        guard let pending = document.pending else { return false }
        let ids = Set((pending.removed + pending.added).map(\.id))
        let actual = archive.records.filter { ids.contains($0.id) }
        return actual.count == pending.added.count && pending.added.allSatisfy { actual.contains($0) }
    }

    func committedMetadata(in archive: SessionArchive) -> MetadataCheckpoint? {
        if pendingAfterIsCommitted(in: archive), let pending = document.pending {
            return MetadataCheckpoint(pending.after)
        }
        return metadata
    }

    private func save(_ next: Document) -> String? {
        if let failure = writeOverride?() { return failure }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            document = next
            return nil
        } catch { return "Correction history couldn't be saved. \(error.localizedDescription.endingInFullStop) Check free space and folder access, then try again." }
    }
}
