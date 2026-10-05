import Foundation

/// History that a crash, a newer build or a corrupted file leaves behind is
/// read in full. Each check forces a failure that a probe-based hunt showed
/// losing or hiding history, or crashing the app on every launch.
enum JournalRecoveryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A complete journal line this build cannot read is set aside, not cut off", unreadableLastLine),
        ("Lines after an unreadable journal line still replay", linesAfterUnreadable),
        ("A journal missing its last newline keeps the next record", missingLastNewline),
        ("A change that compacts the journal is reported saved only if a relaunch reads it",
         compactionAgreesWithRelaunch),
        ("An impossible session length cannot crash the week chart or the rail", impossibleWorkSeconds),
    ]

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private static func scratch() -> URL {
        let directory = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func journal(in directory: URL) -> URL {
        directory.appendingPathComponent("app-usage-journal.jsonl")
    }

    private static func stretch(_ offset: TimeInterval, _ app: String,
                                length: TimeInterval = 300, id: UUID = UUID()) -> AppUsageSession {
        AppUsageSession(id: id, bundleID: "com.example.\(app.lowercased())", appName: app,
                        start: base.addingTimeInterval(offset),
                        end: base.addingTimeInterval(offset + length), endReason: .appSwitch)
    }

    /// Real journal lines, written by the archive itself.
    private static func journalLines(_ stretches: [AppUsageSession]) -> [String] {
        let source = SelfTest.scratchDirectory()
        let writer = AppUsageArchive(directory: source, now: { base })
        for stretch in stretches { writer.record(stretch) }
        let text = (try? String(contentsOf: journal(in: source), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// Whether any file in the directory still holds this text.
    private static func preserved(_ text: String, in directory: URL) -> Bool {
        let bytes = Data(text.utf8)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name)))?.range(of: bytes) != nil
        }
    }

    private static func names(_ archive: AppUsageArchive) -> [String] {
        archive.sessions.map(\.appName)
    }

    private static func unreadableLastLine() -> [String] {
        var problems: [String] = []
        let lines = journalLines([stretch(0, "Alpha"), stretch(600, "Beta")])
        guard lines.count == 2, lines[1].contains("\"appSwitch\"") else {
            return ["could not build the journal fixture"]
        }
        // A whole line in a form this build does not know, as a newer build writes it.
        let newer = lines[1].replacingOccurrences(of: "\"appSwitch\"", with: "\"sleep\"")
        let directory = scratch()
        try? Data((lines[0] + "\n" + newer + "\n").utf8).write(to: journal(in: directory))

        let archive = AppUsageArchive(directory: directory, now: { base })
        expect(names(archive) == ["Alpha"], "the readable line replays, got \(names(archive))", &problems)
        expect(preserved(newer, in: directory),
               "the line this build cannot read was deleted from disk", &problems)
        return problems
    }

    private static func linesAfterUnreadable() -> [String] {
        var problems: [String] = []
        let lines = journalLines([stretch(0, "Alpha"), stretch(600, "Beta")])
        guard lines.count == 2 else { return ["could not build the journal fixture"] }
        let directory = scratch()
        try? Data((lines[0] + "\nnot a journal line\n" + lines[1] + "\n").utf8)
            .write(to: journal(in: directory))

        let first = AppUsageArchive(directory: directory, now: { base })
        expect(names(first) == ["Alpha", "Beta"],
               "the line after the unreadable one replays, got \(names(first))", &problems)
        let relaunched = AppUsageArchive(directory: directory, now: { base })
        expect(names(relaunched) == ["Alpha", "Beta"],
               "a relaunch still has both, got \(names(relaunched))", &problems)
        expect(preserved("not a journal line", in: directory),
               "the unreadable line was not kept aside", &problems)
        return problems
    }

    private static func missingLastNewline() -> [String] {
        var problems: [String] = []
        let lines = journalLines([stretch(0, "Alpha")])
        guard lines.count == 1 else { return ["could not build the journal fixture"] }
        let manager = FileManager.default
        let directory = scratch()
        // The last write stopped just before its newline.
        try? Data(lines[0].utf8).write(to: journal(in: directory))
        // A folder that refuses new files keeps the launch from compacting the
        // journal away, so the next record is appended to it.
        try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        let first = AppUsageArchive(directory: directory, now: { base })
        let recorded = first.record(stretch(600, "Beta"))
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        let relaunched = AppUsageArchive(directory: directory, now: { base })
        expect(recorded, "the new record was refused", &problems)
        expect(names(relaunched) == ["Alpha", "Beta"],
               "after relaunch expected Alpha and Beta, got \(names(relaunched))", &problems)

        // A journal file that refuses writes in a folder that does not: the
        // launch compacts it away, so nothing needs repairing and nothing
        // turns read-only.
        let lockedFile = scratch()
        try? Data(lines[0].utf8).write(to: journal(in: lockedFile))
        try? manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: journal(in: lockedFile).path)
        let opened = AppUsageArchive(directory: lockedFile, now: { base })
        expect(!opened.isReadOnly && opened.record(stretch(600, "Beta")),
               "a read-only journal file turned the archive read-only (readOnly=\(opened.isReadOnly))", &problems)
        let reopened = AppUsageArchive(directory: lockedFile, now: { base })
        expect(names(reopened) == ["Alpha", "Beta"],
               "with a read-only journal file, a relaunch has \(names(reopened))", &problems)
        return problems
    }

    /// An archive whose next change is the one that compacts the journal, and
    /// the id of the 360-second stretch that change lengthens to 420.
    private static func oneChangeBeforeCompacting(in directory: URL) -> (AppUsageArchive, UUID) {
        let archive = AppUsageArchive(directory: directory, now: { base })
        for index in 0..<(AppUsageConstants.journalCompactionThreshold - 2) {
            archive.record(stretch(TimeInterval(1_000 + index * 400), "Filler"))
        }
        let id = UUID()
        archive.record(stretch(0, "Editor", length: 360, id: id))
        return (archive, id)
    }

    private static func compactionAgreesWithRelaunch() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        func lengthAfterRelaunch(_ directory: URL, _ id: UUID) -> TimeInterval? {
            AppUsageArchive(directory: directory, now: { base }).sessions.first { $0.id == id }?.seconds
        }

        // The journal can be neither appended to nor cleared.
        let locked = scratch()
        let (lockedArchive, lockedID) = oneChangeBeforeCompacting(in: locked)
        let journalURL = journal(in: locked)
        try? manager.setAttributes([.immutable: true], ofItemAtPath: journalURL.path)
        let lockedSaved = lockedArchive.checkpoint(stretch(0, "Editor", length: 420, id: lockedID))
        try? manager.setAttributes([.immutable: false], ofItemAtPath: journalURL.path)
        let lockedLength = lengthAfterRelaunch(locked, lockedID)
        expect(lockedSaved == (lockedLength == 420),
               "a locked journal: reported saved=\(lockedSaved), but a relaunch reads \(String(describing: lockedLength))",
               &problems)

        // The journal takes the line, but the folder refuses a new snapshot.
        let full = scratch()
        let (fullArchive, fullID) = oneChangeBeforeCompacting(in: full)
        try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: full.path)
        let fullSaved = fullArchive.checkpoint(stretch(0, "Editor", length: 420, id: fullID))
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: full.path)
        let fullLength = lengthAfterRelaunch(full, fullID)
        expect(fullSaved && fullLength == 420,
               "a journalled change whose snapshot failed: saved=\(fullSaved), relaunch reads \(String(describing: fullLength))",
               &problems)
        return problems
    }

    private static func impossibleWorkSeconds() -> [String] {
        var problems: [String] = []
        let directory = scratch()
        let record = SessionRecord(name: "Corrupted", workType: .deepWork,
                                   start: base.addingTimeInterval(-600), end: base, workSeconds: 600)
        guard let encoded = try? JSONEncoder().encode([record]),
              let text = String(data: encoded, encoding: .utf8),
              text.contains("\"workSeconds\":600") else { return ["could not build the archive fixture"] }
        // A corrupted or hand-edited file: JSON can hold 1e300, and it decodes.
        try? Data(text.replacingOccurrences(of: "\"workSeconds\":600", with: "\"workSeconds\":1e300").utf8)
            .write(to: directory.appendingPathComponent("sessions.json"))

        let archive = SessionArchive(directory: directory, now: { base })
        // Kept as stored: History discloses a malformed record, never rewrites it.
        expect(archive.records.first?.workSeconds == 1e300,
               "the stored length was rewritten to \(archive.records.first?.workSeconds ?? -1)", &problems)
        // Each of these used to trap on a whole-minute or whole-hour conversion.
        let today = archive.todayTotal()
        let bars = archive.weekBars().map(\.minutes)
        let rail = StoryRailFigures.minutes(today)
        _ = RewardEngine(log: [:], now: { base }).next(for: RewardContext(
            focusedToday: today, sameWeekdayLastWeek: nil, streak: 1, bestStreak: 1,
            goal: GoalProgress(goal: 3_600, achieved: today, typical: nil),
            endedMedia: nil, musicPairing: nil, isSessionRunning: true))
        expect(bars.allSatisfy { $0 == 0 }, "the week chart draws \(bars) minutes for it", &problems)
        expect(rail == 0, "the rail shows \(rail) minutes for it", &problems)
        return problems
    }
}
