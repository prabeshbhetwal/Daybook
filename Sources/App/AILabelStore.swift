import Foundation

/// `ai-labels.json` beside `sessions.json` (Phase C, rulings C7, C10 and C19): the labels an AI proposed that
/// the person has not kept, what the model said for each kind of session, the names never proposed again and
/// the last comparisons with the person's own choices. The person's own labels and choices are in it, so the
/// data folder's backups carry it. A file that cannot be read is set aside as the session archive sets its own
/// aside; one entry that cannot be read costs only itself (`AILabelBook`).
final class AILabelStore {
    static let fileName = "ai-labels.json"
    /// Posted after a save, so an open Settings window redraws its tally line.
    static let didSave = Notification.Name("AILabelStore.didSave")

    private let url: URL
    private(set) var book = AILabelBook()
    /// Why nothing is written. While set, the file on disk may be the only copy of what it holds.
    private(set) var failure: String?

    init(directory: URL, now: Date = Date()) {
        url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            book = try JSONDecoder().decode(AILabelBook.self, from: Data(contentsOf: url))
        } catch {
            // Reads as empty; the next save starts a fresh file. Read-only only when the bytes cannot be moved.
            if UnreadableFile.setAside(url, prefix: "ai-labels-corrupt-", pathExtension: "json", at: now) == nil {
                failure = "Daybook's AI category labels couldn't be read. \(error.localizedDescription.endingInFullStop) Their file was kept. Reopen Daybook to try again."
            }
            Diagnostics.log("ai-labels.json unreadable: \(error)")
        }
    }

    /// Writes `next` atomically, with the labels that lapsed by `moment` archived; it becomes `book` only once it
    /// is on disk. Nil when saved, else why it was not.
    @discardableResult
    func save(_ next: AILabelBook, at moment: Date) -> String? {
        if let failure { return failure }
        var written = next
        written.archiveStale(now: moment)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(written).write(to: url, options: .atomic)
            book = written
            NotificationCenter.default.post(name: Self.didSave, object: self)
            return nil
        } catch {
            return "Daybook couldn't save its AI category labels. \(error.localizedDescription.endingInFullStop) Check free space and folder access."
        }
    }
}
