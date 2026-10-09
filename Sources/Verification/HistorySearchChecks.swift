import Foundation

/// History's search, end to end through a real engine and store: every word
/// must be found somewhere a session or break is known by, whatever it is
/// called now or was called before, and the row says why it matched.
enum HistorySearchChecks {
    static let tests: [(String, () -> [String])] = [
        ("Search finds a session by every word, across its name, old name, notes and date", sessionWords),
        ("Search finds a named break by where you were, and lists it under its day", namedBreak)
    ]

    /// Monday 31 August 2026: Parser runs 09:00–09:10, a break named for the
    /// café runs 09:20–09:40, then Parser runs again until 09:50. The second
    /// stretch carries a two-line note, and Parser is then renamed Compiler.
    private final class Fixture {
        var time = SelfTest.gregorian.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fc-history-search-\(UUID())")
        let suite = "fc.history-search.\(UUID())"
        lazy var defaults = MemoryDefaults.suite(named: suite)!
        lazy var archive = SessionArchive(directory: directory, now: { self.time })
        lazy var engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                        ownBundleID: "fc.history-search.test", schedulesDwell: false,
                                        now: { self.time })
        lazy var store = SessionStore(engine: engine, schedulesTicker: false,
                                      applicationIsRunning: { _ in false },
                                      activateApplication: { _, _ in }, now: { self.time })
        var thread = UUID()
        var day: Date { Calendar.current.startOfDay(for: time) }

        /// Nil when the story could not be set up; the checks then say so.
        func build() -> String? {
            engine.start(workType: .deepWork, intent: "Parser")
            thread = engine.activeThreadID
            time.addTimeInterval(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            time.addTimeInterval(1_200)
            engine.transition(on: .awayEnded)
            guard store.resolve(.tookBreak, label: "at the café with Sam") else { return "the break was not recorded" }
            time.addTimeInterval(600)
            guard engine.stop() else { return "the session did not stop" }
            guard let second = archive.records.filter({ $0.threadID == thread }).max(by: { $0.start < $1.start })
            else { return "Parser's second stretch is missing" }
            store.setNoteDraft("Tried the lexer rewrite\nFixed the tokenizer bug", for: second.id)
            guard store.saveNote(for: second.id) else { return "the note did not save" }
            guard let session = store.journalSession(thread: thread, on: day),
                  store.renameSession(session, to: "Compiler") else { return "the rename did not save" }
            return nil
        }

        func hits(_ query: String) -> [HistorySearchHit] {
            store.setHistoryQuery(query)
            return store.historySearchHits(limit: .max)
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func sessionWords() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            if let failure = f.build() { return [failure] }
            var failures: [String] = []
            let worked = f.archive.records.filter { $0.threadID == f.thread }.reduce(0) { $0 + $1.workSeconds }

            let byOldName = f.hits("parser").filter { $0.workType.countsAsFocus }
            if byOldName.map(\.name) != ["Compiler"] {
                failures.append("its old name found \(byOldName.map(\.name)), not the renamed Compiler")
            }
            let across = f.hits("Tokenizer, compiler")
            if across.count != 1 || across.first?.worked != worked {
                failures.append("words from the note and the name found \(across.count) results, "
                                + "\(across.first?.worked ?? 0)s of \(worked)s")
            }
            if across.first?.noteSnippet != "Fixed the tokenizer bug" {
                failures.append("the note line said \(across.first?.noteSnippet ?? "nothing"), not the matching one")
            }
            if let session = f.store.journalSession(thread: f.thread, on: f.day),
               f.store.journalNoteLine(for: session) != "Fixed the tokenizer bug" {
                failures.append("the row showed \(f.store.journalNoteLine(for: session) ?? "no note"), not the matching line")
            }
            if f.hits("monday 31/8/2026 morning compiler").count != 1 {
                failures.append("the weekday, date and time of day did not find the session")
            }
            if !f.hits("tokenizer banana").isEmpty {
                failures.append("a word found nowhere still matched")
            }
            return failures
        }
    }

    private static func namedBreak() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            if let failure = f.build() { return [failure] }
            var failures: [String] = []

            let cafe = f.hits("cafe sam")
            guard cafe.count == 1, let hit = cafe.first, hit.workType == .breakTime else {
                return ["\"cafe sam\" found \(cafe.map(\.name)), not the one break"]
            }
            let entries = HistoryJournalBuilder.entries(matching: cafe)
            let rows = entries.compactMap { entry -> [DayEntry]? in
                guard case .day(let day) = entry else { return nil }
                return HistoryJournalBuilder.rows(f.store.storyDayProjection(on: day.date), only: day.threads)
            }.flatMap { $0 }
            let names = rows.map { entry -> String in
                switch entry {
                case .rest(let rest): return "rest \(rest.name)"
                case .session(let session): return "session \(session.name)"
                }
            }
            if names != ["rest At the café with Sam"] {
                failures.append("the matched break listed as \(names)")
            }
            if HistoryTree.matchSummary(entries) != "1 break matches" {
                failures.append("the summary read \"\(HistoryTree.matchSummary(entries))\"")
            }
            f.store.setHistoryQuery("")
            f.store.setHistoryWorkType(.breakTime)
            if f.store.historySearchHits(limit: .max).map(\.workType) != [.breakTime] {
                failures.append("the Break category did not list the break")
            }
            return failures
        }
    }
}
