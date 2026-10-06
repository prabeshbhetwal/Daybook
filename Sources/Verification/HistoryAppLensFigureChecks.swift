import Foundation

/// An app's History figures count each second once, every day in the figure
/// gets a line, and the rail says what the app was to a picked session.
enum HistoryAppLensFigureChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An app's History counts a stretch recorded twice, or inside two overlapping sessions, once",
         overlapsCountOnce),
        ("A day an app was only glanced at inside sessions still gets a line under the app's story",
         glancesGetALine),
        ("An app's History says how much of its time predates the accurate record",
         legacyIsSaid),
        ("A search word keeps its + and #, and a dash on its own finds nothing", searchWordsKeepSymbols),
        ("The rail says an app's share, visits and rank in a picked session, and its time by category",
         sessionTileText)
    ]

    /// Monday 31 August 2026, in the Gregorian calendar whatever the region.
    private static let calendar = Calendar.current
    private static let day = calendar.startOfDay(for: SelfTest.gregorian.date(from: DateComponents(year: 2026, month: 8, day: 31))!)

    private static func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private static func qwen(_ start: Date, _ end: Date) -> AppUsageSession {
        AppUsageSession(bundleID: "qwen", appName: "Qwen", start: start, end: end)
    }

    /// Records A (9–10) and B (9:30–10:30) overlap, and C (9:10–9:20) lies
    /// inside A; Qwen is in front 9:40–9:50, recorded twice, and 11:00–11:05
    /// outside, recorded twice. Dia is in front 9:00–9:10, recorded twice.
    private static func overlapsCountOnce() -> [String] {
        var problems: [String] = []
        let threadA = UUID()
        let threadB = UUID()
        let records = [
            SessionRecord(name: "A", workType: .deepWork, start: at(9, 0), end: at(10, 0),
                          workSeconds: 3_600, threadID: threadA),
            SessionRecord(name: "B", workType: .deepWork, start: at(9, 30), end: at(10, 30),
                          workSeconds: 3_600, threadID: threadB),
            SessionRecord(name: "C", workType: .admin, start: at(9, 10), end: at(9, 20),
                          workSeconds: 600, threadID: UUID())
        ]
        let dia = AppUsageSession(bundleID: "dia", appName: "Dia", start: at(9, 0), end: at(9, 10))
        let usage = [qwen(at(9, 40), at(9, 50)), qwen(at(9, 40), at(9, 50)),
                     qwen(at(11, 0), at(11, 5)), qwen(at(11, 1), at(11, 5)), dia, dia]
        let lens = HistoryAppLens.build(bundleID: "qwen", records: records, usage: SortedUsage(usage),
                                        calendar: calendar)
        SelfTest.expectClose(lens.inSession, 600, "Qwen's ten minutes in sessions, once", &problems)
        SelfTest.expectClose(lens.outsideTotal, 300, "Qwen's five minutes outside, once", &problems)
        let listed = lens.sessions.reduce(0) { $0 + $1.seconds }
        SelfTest.expectClose(listed, lens.inSession, "the session cards add up to the time in sessions", &problems)
        expect(lens.sessions.map(\.threadID) == [threadA],
               "the overlap belongs to A, which began first; got \(lens.sessions.count) sessions", &problems)
        SelfTest.expectClose(lens.inSessionByType[.deepWork] ?? -1, 600, "Deep work's share of Qwen", &problems)
        SelfTest.expectClose(lens.sessions.first?.share ?? -1, 600.0 / 3_600, "Qwen's share of A", &problems)
        expect(HistorySearchText.lensTotal(lens) == Tokens.duration(900),
               "the headline reads \(HistorySearchText.lensTotal(lens))", &problems)
        expect(lens.inSessionByType[.admin] == nil, "C, inside A, owns none of Qwen's time", &problems)
        SelfTest.expectClose(lens.alongside.first?.total ?? -1, 600, "Dia beside Qwen, once", &problems)
        SelfTest.expectClose(lens.alongside.first?.share ?? -1, 0.5, "Dia's share beside Qwen", &problems)
        let found = SortedUsage(usage).uniqueUse(within: records.map { DateInterval(start: $0.start, end: $0.end) })
        SelfTest.expectClose(found["qwen"]?.total ?? -1, 600, "a search counts Qwen in the sessions once", &problems)
        return problems
    }

    /// Two sessions, each with Qwen in front for four seconds.
    private static func glancesGetALine() -> [String] {
        var problems: [String] = []
        let records = [
            SessionRecord(name: "A", workType: .deepWork, start: at(9, 0), end: at(10, 0),
                          workSeconds: 3_600, threadID: UUID()),
            SessionRecord(name: "B", workType: .admin, start: at(14, 0), end: at(15, 0),
                          workSeconds: 3_600, threadID: UUID())
        ]
        let usage = [qwen(at(9, 10), at(9, 10, 4)), qwen(at(14, 10), at(14, 10, 4))]
        let lens = HistoryAppLens.build(bundleID: "qwen", records: records, usage: SortedUsage(usage),
                                        calendar: calendar)
        expect(lens.sessions.isEmpty, "no session used Qwen for ten seconds, got \(lens.sessions.count)", &problems)
        expect(lens.days.map(\.day) == [day], "the 31st is in the figure, got \(lens.days.map(\.day))", &problems)
        expect(lens.passing == [HistoryAppLens.PassingUse(day: day, seconds: 8, sessions: 2)],
               "the 31st has its glances, got \(lens.passing)", &problems)
        let line = HistorySearchList.passingLine(lens.passing[0], appName: "Qwen")
        expect(line == "\(Tokens.preciseDuration(8)) of Qwen in passing, across 2 sessions, under 10 seconds in each",
               "the glance line read \"\(line)\"", &problems)
        return problems
    }

    /// The record became accurate at 10 am; Qwen ran 9:30–10:30, outside
    /// every session.
    private static func legacyIsSaid() -> [String] {
        var problems: [String] = []
        let lens = HistoryAppLens.build(bundleID: "qwen", records: [], usage: SortedUsage([qwen(at(9, 30), at(10, 30))]),
                                        calendar: calendar, accurateFrom: at(10, 0))
        SelfTest.expectClose(lens.legacy, 1_800, "the half hour before the record was accurate", &problems)
        let note = HistoryAppLensText.legacyNote(lens)
        expect(note?.hasPrefix(Tokens.duration(1_800) + " of this is from before ") == true,
               "the caveat read \(note ?? "nothing")", &problems)
        let clean = HistoryAppLens.build(bundleID: "qwen", records: [], usage: SortedUsage([qwen(at(10, 30), at(11, 0))]),
                                         calendar: calendar, accurateFrom: at(10, 0))
        expect(HistoryAppLensText.legacyNote(clean) == nil, "use after the epoch needs no caveat", &problems)
        return problems
    }

    private static func searchWordsKeepSymbols() -> [String] {
        var problems: [String] = []
        let cases: [(String, [String])] = [
            ("C++ notes", ["c++", "notes"]), ("c#", ["c#"]), (".NET", [".net"]),
            ("“parser”,", ["parser"]), ("(review)", ["review"]), ("deep - work", ["deep", "work"]),
            ("2026-09-28", ["2026-09-28"])
        ]
        for (query, want) in cases {
            let got = SearchWords.words(in: query)
            expect(got == want, "\"\(query)\" read as \(got), want \(want)", &problems)
        }
        expect(!SearchWords.all(SearchWords.words(in: "c++"), in: SearchWords.fold("Deep work · Parser · Xcode")),
               "C++ no longer finds every session holding a c", &problems)
        return problems
    }

    /// Qwen in three Deep work sessions for 2, 6 and 10 minutes, the 6 in two
    /// visits.
    private static func sessionTileText() -> [String] {
        var problems: [String] = []
        let threads = [UUID(), UUID(), UUID()]
        let records = [9, 11, 14].enumerated().map { index, hour in
            SessionRecord(name: "S\(index)", workType: .deepWork, start: at(hour, 0), end: at(hour + 1, 0),
                          workSeconds: 3_600, threadID: threads[index])
        }
        let usage = [qwen(at(9, 0), at(9, 2)), qwen(at(11, 0), at(11, 3)), qwen(at(11, 30), at(11, 33)),
                     qwen(at(14, 0), at(14, 10))]
        let lens = HistoryAppLens.build(bundleID: "qwen", records: records, usage: SortedUsage(usage),
                                        calendar: calendar)
        guard let middle = lens.sessions.first(where: { $0.threadID == threads[1] }) else {
            return ["the 11 am session was not listed"]
        }
        expect(HistoryAppLensText.visits(middle) == "2 visits · longest \(Tokens.duration(180))",
               "visits read \(HistoryAppLensText.visits(middle))", &problems)
        let comparison = HistoryAppLensText.comparison(middle, in: lens)
        expect(comparison == "About its typical session (\(Tokens.duration(360)), the middle of 3) · 2nd longest",
               "comparison read \(comparison ?? "nothing")", &problems)
        let category = HistoryAppLensText.categoryLine(.deepWork, in: lens)
        expect(category == "All time in \(WorkType.deepWork.displayName) sessions: \(Tokens.duration(1_080)) of "
               + Tokens.duration(1_080), "category read \(category)", &problems)
        expect(HistoryAppLensText.ordinal(11) == "11th" && HistoryAppLensText.ordinal(22) == "22nd",
               "ordinals read \(HistoryAppLensText.ordinal(11)), \(HistoryAppLensText.ordinal(22))", &problems)
        let recent = HistoryAppLensText.recent(lens, today: day, calendar: calendar)
        expect(recent == "Last 7 days \(Tokens.duration(1_080)) · last 30 days \(Tokens.duration(1_080))",
               "recent read \(recent)", &problems)
        return problems
    }
}
