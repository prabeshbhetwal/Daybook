import Foundation

/// What the break log keeps of each day's rhythm: the day is the store's, not
/// the one the log was built in, and a write the disk refused is made again.
enum BreakRhythmLogChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The log counts days in the store's calendar, whatever it was built with", logFollowsStoreCalendar),
        ("A rhythm write the disk refused is tried again, once a minute", refusedRhythmWriteRetried),
    ]

    private static let sydney: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func logFollowsStoreCalendar() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let berlin = BreakRhythmStoreChecks.berlin
            // Wednesday 23:30 and Thursday 00:05 in Berlin are both Thursday in Sydney.
            guard let f = BreakRhythmStoreChecks.make(at: BreakRhythmStoreChecks.oct(21, 23, 30), logCalendar: sydney) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            BreakRhythmStoreChecks.save(f) { $0.weekdays[3] = .off }
            _ = BreakRhythmStoreChecks.collect(f)
            BreakRhythmStoreChecks.use(f, from: BreakRhythmStoreChecks.oct(21, 22, 35), to: BreakRhythmStoreChecks.oct(21, 23, 30))
            f.store.refresh()
            f.clock.value = BreakRhythmStoreChecks.oct(22, 0, 5)
            BreakRhythmStoreChecks.use(f, from: BreakRhythmStoreChecks.oct(21, 23, 30), to: BreakRhythmStoreChecks.oct(22, 0, 5))
            f.store.refresh()
            let days = f.store.breakLog.days
            expect(days.map(\.day) == [berlin.startOfDay(for: BreakRhythmStoreChecks.oct(21, 12, 0)),
                                       berlin.startOfDay(for: BreakRhythmStoreChecks.oct(22, 12, 0))]
                   && days.map { $0.rhythm.preset } == ["off", "steady"],
                   "Wednesday's off and Thursday's steady each keep a row, got \(days.map { $0.rhythm.preset ?? "-" })",
                   &problems)
            expect(days.first?.eyesPrompts == 1, "and Wednesday's Eyes glance counts on Wednesday, got "
                   + "\(days.map(\.eyesPrompts))", &problems)
            return problems
        }
    }

    private static func refusedRhythmWriteRetried() -> [String] {
        var problems: [String] = []
        var refusing = true
        var writes = 0
        var saved: Data?
        let log = BreakLog(directory: SelfTest.scratchDirectory(), calendar: BreakRhythmStoreChecks.berlin,
                           writeOverride: { data in
                               writes += 1
                               if refusing { return "disk full" }
                               saved = data
                               return nil
                           })
        let rhythm = BreakPlan.standard.snapshot
        let start = BreakRhythmStoreChecks.oct(21, 10, 0)
        func note(after seconds: TimeInterval) { log.noteRhythm(rhythm, on: start.addingTimeInterval(seconds)) }
        note(after: 0)
        expect(writes == 1, "the first write is attempted, got \(writes)", &problems)
        note(after: 30)
        expect(writes == 1, "the same rhythm 30 seconds on does not try again, got \(writes)", &problems)
        note(after: 60)
        expect(writes == 2, "a minute on it tries, and is refused again, got \(writes)", &problems)
        note(after: 90)
        expect(writes == 2, "and waits another minute, got \(writes)", &problems)
        refusing = false
        note(after: 120)
        let days = saved.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            .flatMap { $0["days"] as? [Any] }
        expect(writes == 3 && days?.count == 1,
               "once the disk answers the day is saved, got \(writes) writes and \(String(describing: days?.count)) days",
               &problems)
        note(after: 300)
        expect(writes == 3, "and a saved day is left alone, got \(writes)", &problems)
        return problems
    }
}
