import Foundation

/// Every machine event Daybook has recorded, one JSON line each.
///
/// Append-only: nothing is updated or removed, so no line is ever rewritten
/// and a crash can at worst tear the one being written. A line this build
/// cannot read — that torn write, or a kind a newer build added — is skipped
/// and left in place for a build that can. Unlike the app-use journal there
/// is no snapshot to fold the lines into, so nothing here needs setting
/// aside. About 5 KB a day, kept for good like the rest of the history.
/// `Core` only.
final class MachineEventLog {
    static let fileName = "machine-events.jsonl"

    private let directory: URL
    private let fileURL: URL
    /// Oldest first, by `at`.
    private(set) var events: [MachineEvent] = []
    /// The file does not end its last line: a write was cut short. The next
    /// append starts a new line, so it is not joined to the torn bytes.
    private var lastLineOpen = false

    init(directory: URL = SessionArchive.defaultDirectory) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(Self.fileName)
        load()
    }

    /// The events that overlap `interval`, including one found afterwards
    /// whose window reaches into it.
    func events(in interval: DateInterval) -> [MachineEvent] {
        // ponytail: a linear scan, about 20,000 events a year; search the
        // sorted `at` instead if it ever shows in a profile.
        events.filter { $0.at < interval.end && $0.end >= interval.start }
    }

    @discardableResult
    func append(_ new: [MachineEvent]) -> Bool {
        guard !new.isEmpty else { return true }
        let encoder = JSONEncoder()
        var bytes = Data()
        if lastLineOpen { bytes.append(0x0A) }
        for event in new {
            guard let line = try? encoder.encode(event) else { continue }
            bytes.append(line)
            bytes.append(0x0A)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                    Diagnostics.log("failed to create the machine event log")
                    return false
                }
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
        } catch {
            // Part of the line may have reached the file; the next append
            // must not join it.
            lastLineOpen = true
            Diagnostics.log("failed to append machine events: \(error)")
            return false
        }
        lastLineOpen = false
        events.append(contentsOf: new)
        sortByTime()
        return true
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        events = data.split(separator: 0x0A, omittingEmptySubsequences: true).compactMap {
            try? decoder.decode(MachineEvent.self, from: Data($0))
        }
        lastLineOpen = data.last.map { $0 != 0x0A } ?? false
        sortByTime()
        events = Self.settlingUnnamedPowerOffs(events)
    }

    /// The first build wrote a power-off macOS announced without a reason as it
    /// was found, though the announcement alone proves nothing: System Settings
    /// quitting Daybook to apply a permission makes the same one. What came
    /// next settles it — a "Mac started up" before the next "Daybook opened"
    /// means the Mac went down; otherwise only Daybook quit. The file keeps
    /// what was written.
    static func settlingUnnamedPowerOffs(_ events: [MachineEvent]) -> [MachineEvent] {
        events.enumerated().map { index, event in
            guard event.kind == .powerOffUnknown else { return event }
            let next = events[(index + 1)...].first { $0.kind == .macStarted || $0.kind == .daybookStarted }
            return MachineEvent(kind: next?.kind == .macStarted ? .restartOrShutDown : .quit,
                                at: event.at, latest: event.latest, detail: event.detail)
        }
    }

    /// Found-afterwards events are written at the next launch, after newer
    /// ones; a stable sort keeps same-time events in the order they came.
    private func sortByTime() {
        events = events.enumerated()
            .sorted { $0.element.at == $1.element.at ? $0.offset < $1.offset : $0.element.at < $1.element.at }
            .map(\.element)
    }
}
