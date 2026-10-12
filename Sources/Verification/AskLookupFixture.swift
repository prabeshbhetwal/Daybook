import Foundation

/// The history `AskLookupChecks` and the suites that borrow it read, through a real store.
extension AskLookupChecks {
    /// Wed 15 Nov 2023, 09:13, on a store whose History holds three sessions:
    /// Thesis on Mon 13 Nov 9–10 with the note "chapter two outline", Parser
    /// on Tue 14 Nov 14:00–15:30 with Safari in front 14:00–15:00, and Thesis
    /// on Tue 17 Oct 9–11. No break is recorded. The dashboard is shown and
    /// History never has been, so its day index is not built.
    struct Fixture {
        let clock: TestClock
        let calendar: Calendar
        let engine: SessionEngine
        let store: SessionStore
        let defaults: UserDefaults
        let suite: String
        /// Where the session, usage and metadata archives write.
        let directories: [URL]

        func cleanUp() {
            for directory in directories { try? FileManager.default.removeItem(at: directory) }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    /// `extraThesisDays` adds that many past days, each with one minute of
    /// Thesis and of Safari, for checks that need a long history.
    private static func makeFixture(extraThesisDays: Int = 0) -> Fixture? {
        let clock = TestClock(SelfTest.base)
        let calendar = Calendar.current.forPeriods
        let directories = (0..<3).map { _ in SelfTest.scratchDirectory() }
        directories.forEach { try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        let suite = "fc-selftest-ask-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        // A moment on the day `back` days before today, in the store's calendar.
        func moment(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: clock.value))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        // Written in one go: a thousand appends would rewrite the file a thousand times.
        let extraDays = (0..<extraThesisDays).map { 40 + $0 }
        let extra = extraDays.map {
            SessionRecord(name: "Thesis", workType: .deepWork, start: moment($0, 9), end: moment($0, 9, 1),
                          workSeconds: 60)
        }
        let file = directories[0].appendingPathComponent("sessions.json")
        if !extra.isEmpty, (try? JSONEncoder().encode(extra).write(to: file, options: .atomic)) == nil { return nil }
        let archive = SessionArchive(directory: directories[0], calendar: calendar, now: { clock.value })
        let thesis = SessionRecord(name: "Thesis", workType: .deepWork, start: moment(2, 9), end: moment(2, 10),
                                   workSeconds: 3_600)
        let records = [
            thesis,
            SessionRecord(name: "Parser", workType: .deepWork, start: moment(1, 14), end: moment(1, 15, 30),
                          workSeconds: 5_400),
            SessionRecord(name: "Thesis", workType: .deepWork, start: moment(29, 9), end: moment(29, 11),
                          workSeconds: 7_200),
        ]
        for record in records where archive.append(record) != nil { return nil }

        let envelope = SelfTest.UsageEnvelopeFixture(
            metadata: AppUsageMetadata(accurateFrom: moment(40 + extraThesisDays, 0)),
            sessions: [AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                       start: moment(1, 14), end: moment(1, 15))]
                + extraDays.map {
                    AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                    start: moment($0, 9), end: moment($0, 9, 1))
                })
        guard let data = try? JSONEncoder().encode(envelope),
              (try? data.write(to: directories[1].appendingPathComponent("app-usage.json"), options: .atomic)) != nil
        else { return nil }
        let usage = AppUsageArchive(directory: directories[1], calendar: calendar, now: { clock.value })

        let metadata = SessionMetadataArchive(directory: directories[2])
        guard case .saved = metadata.saveNote("chapter two outline", for: thesis.id) else { return nil }

        let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "com.example.ask", schedulesDwell: false, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.ask", idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, metadataArchive: metadata,
                                 now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        return Fixture(clock: clock, calendar: calendar, engine: engine, store: store, defaults: defaults,
                       suite: suite, directories: directories)
    }

    static func withFixture(extraThesisDays: Int = 0, _ body: (Fixture, inout [String]) -> Void) -> [String] {
        MainActor.assumeIsolated {
            guard let fixture = makeFixture(extraThesisDays: extraThesisDays) else {
                return ["could not build the Ask fixture"]
            }
            defer { fixture.cleanUp() }
            var problems: [String] = []
            body(fixture, &problems)
            return problems
        }
    }
}
