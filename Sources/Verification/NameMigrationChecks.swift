import Foundation

/// The first launch after the rename carries history and preferences across
/// without losing, hiding or overwriting anything, whatever state the folders
/// are in.
enum NameMigrationChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The old history folder takes the new name on first launch", oldFolderMoves),
        ("An empty new folder gives way to the old history", emptyNewFolderGivesWay),
        ("When both folders hold history, neither moves", bothHoldHistory),
        ("A stray file in the new folder keeps the old history in use", strayFileKeepsOldInUse),
        ("A history folder that cannot be renamed is used where it is", unmovableFolderStaysInUse),
        ("An empty new folder that cannot be cleared keeps the old history in use", unclearableNewFolder),
        ("Under one name for both, launch changes nothing and logs nothing", sameNameIsNoOp),
        ("Old preferences are carried once, kept where they were, and never overwrite new ones",
         preferencesCarriedOnce),
        ("Backups made before the rename join the new backups folder", oldBackupsJoinNewFolder),
    ]

    private static let history = Data("[{\"name\":\"Parser refactor\"}]".utf8)

    /// A scratch Application Support with the old folder's place and a new
    /// name that differs from it, as after the rename.
    private static func folders() -> (support: URL, legacy: URL, named: URL) {
        let support = SelfTest.scratchDirectory()
        return (support, support.appendingPathComponent(NameMigration.legacyFolderName, isDirectory: true),
                support.appendingPathComponent("Renamed", isDirectory: true))
    }

    private static func write(_ data: Data, _ name: String, in folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(name))
    }

    private static func contents(_ name: String, in folder: URL) -> Data? {
        try? Data(contentsOf: folder.appendingPathComponent(name))
    }

    private static func oldFolderMoves() -> [String] {
        var problems: [String] = []
        let (support, legacy, named) = folders()
        write(history, "sessions.json", in: legacy)
        let kept = NameMigration.carryFolders(support: support, named: named, log: { _ in })
        expect(kept == nil, "the new folder should be in use, kept \(kept?.lastPathComponent ?? "")", &problems)
        expect(contents("sessions.json", in: named) == history,
               "the history should arrive byte for byte in the new folder", &problems)
        expect(!FileManager.default.fileExists(atPath: legacy.path),
               "the old folder should be gone after the move", &problems)
        return problems
    }

    private static func emptyNewFolderGivesWay() -> [String] {
        var problems: [String] = []
        let (support, legacy, named) = folders()
        write(history, "sessions.json", in: legacy)
        write(Data(), ".DS_Store", in: named)
        let kept = NameMigration.carryFolders(support: support, named: named, log: { _ in })
        expect(kept == nil, "the new folder should be in use, kept \(kept?.lastPathComponent ?? "")", &problems)
        expect(contents("sessions.json", in: named) == history,
               "the old history should replace an empty new folder", &problems)
        return problems
    }

    private static func bothHoldHistory() -> [String] {
        var problems: [String] = []
        let (support, legacy, named) = folders()
        let newer = Data("[]".utf8)
        write(history, "sessions.json", in: legacy)
        write(newer, "app-usage.json", in: named)
        var logged: [String] = []
        let kept = NameMigration.carryFolders(support: support, named: named, log: { logged.append($0) })
        expect(kept == nil, "the new folder should stay in use, kept \(kept?.lastPathComponent ?? "")", &problems)
        expect(contents("app-usage.json", in: named) == newer, "the new folder's files should be untouched", &problems)
        expect(contents("sessions.json", in: legacy) == history, "the old folder's files should be untouched", &problems)
        expect(logged.count == 1, "the conflict should be logged once, got \(logged.count)", &problems)
        return problems
    }

    private static func strayFileKeepsOldInUse() -> [String] {
        var problems: [String] = []
        let (support, legacy, named) = folders()
        write(history, "sessions.json", in: legacy)
        write(Data("half-written".utf8), ".sessions.json.sb-1234", in: named)
        let kept = NameMigration.carryFolders(support: support, named: named, log: { _ in })
        expect(kept == legacy, "the old folder should stay in use, kept \(kept?.lastPathComponent ?? "nothing")",
               &problems)
        expect(contents("sessions.json", in: legacy) == history, "the old history should be intact", &problems)
        expect(contents(".sessions.json.sb-1234", in: named) != nil, "the stray file should be left alone", &problems)
        return problems
    }

    private static func unmovableFolderStaysInUse() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        let (support, legacy, named) = folders()
        write(history, "sessions.json", in: legacy)
        try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: support.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support.path) }
        var logged: [String] = []
        let kept = NameMigration.carryFolders(support: support, named: named, log: { logged.append($0) })
        expect(kept == legacy, "the old folder should stay in use, kept \(kept?.lastPathComponent ?? "nothing")",
               &problems)
        expect(contents("sessions.json", in: legacy) == history, "the old history should be intact", &problems)
        expect(!logged.isEmpty, "the failed rename should be logged", &problems)
        return problems
    }

    private static func unclearableNewFolder() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        let (support, legacy, named) = folders()
        write(history, "sessions.json", in: legacy)
        write(Data(), ".DS_Store", in: named)
        let locked = named.appendingPathComponent(".DS_Store").path
        try? manager.setAttributes([.immutable: true], ofItemAtPath: locked)
        defer { try? manager.setAttributes([.immutable: false], ofItemAtPath: locked) }
        let kept = NameMigration.carryFolders(support: support, named: named, log: { _ in })
        expect(kept == legacy, "the old folder should stay in use, kept \(kept?.lastPathComponent ?? "nothing")",
               &problems)
        expect(contents("sessions.json", in: legacy) == history, "the old history should be intact", &problems)
        return problems
    }

    private static func sameNameIsNoOp() -> [String] {
        var problems: [String] = []
        let (support, legacy, _) = folders()
        write(history, "sessions.json", in: legacy)
        var logged: [String] = []
        let kept = NameMigration.carryFolders(support: support, named: legacy, log: { logged.append($0) })
        expect(kept == nil, "the folder should be used as it is, kept \(kept?.lastPathComponent ?? "")", &problems)
        expect(contents("sessions.json", in: legacy) == history, "the history should be untouched", &problems)
        expect(logged.isEmpty, "nothing should be logged, got \(logged)", &problems)

        let file = folders()
        write(history, "unrelated", in: file.support)
        try? FileManager.default.moveItem(at: file.support.appendingPathComponent("unrelated"), to: file.legacy)
        let fromFile = NameMigration.carryFolders(support: file.support, named: file.named, log: { _ in })
        expect(fromFile == nil && !FileManager.default.fileExists(atPath: file.named.path),
               "a file in the old folder's place should be ignored, not moved", &problems)
        return problems
    }

    private static func preferencesCarriedOnce() -> [String] {
        var problems: [String] = []
        let legacyDomain = "fc-selftest-name-legacy-\(UUID().uuidString)"
        let domain = "fc-selftest-name-current-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: domain) else { return ["no isolated defaults suite"] }
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: domain)
        }
        let rules = Data("rules".utf8)
        defaults.setPersistentDomain(["fc.dailyGoal": 7_200, "fc.activityRules": rules,
                                      "fc.showsMenuBarIcon": true], forName: legacyDomain)
        defaults.setPersistentDomain(["fc.showsMenuBarIcon": false], forName: domain)

        NameMigration.carryPreferences(from: legacyDomain, to: domain, in: defaults)
        var carried = defaults.persistentDomain(forName: domain) ?? [:]
        expect(carried["fc.dailyGoal"] as? Int == 7_200 && carried["fc.activityRules"] as? Data == rules,
               "the old preferences should be carried, got \(carried.keys.sorted())", &problems)
        expect(carried["fc.showsMenuBarIcon"] as? Bool == false,
               "a preference the new domain already had should be kept", &problems)
        expect((defaults.persistentDomain(forName: legacyDomain) ?? [:]).count == 3,
               "the old preferences should be left where they were", &problems)

        carried["fc.dailyGoal"] = 3_600
        carried["fc.activityRules"] = nil
        defaults.setPersistentDomain(carried, forName: domain)
        NameMigration.carryPreferences(from: legacyDomain, to: domain, in: defaults)
        let later = defaults.persistentDomain(forName: domain) ?? [:]
        expect(later["fc.dailyGoal"] as? Int == 3_600, "a later carry should not overwrite a new setting", &problems)
        expect(later["fc.activityRules"] == nil, "a later carry should not bring back a removed setting", &problems)
        return problems
    }

    private static func oldBackupsJoinNewFolder() -> [String] {
        var problems: [String] = []
        let data = SelfTest.scratchDirectory(), cloud = SelfTest.scratchDirectory()
        write(history, "sessions.json", in: data)
        let earlier = cloud.appendingPathComponent(NameMigration.legacyBackupFolderName, isDirectory: true)
            .appendingPathComponent("2026-09-01 0900", isDirectory: true)
        write(history, "sessions.json", in: earlier)
        let made = try? DataBackup.make(from: data, preferences: nil, into: cloud, at: Date())
        let folder = cloud.appendingPathComponent(DataBackup.folderName, isDirectory: true)
        expect(made?.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
               "the new backup should be in \(DataBackup.folderName), got \(made?.path ?? "none")", &problems)
        expect(contents("sessions.json", in: folder.appendingPathComponent("2026-09-01 0900")) == history,
               "the earlier backup should now be in \(DataBackup.folderName)", &problems)
        return problems
    }
}
