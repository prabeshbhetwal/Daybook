import Foundation

final class SessionMetadataArchive {
    private struct Document: Codable {
        let version: Int
        var entries: [SessionMetadata]
    }

    private let directory: URL
    private let fileURL: URL
    private let writeOverride: ((Data) -> String?)?
    private var cache: [UUID: SessionMetadata] = [:]
    private var loadFailure: String?
    private(set) var revision = 0

    init(directory: URL = SessionArchive.defaultDirectory,
         writeOverride: ((Data) -> String?)? = nil) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("session-metadata.json")
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
        var metadata = candidate[recordID] ?? SessionMetadata(recordID: recordID)
        if !metadata.power.contains(where: { $0.id == observation.id }) {
            metadata.power.append(observation)
            metadata.power.sort {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                let left = boundaryOrder($0.boundary), right = boundaryOrder($1.boundary)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
        }
        candidate[recordID] = metadata
        return commit(candidate)
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

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            if let document = try? JSONDecoder().decode(Document.self, from: data) {
                guard document.version == 1 else {
                    loadFailure = "Session metadata was written by a newer version and remains read-only."
                    return
                }
                cache = merged(document.entries)
                return
            }
            // Compatibility with an early unversioned sidecar prototype.
            let entries = try JSONDecoder().decode([SessionMetadata].self, from: data)
            cache = merged(entries)
        } catch {
            loadFailure = "Session metadata could not be read. The original file was preserved."
        }
    }

    private func merged(_ entries: [SessionMetadata]) -> [UUID: SessionMetadata] {
        var result: [UUID: SessionMetadata] = [:]
        for entry in entries {
            var value = result[entry.recordID] ?? SessionMetadata(recordID: entry.recordID)
            if let note = entry.note { value.note = note }
            for observation in entry.power where !value.power.contains(where: { $0.id == observation.id }) {
                value.power.append(observation)
            }
            value.power.sort {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                let left = boundaryOrder($0.boundary), right = boundaryOrder($1.boundary)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
            result[entry.recordID] = value
        }
        return result
    }

    private func commit(_ candidate: [UUID: SessionMetadata]) -> SessionMetadataWriteResult {
        if let loadFailure { return .failed(loadFailure) }
        guard candidate != cache else { return .saved }
        do {
            let document = Document(version: 1, entries: candidate.values.sorted {
                $0.recordID.uuidString < $1.recordID.uuidString
            })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            if let error = writeOverride?(data) { return .failed(error) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            cache = candidate
            revision &+= 1
            return .saved
        } catch {
            return .failed("Session metadata could not be saved: \(error.localizedDescription)")
        }
    }
}
