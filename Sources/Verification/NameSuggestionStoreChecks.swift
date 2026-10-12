import Foundation

/// The store half of name suggestions: which unnamed sessions from today and
/// yesterday are offered, the facts the on-device model reads, the earlier
/// names it may pick from, and what Name it and Keep as is leave behind. "Now"
/// is `SelfTest.base`, 9:13 am on Wed 15 Nov 2023 in the store's calendar.
enum NameSuggestionStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Only ended, unnamed focus sessions of 10 minutes or more from today and yesterday are offered, newest first", targets),
        ("A session from 23:30 to 00:40 belongs to yesterday and reads last night's", midnightLead),
        ("The 60-day window holds in another zone", windowZones),
        ("Facts list apps, the note and the candidates in the spec's layout", factsText),
        ("A session with a note but no apps gets facts; one with neither gets none", evidence),
        ("Auto names and category names are not earlier names; rule names are", earlierPool),
        ("Name it renames through a correction that Undo reverses", acceptUndo),
        ("Keep as is is remembered and trimmed to two days", keepTrim),
    ]

    /// Moments on the days before "now", in the store's calendar.
    struct Days {
        let calendar: Calendar
        var now = SelfTest.base
        func at(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
    }

    struct Fixture {
        let clock: TestClock
        let engine: SessionEngine
        let store: SessionStore
        let persistence: PersistenceStore
        let metadata: SessionMetadataArchive
    }

    static func record(_ start: Date, _ end: Date, _ type: WorkType = .deepWork, name: String = "",
                               thread: UUID = UUID(), auto: Bool = false) -> SessionRecord {
        SessionRecord(name: name, workType: type, start: start, end: end,
                      workSeconds: end.timeIntervalSince(start), threadID: thread, isAuto: auto)
    }

    static func app(_ name: String, _ start: Date, _ seconds: TimeInterval) -> AppUsageSession {
        AppUsageSession(bundleID: "com.example.\(name.lowercased())", appName: name,
                        start: start, end: start.addingTimeInterval(seconds))
    }

    /// A store over scratch archives and in-memory preferences. `zone` is the
    /// store's calendar base; nil keeps the Mac's.
    static func withFixture(zone: TimeZone? = nil, now: Date = SelfTest.base, records: (Days) -> [SessionRecord],
                            usage: (Days) -> [AppUsageSession] = { _ in [] },
                            _ body: @MainActor (Fixture, Days, inout [String]) -> Void) -> [String] {
        MainActor.assumeIsolated {
            var base = Calendar.current
            if let zone { base.timeZone = zone }
            let days = Days(calendar: base.forPeriods, now: now)
            let clock = TestClock(now)
            let directories = (0..<3).map { _ in SelfTest.scratchDirectory() }
            directories.forEach { try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
            let suite = "fc-selftest-name-suggestion-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
            defer { MemoryDefaults.remove(named: suite) }
            let archive = SessionArchive(directory: directories[0], now: { clock.value })
            for item in records(days) where archive.append(item) != nil { return ["could not append \(item.name)"] }
            let envelope = SelfTest.UsageEnvelopeFixture(metadata: AppUsageMetadata(accurateFrom: days.at(90, 0)),
                                                         sessions: usage(days))
            guard let data = try? JSONEncoder().encode(envelope),
                  (try? data.write(to: directories[1].appendingPathComponent("app-usage.json"))) != nil
            else { return ["could not write app usage"] }
            let usageArchive = AppUsageArchive(directory: directories[1], now: { clock.value })
            let persistence = PersistenceStore(defaults: defaults)
            let engine = SessionEngine(store: persistence, archive: archive, ownBundleID: "com.example.names",
                                       schedulesDwell: false, now: { clock.value })
            let tracker = AppUsageTracker(archive: usageArchive, ownBundleID: "com.example.names", idle: .disabled,
                                          now: { clock.value })
            let metadata = SessionMetadataArchive(directory: directories[2])
            let store = SessionStore(engine: engine, schedulesTicker: false, metadataArchive: metadata,
                                     now: { clock.value })
            store.attach(tracker: tracker, usage: usageArchive)
            store.setDashboardVisible(true)
            if zone != nil { store.periodCalendarBase = base }
            var problems: [String] = []
            body(Fixture(clock: clock, engine: engine, store: store, persistence: persistence, metadata: metadata),
                 days, &problems)
            return problems
        }
    }

    @MainActor static func target(_ f: Fixture, _ thread: UUID) -> DaySession? {
        f.store.nameSuggestionTargets().first { $0.threadID == thread }
    }

    private static func targets() -> [String] {
        let (a, d, i, n) = (UUID(), UUID(), UUID(), UUID())
        let kept = UUID()
        return withFixture(records: { days in [
            record(days.at(0, 7), days.at(0, 8), thread: a),                          // offered
            record(days.at(0, 5), days.at(0, 5).addingTimeInterval(599)),             // 9m59s
            record(days.at(0, 6), days.at(0, 6, 30), name: "Thesis"),                 // named
            record(days.at(0, 8, 10), days.at(0, 8, 40), .breakTime),                 // a break
            record(days.at(1, 14), days.at(1, 15), thread: d),                        // offered
            record(days.at(1, 20), days.at(1, 20, 10), thread: i),                    // exactly 10m
            record(days.at(1, 10), days.at(1, 11), thread: kept),                     // kept
            record(days.at(2, 10), days.at(2, 11)),                                   // two days ago
            // 6m before midnight and 6m after: one session of 12m, offered once.
            record(days.at(1, 23, 54), days.at(0, 0, 6), thread: n),
        ] }) { f, _, problems in
            f.persistence.nameSuggestionKept = [kept.uuidString]
            f.engine.start(workType: .deepWork, intent: "")
            f.clock.advance(15 * 60)
            let offered = f.store.nameSuggestionTargets()
            expect(offered.map(\.threadID) == [a, n, i, d],
                   "offered \(offered.map { "\($0.start) \($0.worked)s" }), not today 7:00, then yesterday 23:54, 20:00 and 14:00",
                   &problems)
            expect(offered.first { $0.threadID == n }?.worked == 720,
                   "the midnight session counts both days' 12m, got \(String(describing: offered.first { $0.threadID == n }?.worked))",
                   &problems)
        }
    }

    private static func midnightLead() -> [String] {
        let (m, a, d, i) = (UUID(), UUID(), UUID(), UUID())
        var problems = withFixture(records: { days in [
            record(days.at(1, 23, 30), days.at(0, 0, 40), thread: m),
            record(days.at(0, 7), days.at(0, 8, 20), thread: a),
            record(days.at(1, 14), days.at(1, 14, 45), thread: d),
            record(days.at(1, 18), days.at(1, 20), thread: i),
        ] }) { f, days, problems in
            guard let night = target(f, m) else { return problems.append("the 23:30–00:40 session is not offered") }
            expect(f.store.nameSuggestionTargets().filter { $0.threadID == m }.count == 1,
                   "the midnight session is offered once", &problems)
            expect(night.start == days.at(1, 23, 30) && night.worked == 4_200,
                   "it starts yesterday at 23:30 with 1h 10m, got \(night.start), \(night.worked)s", &problems)
            let leads = [m, a, d, i].compactMap { target(f, $0) }.map { f.store.nameSuggestionLead(for: $0) }
            let want = ["last night's 1h 10m session", "this morning's 1h 20m session",
                        "yesterday afternoon's 45m session", "yesterday evening's 2h session"]
            expect(leads == want, "leads read \(leads)", &problems)
            _ = f.metadata.saveNote("late fix", for: night.recordIDs[0])
            let first = f.store.nameFacts(for: night)?.text.components(separatedBy: "\n").first
            let line = "Session: Tue 14 Nov, 11:30 pm–12:40 am, 1h 10m focused, category \(WorkType.deepWork.displayName)."
            expect(first == line, "the facts open “\(first ?? "nil")”", &problems)
        }
        // A session that begins on the stroke of midnight is today's, and 9 am's "tonight" was hours ago.
        let p = UUID()
        problems += withFixture(records: { days in [record(days.at(0, 0), days.at(0, 0, 20), thread: p)] }) { f, _, problems in
            let lead = target(f, p).map { f.store.nameSuggestionLead(for: $0) }
            expect(lead == "last night's 20m session", "00:00–00:20 today reads “\(lead ?? "nil")”", &problems)
        }
        return problems
    }

    private static func windowZones() -> [String] {
        // Berlin, or Kolkata where the Mac already keeps Berlin's clock, so the
        // store's calendar differs from the Mac's and the window shows which it used.
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let zone = berlin.secondsFromGMT(for: SelfTest.base) == TimeZone.current.secondsFromGMT(for: SelfTest.base)
            ? TimeZone(identifier: "Asia/Kolkata")! : berlin
        return withFixture(zone: zone, records: { days in
            let start = days.calendar.date(byAdding: .day, value: -60, to: days.calendar.startOfDay(for: SelfTest.base))!
            return [record(start.addingTimeInterval(-5_400), start.addingTimeInterval(-3_600), name: "Old"),
                    record(start.addingTimeInterval(1_800), start.addingTimeInterval(3_600), name: "Recent")]
        }) { f, _, problems in
            let names = f.store.earlierSessionNames()
            expect(names == ["Recent"], "within 60 days of the store's today: \(names)", &problems)
        }
    }

    private static func factsText() -> [String] {
        let s = UUID()
        return withFixture(records: { days in [
            record(days.at(0, 7, 10), days.at(0, 8, 30), thread: s),
            record(days.at(3, 9), days.at(3, 10), name: "Daybook"),
            record(days.at(4, 9), days.at(4, 10), .learning, name: "Thesis"),
        ] }, usage: { days in [
            app("Xcode", days.at(0, 7, 10), 52 * 60), app("Safari", days.at(0, 8, 2), 18 * 60),
            app("Terminal", days.at(0, 8, 20), 6 * 60), app("Finder", days.at(0, 8, 26), 5),
            app("Xcode", days.at(3, 9), 40 * 60), app("Terminal", days.at(3, 9, 40), 20 * 60),
            app("Safari", days.at(4, 9), 40 * 60), app("Xcode", days.at(4, 9, 40), 20 * 60),
        ] }) { f, _, problems in
            guard let session = target(f, s) else { return problems.append("the session is not offered") }
            _ = f.metadata.saveNote("fixed parser for fortnight", for: session.recordIDs[0])
            guard let facts = f.store.nameFacts(for: session) else { return problems.append("no facts") }
            let want = """
                Session: Wed 15 Nov, 7:10–8:30 am, 1h 20m focused, category \(WorkType.deepWork.displayName).
                Apps: Xcode 52m, Safari 18m, Terminal 6m.
                Note: “fixed parser for fortnight”
                Earlier names that fit:
                1. Daybook (usually Xcode, Terminal; \(WorkType.deepWork.displayName))
                2. Thesis (usually Safari, Xcode; \(WorkType.learning.displayName))
                """
            expect(facts.text == want, "the facts read:\n\(facts.text)", &problems)
            expect(facts.appNames == ["Xcode", "Safari", "Terminal"], "app names \(facts.appNames)", &problems)
            expect(facts.candidates.map(\.name) == ["Daybook", "Thesis"], "candidates \(facts.candidates)", &problems)
            let key = "\(s)|\(session.end)|\(WorkType.deepWork.id)|fixed parser for fortnight"
            expect(facts.cacheKey == key, "cache key \(facts.cacheKey)", &problems)
        }
    }

    private static func evidence() -> [String] {
        let (noted, bare) = (UUID(), UUID())
        return withFixture(records: { days in [
            record(days.at(0, 7), days.at(0, 7, 30), thread: noted),
            record(days.at(0, 8), days.at(0, 8, 30), thread: bare),
        ] }, usage: { days in [app("Finder", days.at(0, 8, 5), 5)] }) { f, _, problems in
            guard let withNote = target(f, noted), let without = target(f, bare) else {
                return problems.append("both sessions should be offered")
            }
            _ = f.metadata.saveNote("planning", for: withNote.recordIDs[0])
            let text = f.store.nameFacts(for: withNote)?.text
            expect(text == "Session: Wed 15 Nov, 7:00–7:30 am, 30m focused, category \(WorkType.deepWork.displayName).\nNote: “planning”",
                   "a note alone gives “\(text ?? "nil")”", &problems)
            expect(f.store.nameFacts(for: without) == nil, "5 s of Finder and no note gave facts", &problems)
        }
    }

    private static func earlierPool() -> [String] {
        withFixture(records: { days in [
            record(days.at(9, 9), days.at(9, 10), name: "DayBook"),
            record(days.at(3, 9), days.at(3, 10), name: "Daybook"),
            record(days.at(3, 11), days.at(3, 12), name: "Detected coding", auto: true),
            record(days.at(3, 13), days.at(3, 14), name: "Writing rule", auto: true),
            record(days.at(3, 15), days.at(3, 16), name: WorkType.deepWork.displayName),
            record(days.at(3, 12), days.at(3, 12, 30), .breakTime, name: "Lunch"),
            record(days.at(3, 17), days.at(3, 18)),
        ] }) { f, _, problems in
            f.persistence.activityRules = [ActivityRule(name: "Writing rule", workType: .deepWork, bundleIDs: [])]
            let names = f.store.earlierSessionNames()
            expect(names.sorted() == ["Daybook", "Writing rule"], "earlier names \(names)", &problems)
        }
    }

    private static func acceptUndo() -> [String] {
        let s = UUID()
        return withFixture(records: { days in [record(days.at(0, 7), days.at(0, 8), thread: s)] }) { f, _, problems in
            guard let session = target(f, s) else { return problems.append("the session is not offered") }
            expect(!f.store.acceptNameSuggestion("  ", for: session), "a blank name was accepted", &problems)
            expect(f.store.acceptNameSuggestion("Daybook", for: session), "Name it failed", &problems)
            expect(f.engine.archive.records.allSatisfy { $0.name == "Daybook" }, "the record was not renamed", &problems)
            expect(target(f, s) == nil, "a named session is still offered", &problems)
            guard let correction = f.store.lastCorrection else { return problems.append("no correction to undo") }
            expect(f.store.undoCorrection(expectedID: correction.id), "Undo failed", &problems)
            expect(f.engine.archive.records.allSatisfy { $0.name.isEmpty }, "Undo left a name", &problems)
            expect(target(f, s) != nil, "after Undo the session is not offered", &problems)
        }
    }

    private static func keepTrim() -> [String] {
        let (today, yesterday, old, edge) = (UUID(), UUID(), UUID(), UUID())
        return withFixture(records: { days in [
            record(days.at(0, 7), days.at(0, 8), thread: today),
            record(days.at(1, 10), days.at(1, 11), thread: yesterday),
            record(days.at(3, 10), days.at(3, 11), thread: old),
            record(days.at(2, 23), days.at(1, 0), thread: edge),      // ends as yesterday begins
        ] }) { f, _, problems in
            f.persistence.nameSuggestionKept = Set([yesterday, old, edge, UUID()].map(\.uuidString))
            guard let session = target(f, today) else { return problems.append("today's session is not offered") }
            f.store.keepSessionUnnamed(session)
            let kept = f.persistence.nameSuggestionKept
            expect(kept == Set([today, yesterday].map(\.uuidString)), "kept \(kept)", &problems)
            expect(f.store.nameSuggestionTargets().isEmpty, "a kept session is still offered", &problems)
            f.persistence.removeAll()
            expect(f.persistence.nameSuggestionKept.isEmpty, "removeAll left the kept threads", &problems)
        }
    }
}
