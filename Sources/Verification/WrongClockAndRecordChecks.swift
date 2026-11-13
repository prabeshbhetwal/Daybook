import Foundation

/// History that one bad input used to erase: a single save with the clock far
/// off, and a single unreadable record in the session archive.
enum WrongClockAndRecordChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("One unreadable session record leaves the other 49 shown, and the original kept aside", oneBadRecordKeepsTheRest),
        ("Recovery stopped part way still leaves the 49 readable sessions shown", interruptedRecoveryKeepsTheRest),
        ("Settings' Recovery note says how many sessions are missing, or that all are", recoveryNoteMatchesWhatIsShown),
    ]

    private static let base = SelfTest.base
    private static let calendar = Calendar.current

    private static func oneBadRecordKeepsTheRest() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        let directory = SelfTest.scratchDirectory()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sessions.json")
        guard let original = oneBadRecordArchive() else { return ["could not build the fixture archive"] }
        try? original.write(to: file)

        let first = SessionArchive(directory: directory, now: { base })
        expect(first.records.count == 49 && !first.isReadOnly,
               "49 records show after the load, writable, got \(first.records.count) read-only \(first.isReadOnly)", &problems)
        let relaunched = SessionArchive(directory: directory, now: { base.addingTimeInterval(60) })
        expect(relaunched.records.count == 49,
               "49 records show after a relaunch with no save between, got \(relaunched.records.count)", &problems)
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        let asides = names.filter { $0.hasPrefix(SessionArchive.setAsidePrefix) }
        expect(asides.count == 1, "one set-aside copy, got \(names)", &problems)
        if let aside = asides.first.map({ directory.appendingPathComponent($0) }) {
            expect((try? Data(contentsOf: aside)) == original,
                   "the set-aside copy holds the original bytes", &problems)
            let counts = SessionArchive.unreadableRecords(inSetAside: aside)
            expect(counts?.unreadable == 1 && counts?.total == 50,
                   "the set-aside copy reports 1 of 50 unreadable, got \(String(describing: counts))", &problems)
        }

        // A file that is not a list of records (garbage, or a newer format)
        // is set aside whole: nothing in it is read, and none of it shows.
        let envelope = Data(#"{"version":2,"sessions":[]}"#.utf8)
        try? envelope.write(to: file)
        let whole = SessionArchive(directory: directory, now: { base.addingTimeInterval(120) })
        let wholeAside = directory.appendingPathComponent("\(SessionArchive.setAsidePrefix)\(stamp(120)).json")
        expect(whole.records.isEmpty && (try? Data(contentsOf: wholeAside)) == envelope,
               "a file that is not a list is set aside whole, got \(whole.records.count) records", &problems)
        return problems
    }

    private static func stamp(_ offset: TimeInterval) -> Int {
        Int(base.addingTimeInterval(offset).timeIntervalSince1970)
    }

    /// The fixture archive: 50 records, the eighth with an id that is not a UUID.
    private static func oneBadRecordArchive() -> Data? {
        let records = (0..<50).map { index in
            SessionRecord(name: "Work \(index)", workType: .deepWork,
                          start: base.addingTimeInterval(TimeInterval(index * 900)),
                          end: base.addingTimeInterval(TimeInterval(index * 900 + 600)), workSeconds: 600)
        }
        guard let encoded = try? JSONEncoder().encode(records),
              var elements = (try? JSONSerialization.jsonObject(with: encoded)) as? [[String: Any]] else { return nil }
        elements[7]["id"] = "not a UUID"
        return try? JSONSerialization.data(withJSONObject: elements)
    }

    /// Recovery stops part way, here or in a crash: sessions.json still holds
    /// the original or the recovered list, so the next launch shows the 49.
    private static func interruptedRecoveryKeepsTheRest() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        guard let original = oneBadRecordArchive() else { return ["could not build the fixture archive"] }

        // The copy is set aside, then the write of the 49 is refused.
        let refused = SelfTest.scratchDirectory()
        try? manager.createDirectory(at: refused, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: refused) }
        let file = refused.appendingPathComponent("sessions.json")
        try? original.write(to: file)
        let stopped = SessionArchive(directory: refused, now: { base }, writeOverride: { _ in "stopped" })
        expect(stopped.records.count == 49,
               "49 records show while the write back is refused, got \(stopped.records.count)", &problems)
        expect((try? Data(contentsOf: file)) == original,
               "sessions.json keeps the original until the 49 are written", &problems)
        let again = SessionArchive(directory: refused, now: { base.addingTimeInterval(30) },
                                   writeOverride: { _ in "stopped" })
        let next = SessionArchive(directory: refused, now: { base.addingTimeInterval(60) })
        expect(again.records.count == 49 && next.records.count == 49,
               "the next launches show 49, got \(again.records.count) and \(next.records.count)", &problems)
        let copies = ((try? manager.contentsOfDirectory(atPath: refused.path)) ?? [])
            .filter { $0.hasPrefix(SessionArchive.setAsidePrefix) }
        expect(copies.count == 1, "relaunches reuse the one set-aside copy, got \(copies)", &problems)

        // A crash left the copy half made: the next launch starts over.
        let leftover = SelfTest.scratchDirectory()
        try? manager.createDirectory(at: leftover, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: leftover) }
        try? original.write(to: leftover.appendingPathComponent("sessions.json"))
        try? Data("half a copy".utf8).write(to: leftover.appendingPathComponent(".sessions-unreadable.partial"))
        let resumed = SessionArchive(directory: leftover, now: { base })
        let names = (try? manager.contentsOfDirectory(atPath: leftover.path)) ?? []
        expect(resumed.records.count == 49 && !resumed.isReadOnly,
               "a leftover partial copy does not block recovery, got \(resumed.records.count)", &problems)
        expect(!names.contains(".sessions-unreadable.partial"),
               "the partial copy is cleared, got \(names)", &problems)
        return problems
    }

    /// The Recovery note says what is true: some sessions missing, all of
    /// them, or a whole history an earlier build set aside without keeping any.
    private static func recoveryNoteMatchesWhatIsShown() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        let directory = SelfTest.scratchDirectory()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        guard let original = oneBadRecordArchive() else { return ["could not build the fixture archive"] }
        func note(_ archive: SessionArchive) -> String {
            SettingsDiagnostics.live(usage: AppUsageArchive(directory: directory, now: { base }),
                                     sessions: archive, dataDirectory: directory).recoverySummary
        }
        let reveal = "Reveal Data Folder in Settings, Privacy finds it."

        // An earlier build's copy: it kept nothing, whatever the copy holds.
        let older = "sessions-corrupt-\(stamp(-60)).json"
        try? original.write(to: directory.appendingPathComponent(older))
        let olderNote = note(SessionArchive(directory: directory, now: { base }))
        expect(olderNote == "Session history that couldn't be read was kept as \(older) and isn't shown. " + reveal,
               "an earlier build's set-aside history reads: \(olderNote)", &problems)

        try? original.write(to: directory.appendingPathComponent("sessions.json"))
        let partName = "\(SessionArchive.setAsidePrefix)\(stamp(0)).json"
        let partNote = note(SessionArchive(directory: directory, now: { base }))
        expect(partNote == "1 of 50 sessions couldn't be read. The rest are shown, "
                   + "and the original history was kept as \(partName). " + reveal,
               "one unreadable session of 50 reads: \(partNote)", &problems)

        try? Data("not json".utf8).write(to: directory.appendingPathComponent("sessions.json"))
        let wholeName = "\(SessionArchive.setAsidePrefix)\(stamp(60)).json"
        let wholeNote = note(SessionArchive(directory: directory, now: { base.addingTimeInterval(60) }))
        expect(wholeNote == "Session history couldn't be read, so it isn't shown. "
                   + "It was kept as \(wholeName). " + reveal,
               "a history that is not a list reads: \(wholeNote)", &problems)
        return problems
    }
}
