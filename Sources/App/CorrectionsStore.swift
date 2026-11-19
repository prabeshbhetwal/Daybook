import Foundation

/// `corrections.json` beside `sessions.json`: how the person files a kind of session, kept so it
/// can be offered back. Those are the person's own choices, so the data folder's backups carry
/// the file like the sessions. A file that cannot be read is set aside as the session archive
/// sets its own aside, and one a newer Daybook wrote is left exactly as it is.
final class CorrectionsStore {
    static let fileName = "corrections.json"

    private let url: URL
    private(set) var corrections = CategoryCorrections()
    /// Why nothing is written. While set, the file on disk may be the only copy of what it holds.
    private(set) var failure: String?

    private struct Stamp: Decodable { let version: Int? }

    init(directory: URL, now: Date = Date()) {
        url = directory.appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            if let version = (try? JSONDecoder().decode(Stamp.self, from: data))?.version, version != 1 {
                failure = "Remembered category choices were written by a newer version of Daybook. Their file was kept. Update Daybook to use them."
                return
            }
            corrections = try JSONDecoder().decode(CategoryCorrections.self, from: data)
        } catch {
            // Reads as empty; the next choice starts a fresh file. Read-only only when the bytes cannot be moved.
            if UnreadableFile.setAside(url, prefix: "corrections-corrupt-", pathExtension: "json", at: now) == nil {
                failure = "Remembered category choices couldn't be read. \(error.localizedDescription.endingInFullStop) Their file was kept. Reopen Daybook to try again."
            }
            Diagnostics.log("corrections.json unreadable: \(error)")
        }
    }

    func suggestion(for fingerprint: ActivityFingerprint, now: Date) -> String? {
        corrections.suggestion(for: fingerprint, now: now)
    }

    /// Remembers a choice. Nil when saved, else why it was not.
    @discardableResult
    func record(fingerprint: ActivityFingerprint, chosen: String, vetoed: String?, at moment: Date) -> String? {
        var next = corrections
        next.record(fingerprint: fingerprint, chosen: chosen, vetoed: vetoed, at: moment)
        return save(next, at: moment)
    }

    /// Takes back what filings added, as Undo of the change that made them. `standing`: the filings of the
    /// corrections made before it that nobody has undone, oldest first (see `CategoryCorrections.forget`).
    @discardableResult
    func forget(_ filings: [RememberedFiling], standing: [RememberedFiling], at moment: Date) -> String? {
        var next = corrections
        for filing in filings.reversed() { next.forget(filing, standing: standing) }
        return next == corrections ? nil : save(next, at: moment)
    }

    /// Writes `next` and prunes what lapsed in the same write. Nil when saved, else why it was not.
    /// Nothing here logs: the caller does, once, with the reason.
    func save(_ next: CategoryCorrections, at moment: Date) -> String? {
        if let failure { return failure }
        var written = next
        written.pruned(now: moment)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(written).write(to: url, options: .atomic)
            corrections = written
            return nil
        } catch {
            return "Daybook couldn't remember how you filed that session. \(error.localizedDescription.endingInFullStop) Check free space and folder access."
        }
    }
}
