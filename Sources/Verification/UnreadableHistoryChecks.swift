import Foundation

/// History that cannot be read is set aside, never written over. Each check
/// forces a failure that used to lose data: a set-aside name already taken, and
/// a journal left holding nothing but a torn line.
enum UnreadableHistoryChecks {
    static let tests: [(String, () -> [String])] = [
        ("An unreadable session archive survives a set-aside name already in use", sessionArchiveCollision),
        ("An unreadable session archive that cannot be moved is kept read-only", sessionArchiveUnmovable),
        ("An unreadable journal survives a set-aside name already in use", journalCollision),
        ("A journal holding only a torn line keeps the next record", tornOnlyJournal),
        ("A torn journal that cannot be cut short is left alone, read-only", tornJournalUncuttable),
        ("An unreadable preference list is kept aside before it is saved over", unreadablePreferenceList),
        ("An unreadable live session state is kept aside, not deleted", unreadableLiveState),
        ("A rest that cannot be saved is reported, not dropped in silence", unsavedRestIsReported)
    ]

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let stamp = Int(base.timeIntervalSince1970)

    private static func scratch() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-unreadable-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Whether any file in the directory still holds these exact bytes.
    private static func preserved(_ bytes: Data, in directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { name in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return false }
            return data.range(of: bytes) != nil
        }
    }

    private static func stretch(_ offset: TimeInterval, _ app: String) -> AppUsageSession {
        AppUsageSession(id: UUID(), bundleID: "com.example.\(app.lowercased())", appName: app,
                        start: base.addingTimeInterval(offset),
                        end: base.addingTimeInterval(offset + 300), endReason: .appSwitch)
    }

    private static func sessionArchiveCollision() -> [String] {
        var failures: [String] = []
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unreadable = Data("not json, but the only copy of this history".utf8)
        try? unreadable.write(to: directory.appendingPathComponent("sessions.json"))
        try? Data("an earlier set-aside file".utf8)
            .write(to: directory.appendingPathComponent("sessions-corrupt-\(stamp).json"))

        let archive = SessionArchive(directory: directory, now: { base })
        _ = archive.append(SessionRecord(name: "Later", workType: .deepWork, start: base,
                                         end: base.addingTimeInterval(600), workSeconds: 600))
        if !preserved(unreadable, in: directory) {
            failures.append("the unreadable archive was overwritten when its set-aside name was taken")
        }
        return failures
    }

    private static func sessionArchiveUnmovable() -> [String] {
        var failures: [String] = []
        let manager = FileManager.default
        let directory = scratch()
        defer { try? manager.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sessions.json")
        let unreadable = Data("not json, and nowhere to move it".utf8)
        try? unreadable.write(to: file)
        try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        let archive = SessionArchive(directory: directory, now: { base })
        let error = archive.append(SessionRecord(name: "Later", workType: .deepWork, start: base,
                                                 end: base.addingTimeInterval(600), workSeconds: 600))
        if !archive.isReadOnly || error == nil {
            failures.append("an archive that could not be set aside must refuse writes")
        }
        if (try? Data(contentsOf: file)) != unreadable {
            failures.append("the unreadable archive's bytes changed")
        }
        return failures
    }

    private static func journalCollision() -> [String] {
        var failures: [String] = []
        let directory = scratch()
        let source = scratch()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: source)
        }
        // Real journal lines, written by the archive itself.
        let writer = AppUsageArchive(directory: source, now: { base })
        writer.record(stretch(0, "Before"))
        writer.record(stretch(600, "After"))
        let lines = ((try? String(contentsOf: source.appendingPathComponent("app-usage-journal.jsonl"),
                                  encoding: .utf8)) ?? "").split(separator: "\n")
        guard lines.count == 2 else { return ["could not build the journal fixture"] }

        let journal = Data((lines[0] + "\nnot a journal line\n" + lines[1] + "\n").utf8)
        try? journal.write(to: directory.appendingPathComponent("app-usage-journal.jsonl"))
        try? Data("an earlier set-aside journal".utf8)
            .write(to: directory.appendingPathComponent("app-usage-journal-corrupt-\(stamp).jsonl"))

        _ = AppUsageArchive(directory: directory, now: { base })
        if !preserved(Data(lines[1].utf8), in: directory) {
            failures.append("the line after an unreadable one was lost when its set-aside name was taken")
        }
        return failures
    }

    private static func tornOnlyJournal() -> [String] {
        var failures: [String] = []
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try? Data("{\"upsert\":{\"_0\":{\"id\"".utf8)
            .write(to: directory.appendingPathComponent("app-usage-journal.jsonl"))

        let first = AppUsageArchive(directory: directory, now: { base })
        let kept = stretch(0, "Editor")
        if !first.record(kept) { failures.append("the new record was not accepted") }
        let relaunched = AppUsageArchive(directory: directory, now: { base })
        if relaunched.sessions != [kept] {
            failures.append("after relaunch expected the new record, got \(relaunched.sessions.count)")
        }
        return failures
    }

    private static func tornJournalUncuttable() -> [String] {
        var failures: [String] = []
        let manager = FileManager.default
        let directory = scratch()
        defer { try? manager.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("app-usage-journal.jsonl")
        let torn = Data("{\"upsert\":{\"_0\":{\"id\"".utf8)
        try? torn.write(to: journal)
        try? manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: journal.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: journal.path) }

        let archive = AppUsageArchive(directory: directory, now: { base })
        if !archive.isReadOnly || archive.record(stretch(0, "Editor")) {
            failures.append("a journal whose torn line cannot be removed must refuse new records")
        }
        if (try? Data(contentsOf: journal)) != torn {
            failures.append("the torn journal's bytes changed")
        }
        return failures
    }

    /// Whether any value in the suite still holds these exact bytes.
    private static func kept(_ bytes: Data, in defaults: UserDefaults) -> Bool {
        defaults.dictionaryRepresentation().values.contains { ($0 as? Data) == bytes }
    }

    private static func unreadablePreferenceList() -> [String] {
        var failures: [String] = []
        let suite = "fc.unreadable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated preferences"] }
        defer { defaults.removePersistentDomain(forName: suite) }
        let unreadable = Data("rules written by a build this one cannot read".utf8)
        defaults.set(unreadable, forKey: "fc.activityRules")
        defaults.set(unreadable, forKey: "fc.savedActivities")

        let store = PersistenceStore(defaults: defaults)
        if !store.activityRules.isEmpty { failures.append("unreadable rules should read as none") }
        store.activityRules = [ActivityRule(name: "Writing", workType: .deepWork,
                                            bundleIDs: ["com.example.editor"], isEnabled: true,
                                            startAfter: 180)]
        store.savedActivities = [SavedActivity(name: "Invoices", workType: .admin)]
        if !kept(unreadable, in: defaults) {
            failures.append("saving over unreadable rules and activities lost their only copy")
        }
        if store.activityRules.count != 1 || store.savedActivities.count != 1 {
            failures.append("the new rule and activity must still save")
        }
        return failures
    }

    private static func unreadableLiveState() -> [String] {
        let suite = "fc.unreadable.state.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated preferences"] }
        defer { defaults.removePersistentDomain(forName: suite) }
        let unreadable = Data("a running session this build cannot read".utf8)
        defaults.set(unreadable, forKey: "fc.state")
        let state = PersistenceStore(defaults: defaults).loadState()
        return state == nil && kept(unreadable, in: defaults) ? []
            : ["an unreadable live state must load as nil and keep its bytes"]
    }

    private static func unsavedRestIsReported() -> [String] {
        final class Box { var now: Date; var failing = false; init(_ now: Date) { self.now = now } }
        let box = Box(base)
        let suite = "fc.unsaved.rest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated preferences"] }
        let directory = scratch()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let prefs = PersistenceStore(defaults: defaults)
        prefs.breakThreshold = 5 * 60
        let archive = SessionArchive(directory: directory, now: { box.now },
                                     writeOverride: { _ in box.failing ? "The disk is full." : nil })
        let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "fc.unsaved.rest",
                                   schedulesDwell: false, now: { box.now })
        engine.start(workType: .deepWork, intent: "Film night")
        box.now += 20 * 60
        box.now += 10 * 60
        engine.transition(on: .watchingObserved(seconds: 600))
        box.now += 35 * 60
        engine.transition(on: .watchingObserved(seconds: 45 * 60))
        box.failing = true
        engine.transition(on: .idleObserved(seconds: 2))
        return engine.awayDecisionError == nil
            ? ["a Watching rest that failed to save left no error to show"] : []
    }
}
