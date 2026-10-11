import Foundation

/// The history Ask Daybook v2 part 2's checks read, through a real store.
/// It holds every kind of record a lookup may name, so a check adds data of
/// its own only for what is unusual. Wed 15 Nov 2023, 9:13am; goal 4h,
/// streak minimum 1h.
///
/// - Fri 10, Sat 11, Sun 12 and Tue 14 Nov: Thesis 7:00-8:00am, each day its
///   own thread, Safari in front. Tue's has the note "tokenizer rewrite".
/// - Mon 13 Nov: Thesis in two records of one thread, 9:00-10:40am and
///   11:05am-12:25pm, Safari in front, the first with a note and battery
///   readings, the second on external power; Parser 2:00-3:12pm with Xcode;
///   Email (Admin) 4:30-5:00pm with Mail. Breaks: Lunch 12:25-1:10pm and
///   one unnamed 3:40-3:55pm. Two answers about time away, which carry no
///   record of their own: "Meeting" 10:40-11:05am, counted, and "Coffee"
///   4:10-4:30pm, a break.
/// - A Mac event log from Sun 12 Nov: wake, lock and unlock, a sleep, a wake
///   and a crash found at the launch on Tue 14.
/// - Reading, 9:00-10:00am on each of 1-12 Oct 2023, the best streak; Oct 5
///   runs until 2:00pm with Xcode in front for the first hour only.
///
/// Focus: Mon 13 Nov 4h 42m, goal met; Tue 14 Nov 1h; Oct 5 5h with 1h of
/// goal credit. Current streak 5 days since Fri 10 Nov; best 12.
struct AskDataFixture {
    let clock: TestClock
    let calendar: Calendar
    let engine: SessionEngine
    let store: SessionStore
    let metadata: SessionMetadataArchive
    let machineEvents: MachineEventLog
    let directories: [URL]
    let defaults: UserDefaults
    let suite: String

    let tuesdayThesis: SessionRecord
    let thesisA: SessionRecord
    let thesisB: SessionRecord
    let parser: SessionRecord
    let email: SessionRecord
    let lunch: SessionRecord
    let shortBreak: SessionRecord
    let octFifth: SessionRecord
    let receipts: [AwayDecisionReceipt]

    /// A moment `back` days before today, in the store's calendar.
    func moment(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.moment(calendar, clock.value, back, hour, minute)
    }

    private static func moment(_ calendar: Calendar, _ now: Date, _ back: Int, _ hour: Int, _ minute: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func cleanUp() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        defaults.removePersistentDomain(forName: suite)
    }

    /// `extraBreakDays` adds that many past days before the history, each
    /// with one unnamed 15-minute break, for checks that need a long record.
    static func with(extraBreakDays: Int = 0,
                     _ body: @MainActor (AskDataFixture, inout [String]) -> Void) -> [String] {
        MainActor.assumeIsolated {
            guard let fixture = make(extraBreakDays: extraBreakDays) else { return ["could not build the Ask data fixture"] }
            defer { fixture.cleanUp() }
            var problems: [String] = []
            body(fixture, &problems)
            return problems
        }
    }

    @MainActor
    private static func make(extraBreakDays: Int) -> AskDataFixture? {
        let clock = TestClock(SelfTest.base)
        let calendar = Calendar.current.forPeriods
        let directories = (0..<4).map { _ in SelfTest.scratchDirectory() }
        directories.forEach { try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        let suite = "fc-selftest-ask-data-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        func at(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date { moment(calendar, clock.value, back, hour, minute) }
        func october(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2023, month: 10, day: day, hour: hour))!
        }
        func record(_ name: String, _ type: WorkType, _ start: Date, _ end: Date, thread: UUID = UUID()) -> SessionRecord {
            SessionRecord(name: name, workType: type, start: start, end: end,
                          workSeconds: end.timeIntervalSince(start), threadID: thread)
        }

        let thesisThread = UUID()
        let days = [5, 4, 3].map { record("Thesis", .deepWork, at($0, 7), at($0, 8)) }
        let tuesday = record("Thesis", .deepWork, at(1, 7), at(1, 8))
        let thesisA = record("Thesis", .deepWork, at(2, 9), at(2, 10, 40), thread: thesisThread)
        let thesisB = record("Thesis", .deepWork, at(2, 11, 5), at(2, 12, 25), thread: thesisThread)
        let parser = record("Parser", .deepWork, at(2, 14), at(2, 15, 12))
        let email = record("Email", .admin, at(2, 16, 30), at(2, 17))
        let lunch = record("Lunch", .breakTime, at(2, 12, 25), at(2, 13, 10))
        let shortBreak = record("Break", .breakTime, at(2, 15, 40), at(2, 15, 55))
        let reading = (1...12).map { record("Reading", .deepWork, october($0, 9), october($0, $0 == 5 ? 14 : 10)) }
        let all = days + [tuesday, thesisA, thesisB, parser, email, lunch, shortBreak] + reading
        // Written in one go: a thousand appends would rewrite the file a thousand times.
        let extra = (0..<extraBreakDays).map {
            SessionRecord(name: "", workType: .breakTime, start: at(40 + $0, 15, 40), end: at(40 + $0, 15, 55),
                          workSeconds: 900)
        }
        let file = directories[0].appendingPathComponent("sessions.json")
        if !extra.isEmpty, (try? JSONEncoder().encode(extra).write(to: file, options: .atomic)) == nil { return nil }
        let archive = SessionArchive(directory: directories[0], calendar: calendar, now: { clock.value })
        for item in all where archive.append(item) != nil { return nil }

        func front(_ id: String, _ name: String, _ start: Date, _ end: Date) -> AppUsageSession {
            AppUsageSession(bundleID: id, appName: name, start: start, end: end)
        }
        let safari = (days + [tuesday, thesisA, thesisB]).map { front("com.apple.Safari", "Safari", $0.start, $0.end) }
        let usage = safari + [front("com.apple.dt.Xcode", "Xcode", parser.start, parser.end),
                              front("com.apple.mail", "Mail", email.start, email.end),
                              front("com.apple.dt.Xcode", "Xcode", october(5, 9), october(5, 10))]
        let envelope = SelfTest.UsageEnvelopeFixture(
            metadata: AppUsageMetadata(accurateFrom: calendar.date(from: DateComponents(year: 2023, month: 9, day: 30))!),
            sessions: usage)
        guard let data = try? JSONEncoder().encode(envelope),
              (try? data.write(to: directories[1].appendingPathComponent("app-usage.json"), options: .atomic)) != nil
        else { return nil }
        let usageArchive = AppUsageArchive(directory: directories[1], calendar: calendar, now: { clock.value })

        let metadata = SessionMetadataArchive(directory: directories[2])
        guard case .saved = metadata.saveNote("chapter three, fixed citations", for: thesisA.id),
              case .saved = metadata.saveNote("tokenizer rewrite", for: tuesday.id) else { return nil }
        func power(_ source: PowerSourceKind, _ percent: Double, _ time: Date, _ boundary: PowerCoverageBoundary,
                   for record: SessionRecord) -> Bool {
            let charging: PowerChargingState = source == .external ? .charging : .notCharging
            if case .saved = metadata.appendPower(PowerObservation(timestamp: time, source: source, percentage: percent,
                                                                  charging: charging, boundary: boundary),
                                                  for: record.id) { return true }
            return false
        }
        guard power(.battery, 82, thesisA.start, .stretchStarted, for: thesisA),
              power(.battery, 61, thesisA.end, .stretchEnded, for: thesisA),
              power(.external, 61, thesisB.start, .stretchStarted, for: thesisB),
              power(.external, 88, thesisB.end, .stretchEnded, for: thesisB) else { return nil }

        let log = MachineEventLog(directory: directories[3])
        guard log.append([MachineEvent(kind: .wake, at: at(3, 8)),
                          MachineEvent(kind: .lock, at: at(2, 12, 25)),
                          MachineEvent(kind: .unlock, at: at(2, 13, 10)),
                          MachineEvent(kind: .systemSleep, at: at(2, 23, 48)),
                          MachineEvent(kind: .wake, at: at(1, 7, 52)),
                          MachineEvent(kind: .crashed, at: at(1, 8), latest: at(1, 8, 2))]) else { return nil }

        let meeting = AwayDecisionReceipt(
            id: UUID(), range: DateInterval(start: at(2, 10, 40), end: at(2, 11, 5)), name: "Meeting",
            workType: .deepWork, threadID: thesisThread, sessionStart: thesisA.start, decision: .mergeTime,
            insertedRecord: nil, creditedSeconds: 1_500)
        let coffee = AwayDecisionReceipt(
            id: UUID(), range: DateInterval(start: at(2, 16, 10), end: at(2, 16, 30)), name: "Coffee",
            workType: .admin, threadID: email.threadID, sessionStart: email.start, decision: .tookBreak,
            insertedRecord: nil, creditedSeconds: 0)

        let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "com.example.ask", schedulesDwell: false, now: { clock.value })
        engine.store.streakMinimum = 3_600
        engine.store.dailyGoal = 14_400
        // Receipts come in through the state the engine loads, as an app launch hands them over.
        var saved = engine.snapshot()
        saved.awayDecisions = [meeting, coffee]
        saved.awayDecision = coffee
        engine.restore(from: saved)

        let tracker = AppUsageTracker(archive: usageArchive, ownBundleID: "com.example.ask", idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, metadataArchive: metadata, now: { clock.value })
        store.attach(tracker: tracker, usage: usageArchive)
        store.machineEventLog = log
        store.setDashboardVisible(true)
        return AskDataFixture(clock: clock, calendar: calendar, engine: engine, store: store, metadata: metadata,
                              machineEvents: log, directories: directories, defaults: defaults, suite: suite,
                              tuesdayThesis: tuesday, thesisA: thesisA, thesisB: thesisB, parser: parser,
                              email: email, lunch: lunch, shortBreak: shortBreak, octFifth: reading[4],
                              receipts: [meeting, coffee])
    }
}
