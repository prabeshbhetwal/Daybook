import Foundation

/// Automatic backups: when one comes due, how long automatic ones are kept,
/// that only expired automatic ones reach the Trash, and that Settings'
/// schedule, folder and keeping period are kept and acted on.
enum BackupScheduleChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A backup comes due on its schedule, early by at most one check", dueOnSchedule),
        ("Automatic backups are kept for the chosen calendar period", retentionCutoffs),
        ("Only expired automatic backups go to the Trash, and the newest always stays", pruneKeepsOthers),
        ("The schedule backs up when due, keeps its settings and records what failed", settingsSchedule),
        ("A copy that fails part-way leaves no backup, partial or otherwise", partialCopyLeavesNothing),
        ("An update starts backups off and offers them once; a new install backs up daily", upgradeStartsOff),
    ]

    /// Appended at the end of the registry, after the suites that followed this one.
    static let later: [(String, () -> [String])] = [
        ("A backup pressed during another follows it, and a new destination is not credited with the old",
         overlappingBackups),
    ]

    private static let hour: TimeInterval = 3_600

    /// A scratch folder that exists: a backup refuses a destination that does not.
    private static func folder() -> URL {
        let directory = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func dueOnSchedule() -> [String] {
        var problems: [String] = []
        let now = SelfTest.base
        expect(!BackupSchedule.off.isDue(lastBackup: nil, now: now), "Off is never due", &problems)
        expect(BackupSchedule.daily.isDue(lastBackup: nil, now: now), "a first backup is due at once", &problems)
        let cases: [(BackupSchedule, TimeInterval, Bool)] = [
            (.everySixHours, 5.4 * hour, false), (.everySixHours, 5.5 * hour, true),
            (.daily, 23.4 * hour, false), (.daily, 23.5 * hour, true),
            (.weekly, 6 * 24 * hour, false), (.weekly, 7 * 24 * hour - 0.5 * hour, true),
        ]
        for (schedule, since, due) in cases {
            expect(schedule.isDue(lastBackup: now.addingTimeInterval(-since), now: now) == due,
                   "\(schedule.title) after \(since / hour) h should be due=\(due)", &problems)
        }
        expect(BackupSchedule.weekly.isDue(lastBackup: now.addingTimeInterval(hour), now: now),
               "a last backup dated after now (clock put back) does not hold the next off", &problems)
        let next = BackupSchedule.daily.nextDue(after: now, now: now)
        expect(next == now.addingTimeInterval(23.5 * hour), "the next daily one is 23.5 h on, got \(String(describing: next))",
               &problems)
        expect(BackupSchedule.off.nextDue(after: now, now: now) == nil, "Off has no next backup", &problems)
        return problems
    }

    private static func retentionCutoffs() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let now = SelfTest.base
        expect(BackupRetention.forever.cutoff(at: now, calendar: calendar) == nil, "Forever keeps all", &problems)
        let expected: [(BackupRetention, DateComponents)] = [
            (.oneWeek, DateComponents(day: -7)), (.twoWeeks, DateComponents(day: -14)),
            (.oneMonth, DateComponents(month: -1)), (.threeMonths, DateComponents(month: -3)),
            (.oneYear, DateComponents(year: -1)),
        ]
        for (retention, age) in expected {
            let cutoff = retention.cutoff(at: now, calendar: calendar)
            expect(cutoff == calendar.date(byAdding: age, to: now),
                   "\(retention.title) cuts off at \(age), got \(String(describing: cutoff))", &problems)
        }
        return problems
    }

    private static func pruneKeepsOthers() -> [String] {
        var problems: [String] = []
        let data = folder(), root = folder(), bin = folder()
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: SelfTest.base)! }
        let trash: (URL) throws -> Void = {
            try FileManager.default.moveItem(at: $0, to: bin.appendingPathComponent($0.lastPathComponent))
        }
        let old = try? DataBackup.make(from: data, preferences: nil, into: root, at: day(-20), automatic: true)
        let older = try? DataBackup.make(from: data, preferences: nil, into: root, at: day(-30), automatic: true)
        let manual = try? DataBackup.make(from: data, preferences: nil, into: root, at: day(-40))
        let recent = try? DataBackup.make(from: data, preferences: nil, into: root, at: day(-2), automatic: true)
        expect(old?.lastPathComponent.hasSuffix(DataBackup.automaticMark) == true,
               "an automatic backup's name says so, got \(old?.lastPathComponent ?? "none")", &problems)

        let moved = DataBackup.pruneAutomatic(in: root, before: day(-7), trash: trash)
        expect(Set(moved.map(\.lastPathComponent)) == Set([old, older].compactMap { $0?.lastPathComponent }),
               "the two expired automatic backups went to the Trash, got \(moved.map(\.lastPathComponent))", &problems)
        for kept in [manual, recent].compactMap({ $0 }) {
            expect(FileManager.default.fileExists(atPath: kept.path), "\(kept.lastPathComponent) stays", &problems)
        }

        let none = DataBackup.pruneAutomatic(in: root, before: day(1), trash: trash)
        expect(none.isEmpty && FileManager.default.fileExists(atPath: recent?.path ?? ""),
               "the newest automatic backup stays even past its period", &problems)

        let stuck = try? DataBackup.make(from: data, preferences: nil, into: root, at: day(-1), automatic: true)
        let refused = DataBackup.pruneAutomatic(in: root, before: day(1), trash: { _ in
            throw CocoaError(.featureUnsupported)
        })
        expect(refused.isEmpty && FileManager.default.fileExists(atPath: recent?.path ?? "")
               && FileManager.default.fileExists(atPath: stuck?.path ?? ""),
               "a backup the Trash refuses is left where it is, never deleted", &problems)
        expect(DataBackup.uploadState(of: root) == .notInICloud, "a local folder has nothing to upload", &problems)
        expect(DataBackup.uploadState(of: root.appendingPathComponent("gone")) == .missing,
               "a vanished backup reads as missing", &problems)
        return problems
    }

    private static func settingsSchedule() -> [String] {
        var problems: [String] = []
        let data = folder(), cloud = folder(), bin = folder()
        let suite = "fc-selftest-backups-\(UUID().uuidString)"
        defer { MemoryDefaults.remove(named: suite) }
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not open \(suite)"] }
        let store = PersistenceStore(defaults: defaults)
        try? Data("[]".utf8).write(to: data.appendingPathComponent("sessions.json"))
        func model() -> SettingsModel {
            SettingsModel(store: store, isTrackingEnabled: false, onChange: {}, onTrackingChanged: { _ in },
                          dataDirectory: data, backupRoot: cloud,
                          trashBackup: { try FileManager.default.moveItem(at: $0, to: bin.appendingPathComponent($0.lastPathComponent)) },
                          backupWork: { $0() })
        }
        let settings = model()
        let backups = cloud.appendingPathComponent(DataBackup.folderName)
        func made() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []).sorted() }

        expect(settings.backupSchedule == .daily && settings.backupRetention == .forever
               && settings.backupDestination == .iCloudDrive,
               "a new install backs up daily to iCloud Drive and keeps every backup", &problems)
        let now = SelfTest.base
        settings.backUpIfDue(now: now)
        expect(made().count == 1 && made().first?.hasSuffix(DataBackup.automaticMark) == true,
               "the first check makes one automatic backup, got \(made())", &problems)
        expect(settings.backupLog.lastSuccess == now, "the backup's time is kept", &problems)
        settings.backUpIfDue(now: now.addingTimeInterval(hour))
        expect(made().count == 1, "an hour later nothing is due, got \(made())", &problems)
        settings.backUpIfDue(now: now.addingTimeInterval(24 * hour))
        expect(made().count == 2, "a day later the next is made, got \(made())", &problems)
        expect(settings.nextBackup(now: now.addingTimeInterval(25 * hour)) == .at(now.addingTimeInterval(47.5 * hour)),
               "the next one is shown 23.5 h after the last", &problems)

        settings.backupRetention = .oneWeek
        settings.backUpIfDue(now: now.addingTimeInterval(10 * 24 * hour))
        expect(made().count == 1 && ((try? FileManager.default.contentsOfDirectory(atPath: bin.path)) ?? []).count == 2,
               "a week's keeping moved the two older automatic backups to the Trash, kept \(made())", &problems)

        settings.backupSchedule = .off
        settings.backUpIfDue(now: now.addingTimeInterval(30 * 24 * hour))
        expect(made().count == 1, "Off makes no backup", &problems)

        let unplugged = data.deletingLastPathComponent().appendingPathComponent("unplugged-\(UUID().uuidString)")
        settings.backupDestination = .folder(unplugged)
        expect(settings.backupLog == BackupLog(),
               "a new destination has no backup yet, so the next check backs up there", &problems)
        settings.backUp(at: now.addingTimeInterval(31 * 24 * hour))
        expect(settings.backupLog.lastSuccess == nil && settings.backupLog.failure?.contains("not available") == true
               && !FileManager.default.fileExists(atPath: unplugged.path),
               "a missing folder is reported and is not created, got \(settings.backupLog)", &problems)

        settings.chooseBackupFolder(data.appendingPathComponent("inside"))
        expect(settings.backupDestination == .folder(unplugged), "a folder inside the data folder is refused", &problems)

        let reloaded = model()
        expect(reloaded.backupSchedule == .off && reloaded.backupRetention == .oneWeek
               && reloaded.backupDestination == .folder(unplugged) && reloaded.backupLog == settings.backupLog,
               "schedule, keeping, folder and the last result survive a relaunch", &problems)
        store.removeAll()
        expect(store.backupSchedule == .daily && store.backupLog == BackupLog(),
               "erasing preferences returns backups to their defaults", &problems)
        return problems
    }

    private static func partialCopyLeavesNothing() -> [String] {
        var problems: [String] = []
        let data = folder(), root = folder()
        let unreadable = data.appendingPathComponent("b.json")
        try? Data("a".utf8).write(to: data.appendingPathComponent("a.json"))
        try? Data("b".utf8).write(to: unreadable)
        try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }

        let made = try? DataBackup.make(from: data, preferences: nil, into: root, at: SelfTest.base, automatic: true)
        let left = (try? FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent(DataBackup.folderName).path)) ?? []
        expect(made == nil, "a copy that cannot read every file fails", &problems)
        expect(left.isEmpty, "it leaves no backup folder, finished or partial, got \(left)", &problems)

        // A stage a quit left behind goes with the next backup.
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
        let backups = root.appendingPathComponent(DataBackup.folderName)
        let abandoned = backups.appendingPathComponent(".2023-11-01 0900 (automatic).partial", isDirectory: true)
        try? FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        _ = try? DataBackup.make(from: data, preferences: nil, into: root, at: SelfTest.base)
        expect(!FileManager.default.fileExists(atPath: abandoned.path),
               "a part copy a quit left behind is cleared by the next backup", &problems)

        // The running app's lock is not history, so it is not backed up.
        try? Data().write(to: data.appendingPathComponent(InstanceLock.fileName))
        let clone = try? DataBackup.clone(of: data)
        expect(clone.map { !FileManager.default.fileExists(atPath: $0.appendingPathComponent(InstanceLock.fileName).path) } == true
               && clone.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("a.json").path) } == true,
               "the clone keeps the data and drops the lock file", &problems)
        if let clone { try? FileManager.default.removeItem(at: clone) }
        return problems
    }

    private static func overlappingBackups() -> [String] {
        var problems: [String] = []
        let data = folder(), cloud = folder(), other = folder()
        let suite = "fc-selftest-backup-overlap-\(UUID().uuidString)"
        defer { MemoryDefaults.remove(named: suite) }
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not open \(suite)"] }
        let store = PersistenceStore(defaults: defaults)
        // The copy is held back, as a slow disk would hold it, and let go by hand.
        var held: [() -> Void] = []
        let settings = SettingsModel(store: store, isTrackingEnabled: false, onChange: {}, onTrackingChanged: { _ in },
                                     dataDirectory: data, backupRoot: cloud, backupWork: { held.append($0) })
        func release() { while !held.isEmpty { held.removeFirst()() } }
        func made(_ root: URL) -> Int {
            ((try? FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent(DataBackup.folderName).path)) ?? []).count
        }
        release()

        settings.backUp(at: SelfTest.base, automatic: true)
        settings.backUp(at: SelfTest.base)
        expect(settings.backupStatus?.contains("starts when it finishes") == true,
               "Back Up Now during a backup says it will follow, got \(settings.backupStatus ?? "nothing")", &problems)
        settings.backUp(at: SelfTest.base, automatic: true)
        release()
        expect(made(cloud) == 2, "the running backup and the one pressed during it are both made, got \(made(cloud))",
               &problems)

        settings.backUp(at: SelfTest.base.addingTimeInterval(3_600), automatic: true)
        settings.backupDestination = .folder(other)
        release()
        expect(settings.backupLog == BackupLog(),
               "a backup to the old place does not count for the new one, got \(settings.backupLog)", &problems)
        expect(settings.nextBackup(now: SelfTest.base.addingTimeInterval(3_600)) == .due,
               "so the new place is backed up at the next check", &problems)
        return problems
    }

    private static func upgradeStartsOff() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-backup-offer-\(UUID().uuidString)"
        defer { MemoryDefaults.remove(named: suite) }
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not open \(suite)"] }
        let store = PersistenceStore(defaults: defaults)

        store.settleBackupSchedule(isExistingInstall: true)
        expect(store.backupSchedule == .off && store.backupOfferPending,
               "an install from before starts with backups off and the offer pending", &problems)
        store.settleBackupSchedule(isExistingInstall: false)
        expect(store.backupSchedule == .off, "the first decision is never revisited", &problems)
        let settings = SettingsModel(store: store, isTrackingEnabled: false, onChange: {}, onTrackingChanged: { _ in },
                                     dataDirectory: folder(), backupRoot: folder(), backupWork: { $0() })
        settings.answerBackupOffer(backUpDaily: true)
        expect(store.backupSchedule == .daily && !store.backupOfferPending,
               "Back up every day turns daily backups on and ends the offer", &problems)
        store.backupOfferPending = true
        settings.backupSchedule = .weekly
        expect(!store.backupOfferPending, "choosing a schedule in Settings ends the offer too", &problems)

        store.removeAll()
        store.settleBackupSchedule(isExistingInstall: false)
        expect(store.backupSchedule == .daily && !store.backupOfferPending,
               "a new install backs up daily with no offer", &problems)
        store.removeAll()
        store.settleBackupSchedule(isExistingInstall: true)
        settings.answerBackupOffer(backUpDaily: false)
        expect(store.backupSchedule == .off && !store.backupOfferPending,
               "Not now leaves backups off and ends the offer", &problems)
        return problems
    }
}
