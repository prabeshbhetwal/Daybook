import Foundation

/// Power readings taken while no session is running.
///
/// A session's readings live on its record, so the story can say what the
/// Mac was on while the work happened. Between sessions there is no record,
/// and until now no reading either — the quiet blocks of a day had nothing
/// to say about power at all. These belong to no record and are kept by
/// date: thirty days, which outlasts anything the story will scroll back to
/// for a quiet block. `Core` only.
final class AmbientPowerLog {
    private struct Document: Codable {
        let version: Int
        var observations: [PowerObservation]
    }

    static let retention: TimeInterval = 30 * 24 * 3_600

    private let directory: URL
    private let fileURL: URL
    private let writeOverride: ((Data) -> String?)?
    private(set) var observations: [PowerObservation] = []
    /// The last write that did not reach disk. The reading is still held in
    /// memory and the next append tries again.
    private(set) var lastError: String?
    /// Why the file on disk could not be read. It may be the only copy of
    /// those readings, so while this is set nothing is written over it.
    private var loadFailure: String?

    init(directory: URL = SessionArchive.defaultDirectory,
         writeOverride: ((Data) -> String?)? = nil) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("ambient-power.json")
        self.writeOverride = writeOverride
        load()
        lastError = loadFailure
    }

    func observations(in interval: DateInterval) -> [PowerObservation] {
        observations.filter { $0.timestamp >= interval.start && $0.timestamp <= interval.end }
    }

    @discardableResult
    func append(_ observation: PowerObservation, now: Date) -> SessionMetadataWriteResult {
        guard !observations.contains(where: { $0.id == observation.id }) else { return .saved }
        observations.append(observation)
        observations.sort { $0.timestamp < $1.timestamp }
        let horizon = now.addingTimeInterval(-Self.retention)
        observations.removeAll { $0.timestamp < horizon }
        return commit()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
            guard document.version == 1 else {
                loadFailure = "Ambient power was written by a newer version and remains read-only."
                return
            }
            observations = document.observations.sorted { $0.timestamp < $1.timestamp }
        } catch {
            loadFailure = "Ambient power could not be read. The original file was preserved."
        }
    }

    private func commit() -> SessionMetadataWriteResult {
        if let loadFailure { return .failed(loadFailure) }
        do {
            let data = try JSONEncoder().encode(Document(version: 1, observations: observations))
            if let writeOverride {
                if let error = writeOverride(data) {
                    lastError = error
                    return .failed(error)
                }
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
            }
            lastError = nil
            return .saved
        } catch {
            let message = "Ambient power could not be saved: \(error.localizedDescription)"
            lastError = message
            return .failed(message)
        }
    }
}
