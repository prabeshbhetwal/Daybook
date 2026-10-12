import Foundation

/// Name suggestions' store checks added after review, so the earlier suite
/// keeps its numbers and its file stays small: a session begun before
/// yesterday, a 25-hour day, the kept list across a relaunch, and one rename
/// across two days.
extension NameSuggestionStoreChecks {
    static let later: [(String, () -> [String])] = [
        ("A session begun before yesterday is not offered as a clipped piece", beganBeforeYesterday),
        ("Yesterday and the 60-day window start at local midnight around a 25-hour day", longDay),
        ("The kept list survives a relaunch and a malformed value reads as empty", keptRelaunch),
        ("Name it across two days renames every record and Undo restores them", renameAcrossDays),
    ]

    private static func beganBeforeYesterday() -> [String] {
        let (clipped, edge) = (UUID(), UUID())
        return withFixture(records: { days in [
            record(days.at(2, 22), days.at(1, 1), thread: clipped),   // 3h, 1h of it yesterday
            record(days.at(1, 0), days.at(1, 1), thread: edge),       // begins as yesterday does
        ] }, usage: { days in [app("Xcode", days.at(2, 22), 2 * 3_600)] }) { f, _, problems in
            let offered = f.store.nameSuggestionTargets().map(\.threadID)
            expect(offered == [edge], "offered \(offered), not only the one beginning at yesterday 00:00", &problems)
        }
    }

    /// Mon 30 Oct 2023 follows Berlin's 25-hour Sunday, so yesterday is that
    /// day and `today − 86 400 s` would land on 01:00, past a 00:15 session.
    /// Sun 29 Oct itself follows an ordinary Saturday.
    private static func longDay() -> [String] {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        var problems: [String] = []
        for day in [29, 30] {
            let now = calendar.date(from: DateComponents(year: 2023, month: 10, day: day, hour: 12))!
            let (late, early) = (UUID(), UUID())
            problems += withFixture(zone: berlin, now: now, records: { days in
                let window = days.calendar.startOfDay(
                    for: days.calendar.date(byAdding: .day, value: -60, to: days.calendar.startOfDay(for: now))!)
                return [record(days.at(1, 23), days.at(1, 23, 30), thread: late),
                        record(days.at(1, 0, 15), days.at(1, 0, 45), thread: early),
                        record(window.addingTimeInterval(-5_400), window.addingTimeInterval(-3_600), name: "Old"),
                        record(window.addingTimeInterval(1_800), window.addingTimeInterval(3_600), name: "Recent")]
            }) { f, days, problems in
                let want = calendar.date(from: DateComponents(year: 2023, month: 10, day: day - 1))!
                expect(days.at(1, 0) == want, "Oct \(day - 1) 00:00 is \(days.at(1, 0)), not \(want)", &problems)
                let offered = f.store.nameSuggestionTargets()
                expect(offered.map(\.threadID) == [late, early],
                       "Oct \(day): offered \(offered.map { "\($0.start) \($0.worked)s" })", &problems)
                let leads = offered.map { f.store.nameSuggestionLead(for: $0) }
                // 23:00 yesterday is last night's; 00:15 yesterday was two nights ago.
                expect(leads == ["last night's 30m session", "yesterday's 30m session"],
                       "Oct \(day): leads read \(leads)", &problems)
                let names = f.store.earlierSessionNames()
                expect(names == ["Recent"], "Oct \(day): within 60 days of local midnight: \(names)", &problems)
            }
        }
        return problems
    }

    private static func keptRelaunch() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-name-kept-\(UUID().uuidString)"
        defer { MemoryDefaults.remove(named: suite) }
        guard let first = MemoryDefaults.suite(named: suite), let second = MemoryDefaults.suite(named: suite)
        else { return ["could not open \(suite)"] }
        let kept: Set<String> = [UUID().uuidString, UUID().uuidString]
        PersistenceStore(defaults: first).nameSuggestionKept = kept
        let relaunched = PersistenceStore(defaults: second)
        expect(relaunched.nameSuggestionKept == kept, "relaunch read \(relaunched.nameSuggestionKept)", &problems)
        let malformed: [Any] = ["not a list", [1, 2], ["x", 3]]
        for bad in malformed {
            second.set(bad, forKey: "fc.nameSuggestionKept")
            expect(relaunched.nameSuggestionKept.isEmpty, "\(bad) read as \(relaunched.nameSuggestionKept)", &problems)
        }
        return problems
    }

    private static func renameAcrossDays() -> [String] {
        let thread = UUID()
        return withFixture(records: { days in [
            record(days.at(1, 14), days.at(1, 15), thread: thread),
            record(days.at(0, 7), days.at(0, 8), thread: thread),
        ] }) { f, _, problems in
            guard let session = target(f, thread) else { return problems.append("the thread is not offered") }
            expect(session.recordIDs.count == 2, "the session holds \(session.recordIDs.count) records", &problems)
            expect(f.store.acceptNameSuggestion("Daybook", for: session), "Name it failed", &problems)
            let named = f.engine.archive.records.map(\.name)
            expect(named == ["Daybook", "Daybook"], "records carry \(named)", &problems)
            guard let correction = f.store.lastCorrection else { return problems.append("no correction to undo") }
            expect(f.store.undoCorrection(expectedID: correction.id), "Undo failed", &problems)
            let undone = f.engine.archive.records.map(\.name)
            expect(undone == ["", ""], "after Undo records carry \(undone)", &problems)
        }
    }
}
