import Foundation

/// App-use history is written as a snapshot plus a journal, never capped, and
/// brought back from set-aside files once they read again.
enum UsagePersistenceChecks {
    static let tests: [(String, () -> [String])] = [
        ("A checkpoint appends to the journal instead of rewriting the history", journalAppends),
        ("The journal survives a relaunch, a torn last line and compaction", journalReplay),
        ("History set aside as unreadable is merged back once it reads", setAsideRecovery)
    ]

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private static func scratch() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-usage-journal-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func stretch(_ offset: TimeInterval, _ app: String = "Editor",
                                id: UUID = UUID(), reason: UsageEndReason = .appSwitch) -> AppUsageSession {
        AppUsageSession(id: id, bundleID: "com.example.\(app.lowercased())", appName: app,
                        start: base.addingTimeInterval(offset),
                        end: base.addingTimeInterval(offset + 300), endReason: reason)
    }

    private static func journalAppends() -> [String] {
        var failures: [String] = []
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent("app-usage.json")
        let journal = directory.appendingPathComponent("app-usage-journal.jsonl")

        try? JSONEncoder().encode(Envelope(metadata: AppUsageMetadata(accurateFrom: base),
                                           sessions: [stretch(-3_600, "Earlier")]))
            .write(to: snapshot)
        let before = try? Data(contentsOf: snapshot)
        let archive = AppUsageArchive(directory: directory, now: { base })
        archive.record(stretch(0))

        let live = UUID()
        for minute in 1...30 {
            var open = stretch(600, "Browser", id: live, reason: .stillOpen)
            open.end = base.addingTimeInterval(600 + Double(minute) * 60)
            if !archive.checkpoint(open) { failures.append("checkpoint \(minute) was not durable") }
        }
        if (try? Data(contentsOf: snapshot)) != before {
            failures.append("thirty heartbeat checkpoints rewrote the history snapshot")
        }
        let lines = (try? String(contentsOf: journal, encoding: .utf8))?
            .split(separator: "\n").count ?? 0
        if lines != 31 {
            failures.append("expected one journal line per change (31), got \(lines)")
        }
        if before == nil || archive.sessions.count != 3 || archive.revision != 31 {
            failures.append("the in-memory view must publish every durable change")
        }
        return failures
    }

    private static func journalReplay() -> [String] {
        var failures: [String] = []
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("app-usage-journal.jsonl")

        let first = AppUsageArchive(directory: directory, now: { base })
        let kept = stretch(0)
        let dropped = stretch(1_000, "Notes")
        first.record(kept)
        first.record(dropped)
        var shortened = dropped
        shortened.end = shortened.start.addingTimeInterval(2)
        first.checkpoint(shortened)

        // A crash mid-append leaves a partial line; it must not cost the rest.
        if let handle = try? FileHandle(forWritingTo: journal) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("{\"upsert\":{\"_0\":{\"id\"".utf8))
            try? handle.close()
        }

        let second = AppUsageArchive(directory: directory, now: { base })
        if second.sessions != [kept] {
            failures.append("relaunch did not replay upsert and remove exactly, got \(second.sessions.count)")
        }
        if FileManager.default.fileExists(atPath: journal.path) {
            failures.append("a launch that replayed changes must compact the journal away")
        }

        let third = AppUsageArchive(directory: directory, now: { base })
        let threshold = AppUsageConstants.journalCompactionThreshold
        for index in 0..<threshold {
            third.record(stretch(Double(10_000 + index * 400), "App\(index)"))
        }
        let remaining = (try? String(contentsOf: journal, encoding: .utf8))?
            .split(separator: "\n").count ?? 0
        if remaining >= threshold {
            failures.append("the journal passed \(threshold) lines without compacting (\(remaining))")
        }
        let fourth = AppUsageArchive(directory: directory, now: { base })
        if fourth.sessions.count != threshold + 1 {
            failures.append("compaction lost records: expected \(threshold + 1), got \(fourth.sessions.count)")
        }
        return failures
    }

    private struct Envelope: Codable {
        let metadata: AppUsageMetadata
        let sessions: [AppUsageSession]
    }

    private static func setAsideRecovery() -> [String] {
        var failures: [String] = []
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let epoch = base.addingTimeInterval(86_400)
        let current = stretch(90_000)
        let shared = stretch(3_600, "Shared")
        let august = [stretch(0, "Old"), shared]
        let encoder = JSONEncoder()
        try? encoder.encode(Envelope(metadata: AppUsageMetadata(accurateFrom: epoch),
                                     sessions: [shared, current]))
            .write(to: directory.appendingPathComponent("app-usage.json"))
        try? encoder.encode(Envelope(metadata: AppUsageMetadata(accurateFrom: base),
                                     sessions: august))
            .write(to: directory.appendingPathComponent("app-usage-corrupt-1788016625.json"))
        try? Data("not usage".utf8)
            .write(to: directory.appendingPathComponent("app-usage-corrupt-1788091684.json"))

        let archive = AppUsageArchive(directory: directory, now: { epoch })
        let ids = archive.sessions.map(\.id)
        if Set(ids) != Set([august[0].id, shared.id, current.id]) || ids.count != 3 {
            failures.append("recovery must merge set-aside records once, by id; got \(ids.count)")
        }
        if archive.sessions.first?.id != august[0].id {
            failures.append("recovered history must sit in time order")
        }
        if archive.metadata.accurateFrom != epoch {
            failures.append("recovery must not move the accuracy epoch")
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        if !names.contains("app-usage-recovered-1788016625.json")
            || names.contains("app-usage-corrupt-1788016625.json") {
            failures.append("a recovered file must be renamed, not deleted or reprocessed")
        }
        if !names.contains("app-usage-corrupt-1788091684.json") {
            failures.append("a file that still cannot be read must stay where it is")
        }
        let reopened = AppUsageArchive(directory: directory, now: { epoch })
        if reopened.sessions.count != 3 {
            failures.append("recovered records must be durable, got \(reopened.sessions.count)")
        }
        return failures
    }
}
