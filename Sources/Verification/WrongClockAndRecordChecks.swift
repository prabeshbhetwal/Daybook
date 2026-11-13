import Foundation

/// History that one bad input used to erase: a single save with the clock far
/// off, and a single unreadable record in the session archive.
enum WrongClockAndRecordChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A save with the clock a year ahead or decades behind keeps the reminder log", wrongClockKeepsBreakLog),
        ("One unreadable session record leaves the other 49 shown, and the original kept aside", oneBadRecordKeepsTheRest),
    ]

    private static let base = SelfTest.base
    private static let calendar = Calendar.current

    private static func wrongClockKeepsBreakLog() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = BreakLog(directory: directory, calendar: calendar)
        for minutes in 0..<5 {
            let shown = base.addingTimeInterval(TimeInterval(minutes * 600))
            log.recordShown(BreakPromptEntry(id: UUID(), kind: .main, due: shown, shown: shown))
        }
        log.noteRhythm(.off, on: base)

        // The clock jumps 401 days ahead for a few saves, then comes back.
        let ahead = calendar.date(byAdding: .day, value: 401, to: base)!
        log.noteRhythm(BreakRhythmSnapshot(eyes: true), on: ahead)
        log.noteEyesPrompt(at: ahead.addingTimeInterval(60))
        let afterAhead = BreakLog(directory: directory, calendar: calendar)
        expect(afterAhead.prompts.count == 5,
               "five prompts survive saves with the clock 401 days ahead, got \(afterAhead.prompts.count)", &problems)

        // A clock decades behind: its entry lands first, and nothing goes.
        let behind = calendar.date(byAdding: .year, value: -30, to: base)!
        afterAhead.recordShown(BreakPromptEntry(id: UUID(), kind: .eyes, due: behind, shown: behind))
        afterAhead.noteRhythm(.off, on: behind)
        afterAhead.noteRhythm(BreakRhythmSnapshot(eyes: true), on: base.addingTimeInterval(3_600))
        let afterBehind = BreakLog(directory: directory, calendar: calendar)
        expect(afterBehind.prompts.count == 6,
               "saves with the clock 30 years behind keep all six prompts, got \(afterBehind.prompts.count)", &problems)
        return problems
    }

    private static func oneBadRecordKeepsTheRest() -> [String] {
        var problems: [String] = []
        let manager = FileManager.default
        let directory = SelfTest.scratchDirectory()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sessions.json")
        let records = (0..<50).map { index in
            SessionRecord(name: "Work \(index)", workType: .deepWork,
                          start: base.addingTimeInterval(TimeInterval(index * 900)),
                          end: base.addingTimeInterval(TimeInterval(index * 900 + 600)), workSeconds: 600)
        }
        guard let encoded = try? JSONEncoder().encode(records),
              var elements = (try? JSONSerialization.jsonObject(with: encoded)) as? [[String: Any]],
              elements.count == 50 else { return ["could not build the fixture archive"] }
        elements[7]["id"] = "not a UUID"
        guard let original = try? JSONSerialization.data(withJSONObject: elements) else {
            return ["could not write the fixture archive"]
        }
        try? original.write(to: file)

        let first = SessionArchive(directory: directory, now: { base })
        expect(first.records.count == 49 && !first.isReadOnly,
               "49 records show after the load, writable, got \(first.records.count) read-only \(first.isReadOnly)", &problems)
        let relaunched = SessionArchive(directory: directory, now: { base.addingTimeInterval(60) })
        expect(relaunched.records.count == 49,
               "49 records show after a relaunch with no save between, got \(relaunched.records.count)", &problems)
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        let asides = names.filter { $0.hasPrefix("sessions-corrupt-") }
        expect(asides.count == 1, "one set-aside copy, got \(names)", &problems)
        if let aside = asides.first.map({ directory.appendingPathComponent($0) }) {
            expect((try? Data(contentsOf: aside)) == original,
                   "the set-aside copy holds the original bytes", &problems)
            let counts = SessionArchive.unreadableRecords(inSetAside: aside)
            expect(counts?.unreadable == 1 && counts?.total == 50,
                   "the set-aside copy reports 1 of 50 unreadable, got \(String(describing: counts))", &problems)
        }

        // A file that is not a list of records (garbage, or a newer format)
        // is set aside whole, as before: nothing in it is read or rewritten.
        let envelope = Data(#"{"version":2,"sessions":[]}"#.utf8)
        try? envelope.write(to: file)
        let whole = SessionArchive(directory: directory, now: { base.addingTimeInterval(120) })
        expect(whole.records.isEmpty && !manager.fileExists(atPath: file.path),
               "a file that is not a list is set aside whole, got \(whole.records.count) records", &problems)
        return problems
    }
}
