import Foundation

/// Session history is kept whole, and a copy can be put somewhere else on
/// request: iCloud Drive in the app, a scratch folder here.
enum HistoryKeepingChecks {
    static let tests: [(String, () -> [String])] = [
        ("Session history keeps every record; nothing old is retired", historyIsUncapped),
        ("A backup copies the data folder and the app's preferences into a new dated folder", backupCopiesEverything),
        ("A second backup in the same minute never replaces the first", backupsNeverOverwrite),
        ("Backing up with no iCloud Drive on this Mac says so and writes nothing", backupNeedsDestination),
        ("Settings' backup button saves the app's own preferences and reports where", settingsBackup)
    ]

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private static func scratch() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-history-keeping-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func record(_ index: Int) -> SessionRecord {
        let start = base.addingTimeInterval(Double(index) * 3_600)
        return SessionRecord(name: "Session \(index)", workType: .deepWork, start: start,
                             end: start.addingTimeInterval(1_500), workSeconds: 1_500)
    }

    private static func historyIsUncapped() -> [String] {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The old limit's worth of records, written as a file, then one more
        // through the archive's own path.
        let existing = (0..<5_000).map(record)
        try? JSONEncoder().encode(existing).write(to: directory.appendingPathComponent("sessions.json"))
        let archive = SessionArchive(directory: directory, now: { base })
        let failure = archive.append(record(5_000))
        let reloaded = SessionArchive(directory: directory, now: { base })
        guard failure == nil else { return ["the 5,001st record was refused: \(failure ?? "")"] }
        return reloaded.records.count == 5_001 && reloaded.records.first?.id == existing.first?.id ? []
            : ["expected all 5,001 records with the oldest kept, got \(reloaded.records.count)"]
    }

    private static func backupCopiesEverything() -> [String] {
        var failures: [String] = []
        let data = scratch(), cloud = scratch()
        defer { try? FileManager.default.removeItem(at: data); try? FileManager.default.removeItem(at: cloud) }
        let sessions = Data("[]".utf8)
        try? sessions.write(to: data.appendingPathComponent("sessions.json"))
        let preferences: [String: Any] = ["fc.activityRules": Data("rules".utf8), "fc.dailyGoal": 7_200]

        do {
            let folder = try DataBackup.make(from: data, preferences: preferences, into: cloud, at: base)
            if folder.deletingLastPathComponent().lastPathComponent != DataBackup.folderName {
                failures.append("the backup is not inside \(DataBackup.folderName): \(folder.path)")
            }
            if (try? Data(contentsOf: folder.appendingPathComponent("sessions.json"))) != sessions {
                failures.append("the data folder's files were not copied")
            }
            let saved = NSDictionary(contentsOf: folder.appendingPathComponent(DataBackup.preferencesFile))
            if saved?["fc.dailyGoal"] as? Int != 7_200 || saved?["fc.activityRules"] as? Data != Data("rules".utf8) {
                failures.append("the preferences were not written beside the data")
            }
        } catch {
            failures.append("the backup failed: \(error.localizedDescription)")
        }
        return failures
    }

    private static func backupsNeverOverwrite() -> [String] {
        let data = scratch(), cloud = scratch()
        defer { try? FileManager.default.removeItem(at: data); try? FileManager.default.removeItem(at: cloud) }
        try? Data("first".utf8).write(to: data.appendingPathComponent("sessions.json"))
        guard let first = try? DataBackup.make(from: data, preferences: nil, into: cloud, at: base) else {
            return ["the first backup failed"]
        }
        try? Data("second".utf8).write(to: data.appendingPathComponent("sessions.json"))
        guard let second = try? DataBackup.make(from: data, preferences: nil, into: cloud, at: base) else {
            return ["the second backup failed"]
        }
        let firstBytes = try? Data(contentsOf: first.appendingPathComponent("sessions.json"))
        return first != second && firstBytes == Data("first".utf8) ? []
            : ["a same-minute backup replaced the one before it"]
    }

    private static func backupNeedsDestination() -> [String] {
        let data = scratch()
        defer { try? FileManager.default.removeItem(at: data) }
        let missing = data.appendingPathComponent("no-icloud-drive-here", isDirectory: true)
        do {
            _ = try DataBackup.make(from: data, preferences: nil, into: missing, at: base)
            return ["a backup into a missing iCloud Drive claimed success"]
        } catch {
            return FileManager.default.fileExists(atPath: missing.path)
                ? ["a failed backup created the missing destination"] : []
        }
    }

    private static func settingsBackup() -> [String] {
        var failures: [String] = []
        let data = scratch(), cloud = scratch()
        let suite = "fc.backup.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated preferences"] }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: data)
            try? FileManager.default.removeItem(at: cloud)
        }
        let store = PersistenceStore(defaults: defaults)
        store.dailyGoal = 7_200
        let model = SettingsModel(store: store, isTrackingEnabled: false, onChange: {},
                                  onTrackingChanged: { _ in }, dataDirectory: data, backupRoot: cloud)
        model.backUpToICloudDrive(at: base)
        let status = model.backupStatus ?? ""
        let folder = cloud.appendingPathComponent(DataBackup.folderName)
        let made = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let name = made.first, status.contains(name) else {
            return ["the backup was not made or not reported: \(status)"]
        }
        let saved = NSDictionary(contentsOf: folder.appendingPathComponent(name)
            .appendingPathComponent(DataBackup.preferencesFile))
        if saved?["fc.dailyGoal"] as? Double != 7_200 { failures.append("the daily goal preference was not saved") }
        if saved?.allKeys.contains(where: { !(($0 as? String)?.hasPrefix("fc.") ?? false) }) == true {
            failures.append("preferences from outside the app were saved too")
        }
        return failures
    }
}
