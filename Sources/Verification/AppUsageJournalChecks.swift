import Foundation

/// App-use history whose journal is there but cannot be read is left as it
/// is, so a later compaction cannot write a snapshot without those records
/// and then delete the journal that held them.
enum AppUsageJournalChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("App use whose journal cannot be read is shown read-only and both files are kept",
         unreadableJournalIsKept),
    ]

    private static func stretch(_ offset: TimeInterval, _ app: String) -> AppUsageSession {
        AppUsageSession(bundleID: "com.example.\(app.lowercased())", appName: app,
                        start: SelfTest.base.addingTimeInterval(offset),
                        end: SelfTest.base.addingTimeInterval(offset + 300), endReason: .appSwitch)
    }

    private static func unreadableJournalIsKept() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        let directory = SelfTest.scratchDirectory()
        let snapshot = directory.appendingPathComponent("app-usage.json")
        let journal = directory.appendingPathComponent("app-usage-journal.jsonl")
        func bytes() -> [Data?] { [snapshot, journal].map { try? Data(contentsOf: $0) } }
        func names(_ archive: AppUsageArchive) -> [String] { archive.sessions.map(\.appName).sorted() }

        // A relaunch folds Alpha into the snapshot; Beta then waits in the journal.
        AppUsageArchive(directory: directory, now: { SelfTest.base }).record(stretch(0, "Alpha"))
        let seeded = AppUsageArchive(directory: directory, now: { SelfTest.base })
        guard seeded.record(stretch(600, "Beta")), bytes().allSatisfy({ $0 != nil }) else {
            return ["could not seed a snapshot and a journal"]
        }
        let before = bytes()

        try? manager.setAttributes([.posixPermissions: 0o200], ofItemAtPath: journal.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: journal.path) }
        guard (try? Data(contentsOf: journal)) == nil else {
            return ["the journal stayed readable, so nothing was tested"]
        }
        let blind = AppUsageArchive(directory: directory, now: { SelfTest.base })
        let recorded = blind.record(stretch(1_200, "Gamma"))
        let checkpointed = blind.checkpoint(stretch(1_800, "Delta"))
        expect(blind.isReadOnly && !recorded && !checkpointed,
               "an unreadable journal should leave the archive read-only, got readOnly=\(blind.isReadOnly) recorded=\(recorded) checkpointed=\(checkpointed)",
               &problems)

        try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: journal.path)
        expect(bytes() == before, "the snapshot or the unreadable journal was changed", &problems)
        let restored = AppUsageArchive(directory: directory, now: { SelfTest.base })
        expect(names(restored) == ["Alpha", "Beta"],
               "once readable, a fresh load should read Alpha and Beta, got \(names(restored))", &problems)
        return problems
    }
}
