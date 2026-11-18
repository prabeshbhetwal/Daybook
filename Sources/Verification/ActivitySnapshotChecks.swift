import Foundation

/// A session keeps a summary of its phases beside its notes (the snapshot), and its row reads phases
/// from its beats, else that summary, else its apps. Records and shows: none of it changes what a
/// session counts, its name or its category. The store rig is `ActivityEvidenceStoreChecks.rig`.
enum ActivitySnapshotChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session's phases reach its row", phasesReachTheRow),
        ("Clearing a note keeps the snapshot, and an entry holding only a snapshot is not dropped", clearingNoteKeepsSnapshot),
        ("A snapshot written before the key existed reads as none, and the file stays version 2", oldEntriesReadAsNone),
        ("An ended session's snapshot is written once and rewritten when its bounds or the rules change", writtenOnceRewrittenOnChange),
        ("After the evidence expires the snapshot is the record", snapshotIsTheRecord),
        ("A session with neither beats nor snapshot shows phases from its apps", appsOnlyWhenNothingElse),
        ("A session that began before the oldest day file kept reads its snapshot, not part of its beats", beganBeforeTheOldestDay),
        ("A session of several records reads its snapshots as one, and any record without one reads its apps", severalRecordsJoin),
        ("Snapshots of several records join: time and credit add up, depth and fingerprint are dropped", joinAddsUp),
        ("A running session is read from its closed beats only", runningTrailsByABeat),
        ("A session's phases are kept until its bounds, counted time, beats or the rules move", memoKey),
        ("At most 20 records are written per call, newest first", twentyPerSweep),
        ("The beat archive keeps eight days decoded at most and reads an evicted day again whole", beatCacheIsBounded),
        ("The beat archive covers a session only from its oldest day file", coversFromOldestDay),
    ] + backdatedPauseTests + repairTests

    static let coding = "com.apple.dt.Xcode"

    /// The first grid edge of the fixture day.
    static var t0: Date { Beat.gridStart(for: SelfTest.base) }

    /// `seconds` of 30-second beats from `start`, all of one app, in one state of input.
    static func beats(_ archive: BeatArchive, from start: Date, seconds: Int, app: String = coding,
                      keys: Int = 3, presence: BeatPresence = .input) {
        for step in 0..<(seconds / 30) {
            try? archive.append(Beat(start: start.addingTimeInterval(TimeInterval(step * 30)),
                                     slices: [BeatSlice(app: app, seconds: 30, keys: keys, clicks: 0, scrolls: 0)],
                                     presence: presence))
        }
    }

    /// A record of `seconds` from `start`; no pauses unless given.
    static func record(from start: Date, seconds: TimeInterval, paused: [DateInterval]? = [],
                       type: WorkType = .deepWork, thread: UUID = UUID()) -> SessionRecord {
        SessionRecord(name: "Parser", workType: type, start: start, end: start.addingTimeInterval(seconds),
                      workSeconds: seconds, threadID: thread, pausedSpans: paused)
    }

    /// The row a day shows for these records of one thread.
    static func daySession(_ records: [SessionRecord], running: Bool = false) -> DaySession {
        let ends = records.map(\.end).max() ?? t0
        return DaySession(id: records[0].id, threadID: records[0].threadID, name: records[0].name,
                          workType: records[0].workType, start: records.map(\.start).min() ?? t0, end: ends,
                          worked: records.reduce(0) { $0 + $1.workSeconds }, stretches: records.count,
                          spans: records.map { DateInterval(start: $0.start, end: $0.end) },
                          recordIDs: records.map(\.id), isRunning: running)
    }

    /// A stored shape with one counted phase, for what a check needs to tell apart.
    static func shape(_ label: ActivityLabel, credited: [String: TimeInterval], over bounds: DateInterval,
                      counted: TimeInterval? = nil, version: Int = ActivityConstants.algorithmVersion,
                      depth: SessionDepth? = .light) -> SessionActivityShape {
        SessionActivityShape(
            algorithmVersion: version, fidelity: .beats, bounds: bounds, countedSeconds: counted ?? bounds.duration,
            signals: [], phases: [SessionPhase(start: bounds.start, end: bounds.end, activity: .purpose(.coding),
                                               counted: true, credited: credited)],
            depth: depth, label: label, credited: credited,
            fingerprint: ActivityFingerprint(shares: [5, 0, 0, 0, 0, 0, 0], topApps: [coding, ""], siteKind: "none"),
            splitCandidates: [])
    }

    /// A metadata archive in its own folder, reopened from the same one by `reopened`.
    static func metadata() -> (archive: SessionMetadataArchive, directory: URL, reopened: () -> SessionMetadataArchive) {
        let directory = SelfTest.scratchDirectory()
        return (SessionMetadataArchive(directory: directory), directory, { SessionMetadataArchive(directory: directory) })
    }

    // MARK: - The sidecar

    private static func clearingNoteKeepsSnapshot() -> [String] {
        var problems: [String] = []
        let (archive, _, reopened) = metadata()
        let id = UUID(), other = UUID()
        let kept = shape(.activity(.coding), credited: ["coding": 300], over: DateInterval(start: t0, duration: 300))
        expect(archive.saveActivityShape(kept, for: id) == .saved, "a snapshot is saved", &problems)
        expect(archive.metadata(for: id)?.activityShape == kept, "and kept whole", &problems)
        archive.saveNote("x", for: id)
        archive.saveNote(nil, for: id)
        expect(archive.metadata(for: id)?.activityShape == kept && archive.metadata(for: id)?.note == nil,
               "a note saved and then cleared leaves the snapshot, and the entry stays", &problems)
        archive.saveNote("  \n ", for: id)
        expect(archive.metadata(for: id)?.activityShape == kept, "a blank note does not drop the entry", &problems)
        archive.saveNote("only a note", for: other)
        archive.saveNote(nil, for: other)
        expect(archive.metadata(for: other) == nil, "an entry with no note, power or snapshot is dropped", &problems)
        expect(reopened().metadata(for: id)?.activityShape == kept, "the snapshot is there when the folder is reopened", &problems)
        return problems
    }

    private static func oldEntriesReadAsNone() -> [String] {
        var problems: [String] = []
        let (archive, directory, reopened) = metadata()
        let id = UUID()
        archive.saveNote("an older entry", for: id)
        let metadata = reopened().metadata(for: id)
        expect(metadata?.note == "an older entry" && metadata?.activityShape == nil,
               "an entry written without the key reads with no snapshot, got \(String(describing: metadata?.activityShape))", &problems)
        let blank = SessionMetadata(recordID: id)
        expect(blank.isEmpty, "an entry with a note, readings and snapshot all absent is empty", &problems)
        var held = blank
        held.activityShape = shape(.unsorted, credited: [:], over: DateInterval(start: t0, duration: 60))
        expect(!held.isEmpty, "a snapshot alone is not empty", &problems)
        let file = (try? String(contentsOf: directory.appendingPathComponent("session-metadata.json"), encoding: .utf8)) ?? ""
        expect(file.contains("\"version\" : 2"), "the file stays version 2", &problems)
        return problems
    }

    private static func joinAddsUp() -> [String] {
        var problems: [String] = []
        let first = shape(.activity(.coding), credited: ["coding": 600], over: DateInterval(start: t0, duration: 600),
                          counted: 600)
        let second = shape(.activity(.design), credited: ["design": 900, "coding": 100],
                           over: DateInterval(start: t0.addingTimeInterval(1_200), duration: 1_000), counted: 900)
        expect(SessionActivityShape.joined([first]) == first, "one shape is itself", &problems)
        expect(SessionActivityShape.joined([]) == nil, "none is none", &problems)
        guard let both = SessionActivityShape.joined([first, second]) else { return problems + ["two shapes did not join"] }
        expect(both.bounds == DateInterval(start: t0, end: t0.addingTimeInterval(2_200)), "the bounds span both, got \(both.bounds)", &problems)
        expect(both.countedSeconds == 1_500, "counted time adds, got \(both.countedSeconds)", &problems)
        expect(both.credited == ["coding": 700, "design": 900], "credit adds, got \(both.credited)", &problems)
        expect(both.label == .activity(.design), "the label follows the summed credit, got \(both.label)", &problems)
        expect(both.depth == nil && both.fingerprint == nil, "depth and fingerprint are dropped", &problems)
        expect(both.phases.map(\.start) == [first.bounds.start, second.bounds.start], "the phases keep their order", &problems)
        return problems
    }

    // MARK: - The beat archive

    private static func beatCacheIsBounded() -> [String] {
        var problems: [String] = []
        let archive = BeatArchive(directory: SelfTest.scratchDirectory())
        let days = BeatArchive.cachedDayLimit + 4
        func start(_ daysAgo: Int) -> Date {
            Beat.gridStart(for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: SelfTest.base) ?? SelfTest.base)
        }
        for ago in (0..<days).reversed() { beats(archive, from: start(ago), seconds: 60) }
        expect(archive.cachedDayCount <= BeatArchive.cachedDayLimit,
               "\(days) days appended keep at most \(BeatArchive.cachedDayLimit) decoded, got \(archive.cachedDayCount)", &problems)
        let everything = DateInterval(start: start(days + 1), end: start(0).addingTimeInterval(86_400))
        expect(archive.beats(in: everything).count == days * 2, "every day is still read, got \(archive.beats(in: everything).count)", &problems)
        expect(archive.cachedDayCount <= BeatArchive.cachedDayLimit, "and reading keeps the limit, got \(archive.cachedDayCount)", &problems)
        // The oldest day was dropped from the cache; an append to it must not lose the beats already on disk.
        beats(archive, from: start(days - 1).addingTimeInterval(60), seconds: 30)
        let oldest = archive.beats(in: DateInterval(start: start(days - 1), duration: 300))
        expect(oldest.count == 3, "an append to a day dropped from the cache keeps its earlier beats, got \(oldest.count)", &problems)
        return problems
    }

    private static func coversFromOldestDay() -> [String] {
        var problems: [String] = []
        let archive = BeatArchive(directory: SelfTest.scratchDirectory())
        expect(!archive.covers(from: t0), "with no files nothing is covered", &problems)
        let calendar = Calendar.current
        let today = t0
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        beats(archive, from: today, seconds: 60)
        expect(archive.covers(from: today), "a session from the oldest day on is covered", &problems)
        expect(archive.covers(from: today.addingTimeInterval(3_600)), "and so is a later one", &problems)
        expect(!archive.covers(from: yesterday), "one from an earlier day is not", &problems)
        beats(archive, from: yesterday, seconds: 60)
        expect(archive.covers(from: yesterday), "it is once that day is kept", &problems)
        return problems
    }
}
