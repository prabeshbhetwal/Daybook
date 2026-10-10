import Foundation

/// History's open path when the record moves under it: an open place whose
/// days have left the record folds away, never opening a row of no days.
enum HistoryOpenPathChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Removing the first day's only session folds that day in History instead of opening an empty place",
         removedFirstDayFolds),
    ]

    private static func removedFirstDayFolds() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = SessionStore.historyCalendar
            // A Sunday and the Monday after it in one month, and today a week
            // later: the top is the month and its rows are Monday-first weeks,
            // so the Sunday's week ends where the Monday's begins.
            let anchor = calendar.date(from: DateComponents(year: 2025, month: 11, day: 15, hour: 12))!
            let monday = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
            let sunday = calendar.date(byAdding: .day, value: -1, to: monday)!
            let today = calendar.date(byAdding: .day, value: 9, to: monday)!
            func at(_ day: Date, _ hour: Int) -> Date {
                calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            }
            let clock = TestClock(at(today, 12))
            let suite = "fc-selftest-history-open-path-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no in-memory preferences"] }
            defer { MemoryDefaults.remove(named: suite) }
            let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
            let usage = AppUsageArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "com.example.daybook", schedulesDwell: false,
                                       now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: AppUsageTracker(archive: usage, ownBundleID: "com.example.daybook",
                                                  idle: .disabled, now: { clock.value }),
                         usage: usage)
            for day in [sunday, monday] {
                archive.append(SessionRecord(name: "Writing", workType: .deepWork, start: at(day, 10), end: at(day, 11),
                                             workSeconds: 3_600, detectedApp: "com.example.code", threadID: UUID()))
            }
            store.refresh()
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            navigation.openHistory(day: sunday)
            expect(navigation.historyOpen.last == HistoryPlace(level: .day,
                                                               span: DateInterval(start: sunday, end: monday)),
                   "Jump to date should open the Sunday, opened \(describe(navigation.historyOpen))", &problems)

            let session = SessionDigest.entries(records: archive.records(on: sunday), running: nil,
                                                now: clock.value, day: sunday)
                .compactMap { entry -> DaySession? in
                    if case .session(let session) = entry { return session }
                    return nil
                }.first
            guard let session, store.removeSession(session) else {
                return problems + ["the Sunday's session was not removed: \(store.correctionError ?? "no session")"]
            }
            expect(store.historyTop().firstDay == monday,
                   "the record should now start on the Monday, starts \(store.historyTop().firstDay)", &problems)
            // What History runs when its top changes.
            navigation.reconcileHistory()
            let open = navigation.historyOpen
            expect(open.isEmpty, "the removed Sunday should fold away, History opened \(describe(open))", &problems)
            expect(navigation.historyFocus == nil,
                   "the keyboard should leave the folded Sunday, stands on \(String(describing: navigation.historyFocus))",
                   &problems)
            return problems
        }
    }

    private static func describe(_ places: [HistoryPlace]) -> String {
        "[" + places.map { "\($0.level) \($0.span.start)–\($0.span.end) (\(Int($0.span.duration)) s)" }
            .joined(separator: ", ") + "]"
    }
}
