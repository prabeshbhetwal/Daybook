import Foundation

/// An append-only file of JSON lines kept beside a snapshot, one change per
/// line, until a fresh snapshot absorbs it and it is removed.
///
/// An archive whose changes are small next to its history uses one, so a
/// change costs a line rather than a rewrite of everything. Each archive
/// decides what a line holds and what an unreadable one means; this type owns
/// only the file: appending, reading back, and repairing the end that a
/// cut-short write left.
struct JournalFile {
    let url: URL

    /// The journal as the last write left it.
    struct Contents {
        let data: Data
        /// Every non-empty line, including a last one a cut-short write tore.
        let lines: [Data]
        /// Every append ends its line, so a journal that does not end in a
        /// newline was cut short by its last write.
        let lastWriteCut: Bool
    }

    /// The lines of a journal, decoded in order.
    struct Replay<Change> {
        var changes: [Change] = []
        /// The last line did not read and the last write was cut short, so it
        /// alone may be torn. It is left out.
        var skippedTornLine = false
        /// The first complete line that did not read, counted from 1.
        var unreadableLine: Int?
    }

    /// Nil when there is no journal, or it cannot be read.
    func read() -> Contents? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return Contents(data: data,
                        lines: data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) },
                        lastWriteCut: data.last.map { $0 != 0x0A } ?? false)
    }

    /// Only the last line can be torn, and only when the last write was cut
    /// short. Any other line that does not read, such as one a newer build
    /// wrote, is noted and passed over, so the lines that do read still apply.
    func replay<Change: Decodable>(_ type: Change.Type, from contents: Contents) -> Replay<Change> {
        var result = Replay<Change>()
        for (offset, line) in contents.lines.enumerated() {
            guard let change = try? JSONDecoder().decode(Change.self, from: line) else {
                if offset == contents.lines.count - 1, contents.lastWriteCut {
                    result.skippedTornLine = true
                    break
                }
                result.unreadableLine = result.unreadableLine ?? offset + 1
                continue
            }
            result.changes.append(change)
        }
        return result
    }

    /// Appends one line and ends it, so the next append starts a line of its own.
    ///
    /// A write that fails part-way, on a full disk say, leaves nothing behind:
    /// its change is reported as not saved, and the next line would otherwise
    /// join the torn bytes and be unreadable too.
    func append(_ line: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        } else {
            dropTailOfFailedWrite()
        }
        var ended = line
        ended.append(0x0A)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        do {
            try handle.write(contentsOf: ended)
        } catch {
            try? handle.truncate(atOffset: end)
            throw error
        }
    }

    /// Cuts a line left by a failed write whose truncation also failed. In a
    /// running process an unended last line can only be that: a launch has
    /// already ended or cut the one it found.
    private func dropTailOfFailedWrite() {
        guard let reader = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? reader.close() }
        guard let end = try? reader.seekToEnd(), end > 0,
              (try? reader.seek(toOffset: end - 1)) != nil,
              let last = try? reader.read(upToCount: 1), last != Data([0x0A]),
              let data = try? Data(contentsOf: url) else { return }
        _ = dropTornLine(from: data)
    }

    /// Writes the newline a cut-short write left off a line that reads.
    func endLastLine() -> Bool {
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0x0A]))
            return true
        } catch {
            return false
        }
    }

    /// Truncates the journal to just before its last line.
    func dropTornLine(from data: Data) -> Bool {
        var end = data.endIndex
        while end > data.startIndex, data[end - 1] == 0x0A { end -= 1 }
        let keep = data[..<end].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(keep - data.startIndex))
            return true
        } catch {
            return false
        }
    }

    /// Removes the journal once a snapshot holds it. True when none is left.
    func remove() -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
            || !FileManager.default.fileExists(atPath: url.path)
    }
}
