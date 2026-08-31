import Foundation

/// A write-ahead journal for narrow corrections. The ordinary session file
/// remains an array, so existing readers and backups remain compatible.
final class DecisionHistory {
    struct Transaction: Codable {
        let id: UUID
        let before: PersistedState
        let after: PersistedState
        let removed: [SessionRecord]
        let added: [SessionRecord]
        let fieldsBefore: [SessionStoreCorrectionState]
        let fieldsAfter: [SessionStoreCorrectionState]
    }
    struct Document: Codable {
        var version = 1
        var checkpoint: PersistedState?
        var fields: [SessionStoreCorrectionState] = []
        var pending: Transaction?
    }
    private let url: URL
    private let writeOverride: (() -> String?)?
    private(set) var document = Document()
    private(set) var error: String?

    init(directory: URL, writeOverride: (() -> String?)? = nil) {
        url = directory.appendingPathComponent("correction-history.json")
        self.writeOverride = writeOverride
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            if document.version != 1 { error = "Correction history has an unsupported version. Its file was preserved." }
        } catch {
            self.error = "Correction history could not be read. Its file was preserved: \(error.localizedDescription)"
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
            next.checkpoint = pending.after
            next.fields = pending.fieldsAfter
        } else if matches(pending.removed) {
            next.checkpoint = pending.before
            next.fields = pending.fieldsBefore
        } else {
            return "A pending correction conflicts with newer evidence. No records were replaced."
        }
        next.pending = nil
        return save(next)
    }

    func commit(before: PersistedState, after: PersistedState,
                removing: [SessionRecord] = [], adding: [SessionRecord] = [],
                fields: [SessionStoreCorrectionState]? = nil,
                archive: SessionArchive, allowsEviction: Bool = false) -> String? {
        if let failure = reconcile(archive: archive) { return failure }
        // Capacity must be checked before journalling. Initial answers may
        // retain ordinary archive retention; historical corrections may not.
        if let failure = archive.validateEdit(removing: removing, adding: adding,
                                               allowsEviction: allowsEviction) { return failure }
        let transaction = Transaction(id: UUID(), before: before, after: after,
            removed: removing, added: adding, fieldsBefore: document.fields,
            fieldsAfter: fields ?? document.fields)
        var prepared = document
        prepared.pending = transaction
        if let failure = save(prepared) { return failure }
        if let failure = archive.edit(removing: removing, adding: adding, allowsEviction: allowsEviction) {
            return failure
        }
        var committed = prepared
        committed.checkpoint = after
        committed.fields = transaction.fieldsAfter
        committed.pending = nil
        return save(committed)
    }

    private func save(_ next: Document) -> String? {
        if let failure = writeOverride?() { return failure }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            document = next
            return nil
        } catch { return "Could not save correction history: \(error.localizedDescription)" }
    }
}
