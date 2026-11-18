import Foundation

/// Activity-aware sessions: the constants, the signal gate and the beat
/// archive that keeps what each half-minute held. Archives here always sit in
/// a scratch directory, never the live one.
enum BeatArchiveChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Beats sit on a 30-second grid in every zone", gridHoldsInEveryZone),
        ("A beat reads back exactly as written", beatReadsBackExactly),
        ("A torn last line loses only that beat", tornLastLineLosesOnlyThatBeat),
        ("A beat line from a newer build is passed over", newerBuildLineIsPassedOver),
        ("A session across midnight reads both days once", acrossMidnightReadsBothDaysOnce),
        ("Old evidence is removed after the retention period", oldEvidenceIsRemoved),
        ("Signals are off until a probe passes", signalsAreOffUntilAProbePasses),
        ("The algorithm version moves with its constants", versionMovesWithConstants),
        ("A beat filed under another zone's day is still found", otherZoneDayIsStillFound),
        ("A beat line cut short before its newline is kept when the next beat is written", unendedLineIsKept),
        ("Two beats of one cell are both kept, in order of offset", twoBeatsInOneCellAreBothKept),
    ]

    // MARK: - Fixtures

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func date(_ calendar: Calendar, _ day: Int, _ month: Int, _ hour: Int, _ minute: Int,
                             _ second: Int = 0, year: Int = 2023) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    private static func slice(_ app: String, _ seconds: Int, keys: Int = 0, clicks: Int = 0,
                              scrolls: Int = 0) -> BeatSlice {
        BeatSlice(app: app, seconds: seconds, keys: keys, clicks: clicks, scrolls: scrolls)
    }

    private static func beat(_ start: Date, presence: BeatPresence = .input,
                             slices: [BeatSlice]? = nil) -> Beat {
        Beat(start: start, slices: slices ?? [slice("com.example.editor", 30, keys: 12)], presence: presence)
    }

    /// The one day file in a directory that holds a single day.
    private static func dayFile(_ directory: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".jsonl") }.first.map { directory.appendingPathComponent($0) }
    }

    private static func appendRaw(_ text: String, to url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }

    private static func wide(around date: Date) -> DateInterval {
        DateInterval(start: date.addingTimeInterval(-3_600), end: date.addingTimeInterval(3_600))
    }

    // MARK: - Checks

    private static func gridHoldsInEveryZone() -> [String] {
        var problems: [String] = []
        let grid = Beat.gridStart(for: SelfTest.base)
        expect(Beat.gridStart(for: grid.addingTimeInterval(29)) == grid,
               "29 seconds into a cell stays in it", &problems)
        expect(Beat.gridStart(for: grid.addingTimeInterval(30)) == grid.addingTimeInterval(30),
               "30 seconds into a cell starts the next one", &problems)
        for zone in ["Europe/Berlin", "Pacific/Kiritimati", "America/Los_Angeles"] {
            let local = date(calendar(zone), 15, 11, 9, 13, 20)
            let start = Beat.gridStart(for: local).timeIntervalSinceReferenceDate
            expect(start.truncatingRemainder(dividingBy: 30) == 0,
                   "grid start in \(zone) is a multiple of 30, got \(start)", &problems)
            expect(start <= local.timeIntervalSinceReferenceDate && local.timeIntervalSinceReferenceDate < start + 30,
                   "grid start in \(zone) holds the moment, got \(start)", &problems)
        }
        return problems
    }

    private static func beatReadsBackExactly() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let start = Beat.gridStart(for: SelfTest.base)
        let plain = beat(start)
        let held = Beat(start: start.addingTimeInterval(30), offset: 10,
                        slices: [slice("com.example.player", 20, clicks: 1), slice("", 0)],
                        presence: .watched, watchedApps: [])
        let quiet = Beat(start: start.addingTimeInterval(60), slices: [slice("com.example.editor", 30, scrolls: 4)],
                         presence: .quiet, watchedApps: ["com.example.player"])
        let archive = BeatArchive(directory: directory, calendar: .current)
        for beat in [plain, held, quiet] {
            do { try archive.append(beat) } catch { problems.append("append failed: \(error)") }
        }
        expect(archive.revision == 3, "three appends bump the revision to 3, got \(archive.revision)", &problems)
        let read = BeatArchive(directory: directory, calendar: .current)
            .beats(in: DateInterval(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(600)))
        expect(read == [plain, held, quiet], "beats read back equal and in order, got \(read)", &problems)
        expect(read.count == 3 && read[1].watchedApps == [] && read[2].watchedApps == ["com.example.player"]
                   && read[0].watchedApps == nil,
               "nil and empty watched apps read back distinct", &problems)
        let lines = dayFile(directory).flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .split(separator: "\n").map(String.init) ?? []
        expect(lines.count == 3, "one line per beat, got \(lines.count)", &problems)
        if lines.count == 3 {
            expect(!lines[0].contains("\"h\"") && !lines[0].contains("\"f\""),
                   "a beat with no holders read and no late start writes neither key: \(lines[0])", &problems)
            expect(lines[1].contains("\"h\":[]") && lines[1].contains("\"f\":10"),
                   "an empty holder list and a late start are written: \(lines[1])", &problems)
        }
        return problems
    }

    private static func tornLastLineLosesOnlyThatBeat() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let start = Beat.gridStart(for: SelfTest.base)
        let first = beat(start), second = beat(start.addingTimeInterval(30))
        let archive = BeatArchive(directory: directory, calendar: .current)
        try? archive.append(first)
        try? archive.append(second)
        guard let file = dayFile(directory) else { return ["no day file was written"] }
        appendRaw("{\"v\":1,\"t\":", to: file)
        let reload = BeatArchive(directory: directory, calendar: .current)
        let interval = DateInterval(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(600))
        expect(reload.beats(in: interval) == [first, second],
               "a half line costs only itself, got \(reload.beats(in: interval).count) beats", &problems)
        let third = beat(start.addingTimeInterval(60))
        try? reload.append(third)
        let after = BeatArchive(directory: directory, calendar: .current).beats(in: interval)
        expect(after == [first, second, third],
               "the next beat starts a line of its own, got \(after.count) beats", &problems)
        return problems
    }

    private static func newerBuildLineIsPassedOver() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let start = Beat.gridStart(for: SelfTest.base)
        let before = beat(start), after = beat(start.addingTimeInterval(60))
        try? BeatArchive(directory: directory, calendar: .current).append(before)
        guard let file = dayFile(directory) else { return ["no day file was written"] }
        let newer = "{\"v\":2,\"t\":\(Int(start.addingTimeInterval(30).timeIntervalSinceReferenceDate)),"
            + "\"s\":[],\"p\":\"input\",\"zz\":\"a field this build has never seen\"}\n"
        appendRaw(newer, to: file)
        try? BeatArchive(directory: directory, calendar: .current).append(after)
        let read = BeatArchive(directory: directory, calendar: .current)
            .beats(in: DateInterval(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(600)))
        expect(read == [before, after], "both good beats return around a newer line, got \(read.count)", &problems)
        return problems
    }

    private static func acrossMidnightReadsBothDaysOnce() -> [String] {
        var problems: [String] = []
        let berlin = calendar("Europe/Berlin")
        let late = beat(date(berlin, 28, 10, 23, 59, 30)), early = beat(date(berlin, 29, 10, 0, 0, 0))
        let directory = SelfTest.scratchDirectory()
        let writer = BeatArchive(directory: directory, calendar: berlin)
        try? writer.append(late)
        try? writer.append(early)
        let interval = DateInterval(start: date(berlin, 28, 10, 23, 50), end: date(berlin, 29, 10, 0, 10))
        for (label, archive) in [("the writer", writer),
                                 ("a fresh archive", BeatArchive(directory: directory, calendar: berlin))] {
            let read = archive.beats(in: interval)
            expect(read == [late, early], "\(label) reads both nights' beats once, got \(read.count)", &problems)
        }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        expect(files == ["2023-10-28.jsonl", "2023-10-29.jsonl"], "one file per local day, got \(files)", &problems)
        return problems
    }

    private static func oldEvidenceIsRemoved() -> [String] {
        var problems: [String] = []
        let calendar = SelfTest.gregorian
        let now = SelfTest.base
        let directory = SelfTest.scratchDirectory()
        let archive = BeatArchive(directory: directory, calendar: calendar)
        func ago(_ days: Int) -> Date {
            Beat.gridStart(for: calendar.date(byAdding: .day, value: -days, to: now)!)
        }
        for days in [91, 90, 1] { try? archive.append(beat(ago(days))) }
        let revision = archive.revision
        expect(archive.prune(olderThan: 90, now: now) == 1, "one day file is more than 90 days old", &problems)
        expect(archive.revision > revision, "removing evidence bumps the revision", &problems)
        let kept = BeatArchive(directory: directory, calendar: calendar)
            .beats(in: DateInterval(start: ago(100), end: now))
        expect(kept.map(\.start) == [ago(90), ago(1)], "the 90-day and 1-day beats stay, got \(kept.count) beats",
               &problems)
        expect(archive.beats(in: DateInterval(start: ago(100), end: now)).count == 2,
               "the pruned archive no longer serves the removed day from its cache", &problems)
        expect(archive.prune(olderThan: 90, now: now) == 0, "a second prune finds nothing", &problems)
        return problems
    }

    private static func signalsAreOffUntilAProbePasses() -> [String] {
        var problems: [String] = []
        for signal in SignalKind.allCases {
            for major in 14...30 {
                expect(!SignalGate.isOn(signal, macOSMajor: major),
                       "\(signal) is on for macOS \(major) with no passing probe report", &problems)
            }
        }
        return problems
    }

    private static func versionMovesWithConstants() -> [String] {
        var problems: [String] = []
        expect(ActivityConstants.algorithmVersion == 1 && ActivityConstants.signature
                   == "30|5|3|120|60|180|900|1500|0.7|0.15",
               "A rule or constant changed: change the constant, algorithmVersion and this literal together. "
                   + "Got version \(ActivityConstants.algorithmVersion), signature \(ActivityConstants.signature)",
               &problems)
        return problems
    }

    private static func otherZoneDayIsStillFound() -> [String] {
        var problems: [String] = []
        // 26 hours apart, so the reader's day for the beat is two days before the file's.
        let kiritimati = calendar("Pacific/Kiritimati"), farWest = calendar("Etc/GMT+12")
        let directory = SelfTest.scratchDirectory()
        let moved = beat(date(kiritimati, 15, 11, 0, 10))
        try? BeatArchive(directory: directory, calendar: kiritimati).append(moved)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        expect(files == ["2023-11-15.jsonl"], "the beat is filed under Kiritimati's day, got \(files)", &problems)
        let read = BeatArchive(directory: directory, calendar: farWest).beats(in: wide(around: moved.start))
        expect(read == [moved], "A reader 26 hours behind still finds the beat Kiritimati filed, got \(read.count)",
               &problems)
        return problems
    }

    private static func unendedLineIsKept() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let start = Beat.gridStart(for: SelfTest.base)
        let first = beat(start), second = beat(start.addingTimeInterval(30))
        try? BeatArchive(directory: directory, calendar: .current).append(first)
        // A write cut short after the line's last byte but before its newline.
        guard let file = dayFile(directory), let data = try? Data(contentsOf: file), data.last == 0x0A,
              (try? data.dropLast().write(to: file)) != nil else { return ["could not leave a line unended"] }
        try? BeatArchive(directory: directory, calendar: .current).append(second)
        let interval = DateInterval(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(600))
        let read = BeatArchive(directory: directory, calendar: .current).beats(in: interval)
        expect(read == [first, second], "both beats survive the next append, got \(read.count)", &problems)
        return problems
    }

    private static func twoBeatsInOneCellAreBothKept() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let start = Beat.gridStart(for: SelfTest.base)
        // A pause or a restart inside one cell: the same start, recording resumed 12 s in.
        let first = beat(start, slices: [slice("com.example.editor", 10, keys: 3)])
        let second = Beat(start: start, offset: 12, slices: [slice("com.example.editor", 18)], presence: .quiet)
        let writer = BeatArchive(directory: directory, calendar: .current)
        // Written out of order, so reading has to sort by offset as well.
        try? writer.append(second)
        try? writer.append(first)
        for (label, archive) in [("the writer", writer),
                                 ("a fresh archive", BeatArchive(directory: directory, calendar: .current))] {
            let read = archive.beats(in: wide(around: start))
            expect(read == [first, second], "\(label) should return both beats of the cell, offset 0 then 12, got \(read.map(\.offset))",
                   &problems)
        }
        return problems
    }
}
