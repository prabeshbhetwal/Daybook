import Foundation

final class SessionMetadataArchive {
    private enum ValidationError: Error {
        case duplicateRecordID
        case conflictingObservationID
    }
    private struct Document: Codable {
        let version: Int
        var entries: [SessionMetadata]
    }
    /// Version 2 may have a journal beside it. A build that knows only version
    /// 1 cannot see the journal, so it must not write over the snapshot; it
    /// reads version 2 as newer and keeps the metadata read-only. A version 1
    /// file is rewritten as version 2 before the first journal line.
    private static let version = 2
    /// One change since the snapshot: every entry it touched, written whole,
    /// and every entry it removed. A change is one line, so a write cut short
    /// loses the whole change and never half of one, such as power moved out
    /// of one session but not yet into the next. A power reading, the common
    /// change, is just the reading, so a line does not grow with its session.
    private struct JournalLine: Codable {
        struct Reading: Codable {
            let recordID: UUID
            let observation: PowerObservation
        }
        var upserts: [SessionMetadata] = []
        var removals: [UUID] = []
        var reading: Reading?
    }
    /// A write the injected writer refused, with its message.
    private struct WriteRefused: Error { let message: String }
    private struct JournalUnreadable: Error {}

    /// Journal lines kept before the snapshot is rewritten. A power reading is
    /// one line, so this is about a week of readings.
    static let journalCompactionThreshold = 500

    private let directory: URL
    private let fileURL: URL
    private let journal: JournalFile
    private var journalEntries = 0
    /// The version of the snapshot on disk; nil when there is none.
    private var snapshotVersion: Int?
    private let writeOverride: ((Data) -> String?)?
    private var cache: [UUID: SessionMetadata] = [:]
    private var loadFailure: String?
    private(set) var revision = 0

    init(directory: URL = SessionArchive.defaultDirectory,
         writeOverride: ((Data) -> String?)? = nil) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("session-metadata.json")
        self.journal = JournalFile(url: directory.appendingPathComponent("session-metadata-journal.jsonl"))
        self.writeOverride = writeOverride
        load()
    }

    var allMetadata: [SessionMetadata] {
        cache.values.sorted { $0.recordID.uuidString < $1.recordID.uuidString }
    }

    func metadata(for recordID: UUID) -> SessionMetadata? { cache[recordID] }

    @discardableResult
    func saveNote(_ note: String?, for recordID: UUID) -> SessionMetadataWriteResult {
        let value = note.flatMap { text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        var candidate = cache
        var metadata = candidate[recordID] ?? SessionMetadata(recordID: recordID)
        metadata.note = value
        if metadata.note == nil && metadata.power.isEmpty { candidate.removeValue(forKey: recordID) }
        else { candidate[recordID] = metadata }
        return commit(candidate)
    }

    @discardableResult
    func appendPower(_ observation: PowerObservation,
                     for recordID: UUID) -> SessionMetadataWriteResult {
        var candidate = cache
        if candidate.contains(where: { owner, metadata in
            owner != recordID && metadata.power.contains(where: { $0.id == observation.id })
        }) {
            return .failed("That power observation already belongs to another session record.")
        }
        var metadata = candidate[recordID] ?? SessionMetadata(recordID: recordID)
        if let existing = metadata.power.first(where: { $0.id == observation.id }) {
            guard existing == observation else {
                return .failed("That power observation already exists on this session record with different content.")
            }
            return .saved
        }
        metadata.power.append(observation)
        metadata.power.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            let left = boundaryOrder($0.boundary), right = boundaryOrder($1.boundary)
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
        candidate[recordID] = metadata
        return commit(candidate, line: JournalLine(reading: .init(recordID: recordID, observation: observation)))
    }

    private func boundaryOrder(_ boundary: PowerCoverageBoundary?) -> Int {
        switch boundary {
        case .stretchStarted: return 0
        case .sourceChanged, nil: return 1
        case .coverageResumed: return 2
        case .stretchEnded: return 3
        }
    }

    @discardableResult
    func retain(recordIDs: Set<UUID>) -> SessionMetadataWriteResult {
        commit(cache.filter { recordIDs.contains($0.key) })
    }

    /// Moves observations that occurred after a successor's factual start in
    /// one atomic sidecar candidate. This is used when an Away answer closes the
    /// record that was still active when post-return notifications arrived.
    @discardableResult
    func reassignPower(from sourceID: UUID, to destinationID: UUID,
                       atOrAfter boundary: Date) -> SessionMetadataWriteResult {
        guard sourceID != destinationID else { return commit(cache) }
        var candidate = cache
        guard var source = candidate[sourceID] else { return commit(candidate) }
        let moving = source.power.filter { $0.timestamp >= boundary }
        guard !moving.isEmpty else { return commit(candidate) }
        source.power.removeAll { $0.timestamp >= boundary }
        var destination = candidate[destinationID] ?? SessionMetadata(recordID: destinationID)
        for observation in moving {
            if let existing = destination.power.first(where: { $0.id == observation.id }),
               existing != observation {
                return .failed("Session metadata contains conflicting power observations and remains unchanged.")
            }
            if !destination.power.contains(where: { $0.id == observation.id }) {
                destination.power.append(observation)
            }
        }
        destination.power.sort(by: observationsBefore)
        if source.note == nil && source.power.isEmpty { candidate.removeValue(forKey: sourceID) }
        else { candidate[sourceID] = source }
        candidate[destinationID] = destination
        return commit(candidate)
    }

    private func load() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                if let document = try? JSONDecoder().decode(Document.self, from: data) {
                    guard (1...Self.version).contains(document.version) else {
                        loadFailure = "Session metadata was written by a newer version and remains read-only."
                        return
                    }
                    cache = try validated(document.entries)
                    snapshotVersion = document.version
                } else {
                    // Compatibility with an early unversioned sidecar prototype.
                    cache = try validated(JSONDecoder().decode([SessionMetadata].self, from: data))
                    snapshotVersion = 0
                }
            }
            try replayJournal()
        } catch ValidationError.duplicateRecordID {
            cache = [:]
            loadFailure = "Session metadata contains duplicate record identities and remains read-only."
        } catch ValidationError.conflictingObservationID {
            cache = [:]
            loadFailure = "Session metadata contains conflicting power observations and remains read-only."
        } catch {
            loadFailure = "Session metadata could not be read. The original file was preserved."
        }
    }

    /// Applies the changes written since the snapshot. A launch does not fold
    /// them in: that rewrites the whole sidecar, about a second at five years
    /// of readings, while the journal it would clear replays in milliseconds.
    /// A last line that a cut-short write tore is cut off, losing only that
    /// change. Any other line that does not read, such as one a newer build
    /// wrote, leaves the metadata read-only with both files as they are, and
    /// shows only the changes before it: later ones may depend on it. So does
    /// a journal that is there but cannot be read.
    private func replayJournal() throws {
        guard let contents = journal.read() else {
            if FileManager.default.fileExists(atPath: journal.url.path) { throw JournalUnreadable() }
            return
        }
        let replay = journal.replay(JournalLine.self, from: contents)
        var entries = cache
        for line in replay.changes.prefix((replay.unreadableLine ?? Int.max) - 1) {
            for entry in line.upserts { entries[entry.recordID] = entry }
            for recordID in line.removals { entries.removeValue(forKey: recordID) }
            if let reading = line.reading {
                entries[reading.recordID, default: SessionMetadata(recordID: reading.recordID)]
                    .power.append(reading.observation)
            }
        }
        if !replay.changes.isEmpty { cache = try validated(Array(entries.values)) }
        journalEntries = contents.lines.count
        if replay.unreadableLine != nil { throw JournalUnreadable() }
        // The next append must start on a line of its own.
        guard contents.lastWriteCut, FileManager.default.fileExists(atPath: journal.url.path) else { return }
        let repaired = replay.skippedTornLine
            ? journal.dropTornLine(from: contents.data) : journal.endLastLine()
        if !repaired { throw JournalUnreadable() }
    }

    private func validated(_ entries: [SessionMetadata]) throws -> [UUID: SessionMetadata] {
        var result: [UUID: SessionMetadata] = [:]
        var observationOwners: [UUID: (recordID: UUID, observation: PowerObservation)] = [:]
        for entry in entries {
            guard result[entry.recordID] == nil else { throw ValidationError.duplicateRecordID }
            var observations: [UUID: PowerObservation] = [:]
            for observation in entry.power {
                if let owner = observationOwners[observation.id] {
                    if owner.recordID != entry.recordID || owner.observation != observation {
                        throw ValidationError.conflictingObservationID
                    }
                } else {
                    observationOwners[observation.id] = (entry.recordID, observation)
                }
                if let existing = observations[observation.id], existing != observation {
                    throw ValidationError.conflictingObservationID
                }
                observations[observation.id] = observation
            }
            var value = entry
            value.power = observations.values.sorted(by: observationsBefore)
            result[entry.recordID] = value
        }
        return result
    }

    private func observationsBefore(_ left: PowerObservation,
                                    _ right: PowerObservation) -> Bool {
        if left.timestamp != right.timestamp { return left.timestamp < right.timestamp }
        let leftBoundary = boundaryOrder(left.boundary), rightBoundary = boundaryOrder(right.boundary)
        return leftBoundary == rightBoundary
            ? left.id.uuidString < right.id.uuidString : leftBoundary < rightBoundary
    }

    /// Publishes a change only once it is durable. With a snapshot on disk, a
    /// change is one journal line holding just the entries it touched: every
    /// power reading used to rewrite the whole sidecar, a cost that grew with
    /// history to about 90 ms and 6 MB a reading after a year. The snapshot is
    /// written instead when there is none yet or it is an older version, and
    /// also each time the journal grows by its limit, after the line, so a
    /// snapshot that fails loses nothing and is not retried on every change.
    private func commit(_ candidate: [UUID: SessionMetadata],
                        line: JournalLine? = nil) -> SessionMetadataWriteResult {
        if let loadFailure { return .failed(loadFailure) }
        guard candidate != cache else { return .saved }
        do {
            if snapshotVersion == Self.version, FileManager.default.fileExists(atPath: fileURL.path) {
                try appendToJournal(line ?? JournalLine(
                    upserts: candidate.values.filter { cache[$0.recordID] != $0 }
                        .sorted { $0.recordID.uuidString < $1.recordID.uuidString },
                    removals: cache.keys.filter { candidate[$0] == nil }
                        .sorted { $0.uuidString < $1.uuidString }))
            } else {
                try writeSnapshot(candidate)
            }
        } catch let refused as WriteRefused {
            return .failed(refused.message)
        } catch {
            return .failed("Session metadata could not be saved: \(error.localizedDescription)")
        }
        cache = candidate
        revision &+= 1
        if journalEntries > 0, journalEntries % Self.journalCompactionThreshold == 0 {
            do {
                try writeSnapshot(cache)
            } catch {
                Diagnostics.log("session metadata snapshot not written, the journal keeps every change: \(error)")
            }
        }
        return .saved
    }

    private func appendToJournal(_ line: JournalLine) throws {
        let data = try JSONEncoder().encode(line)
        if let message = writeOverride?(data) { throw WriteRefused(message: message) }
        try journal.append(data)
        journalEntries += 1
    }

    /// Writes every entry as the snapshot, then removes the journal it
    /// absorbed. If removing fails, replaying those lines over the snapshot
    /// changes nothing: whole entries are set again in order, and a reading
    /// the snapshot already holds loads as the same reading.
    private func writeSnapshot(_ entries: [UUID: SessionMetadata]) throws {
        let document = Document(version: Self.version, entries: entries.values.sorted {
            $0.recordID.uuidString < $1.recordID.uuidString
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        if let message = writeOverride?(data) { throw WriteRefused(message: message) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        snapshotVersion = Self.version
        if journal.remove() { journalEntries = 0 }
    }
}
