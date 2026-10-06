import Foundation

/// A picked app's headline facts in History: when it was first used and its
/// recent totals follow the calendar day it was in front, while its day count
/// matches the day lines listed; time in a session is not called focus, its
/// share is of the session's recorded time; and the total, its parts and the
/// subtitle print to one precision.
enum HistoryLensFactChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An app's first-used day and recent totals follow the calendar day it was in front",
         calendarFacts),
        ("An app used during a session's pause is not called focus, and its share is of the recorded session",
         pausedUseIsNotFocus),
        ("An app's total, its parts and its subtitle print to one precision", onePrecision)
    ]

    /// Wednesday 15 July 2026, far from any change of clocks, in an explicit
    /// Gregorian calendar in the local zone, which the date text also uses.
    private static let calendar = SelfTest.gregorian
    private static let day = calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!)

    private static func at(_ hour: Int, _ minute: Int, _ second: Int = 0, dayOffset: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: dayOffset, to: day)!
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: base)!
    }

    private static func lens(_ records: [SessionRecord], _ qwen: [(Date, Date)]) -> HistoryAppLens {
        let usage = qwen.map { AppUsageSession(bundleID: "qwen", appName: "Qwen", start: $0.0, end: $0.1) }
        return HistoryAppLens.build(bundleID: "qwen", records: records, usage: SortedUsage(usage), calendar: calendar)
    }

    /// A session from 11:30 pm on the 15th to 12:30 am on the 16th.
    private static func calendarFacts() -> [String] {
        var problems: [String] = []
        let late = SessionRecord(name: "Late", workType: .deepWork, start: at(23, 30),
                                 end: at(0, 30, dayOffset: 1), workSeconds: 3_600)
        // Qwen 11:45 pm to 12:15 am: the bar stays on the 15th, and the week
        // from the 16th holds the quarter hour after midnight.
        let across = lens([late], [(at(23, 45), at(0, 15, dayOffset: 1))])
        expect(across.days.map(\.day) == [day], "the bar is under the start day, got \(across.days.map(\.day))", &problems)
        let recent = HistoryAppLensText.recent(across, today: at(12, 0, dayOffset: 7), calendar: calendar)
        let want = "Last 7 days \(HistorySessionRow.figure(900)) · last 30 days \(HistorySessionRow.figure(1_800))"
        expect(recent == want, "recent read \"\(recent)\", want \"\(want)\"", &problems)
        let both = HistorySearchText.lensSentence(appName: "Qwen", lens: across).sentence
        // The day count is the day lines below it: one, the session's.
        expect(both == "You used Qwen for \(Tokens.duration(1_800)) on 1 day.", "the headline read \"\(both)\"", &problems)

        // Qwen only after midnight in the session, then 10 to 10:05 am
        // outside it: one calendar day, the 16th, though two bars.
        let after = lens([late], [(at(0, 5, dayOffset: 1), at(0, 15, dayOffset: 1)),
                                  (at(10, 0, dayOffset: 1), at(10, 5, dayOffset: 1))])
        expect(after.days.map(\.day) == [day, at(0, 0, dayOffset: 1)],
               "the bars are the 15th and the 16th, got \(after.days.map(\.day))", &problems)
        let eyebrow = HistorySearchText.eyebrow(filter: HistoryFilter(), appName: "Qwen", lens: after)
        let first = DateFormats.australian("d MMMM yyyy").string(from: at(0, 0, dayOffset: 1))
        expect(eyebrow == "Qwen · first used \(first)", "the eyebrow read \"\(eyebrow)\"", &problems)
        let one = HistorySearchText.lensSentence(appName: "Qwen", lens: after).sentence
        expect(one == "You used Qwen for \(Tokens.duration(900)) on 2 days.", "the headline read \"\(one)\"", &problems)
        return problems
    }

    /// A two-hour session from 9 am paused for its second hour, with Qwen in
    /// front only during the pause.
    private static func pausedUseIsNotFocus() -> [String] {
        var problems: [String] = []
        let paused = SessionRecord(name: "Paused", workType: .deepWork, start: at(9, 0), end: at(11, 0),
                                   workSeconds: 3_600, pausedSpans: [DateInterval(start: at(10, 0), end: at(11, 0))])
        let pausedLens = lens([paused], [(at(10, 0), at(11, 0))])
        guard let use = pausedLens.sessions.first else { return ["the paused session was not listed"] }
        SelfTest.expectClose(use.seconds, 3_600, "Qwen's hour inside the session", &problems)
        SelfTest.expectClose(use.share, 0.5, "Qwen's hour of the two-hour session, all of it paused", &problems)
        let facts = HistorySearchText.lensFacts(pausedLens)
        expect(facts.first == "\(Tokens.duration(3_600)) in 1 session",
               "the subtitle read \(facts.first ?? "nothing")", &problems)
        expect(!facts.contains { $0.contains("focus") }, "the subtitle called paused use focus: \(facts)", &problems)

        // Worked 2 to 2:30 pm, paused to 3; Qwen 2:20 to 2:40 is ten minutes
        // of each.
        let pausedHalf = [DateInterval(start: at(14, 30), end: at(15, 0))]
        let half = SessionRecord(name: "Half", workType: .deepWork, start: at(14, 0), end: at(15, 0),
                                 workSeconds: 1_800, pausedSpans: pausedHalf)
        let mixed = lens([half], [(at(14, 20), at(14, 40))])
        SelfTest.expectClose(mixed.sessions.first?.share ?? -1, 1_200.0 / 3_600, "Qwen's share of the recorded hour",
                             &problems)
        // With no record of when it paused, the share is the same.
        let legacy = SessionRecord(name: "Old", workType: .deepWork, start: at(14, 0), end: at(15, 0),
                                   workSeconds: 1_800)
        SelfTest.expectClose(lens([legacy], [(at(14, 20), at(14, 40))]).sessions.first?.share ?? -1, 1_200.0 / 3_600,
                             "Qwen's share where the pauses are unknown", &problems)
        // One thread: 4 to 5 pm with a pause saved as running to 6, then 5:30
        // to 6:30 unpaused with Qwen throughout. The first record's pause
        // ends with it, and the share is of both records' own hours.
        let thread = UUID()
        let before = SessionRecord(name: "Before", workType: .deepWork, start: at(16, 0), end: at(17, 0),
                                   workSeconds: 1_800, threadID: thread,
                                   pausedSpans: [DateInterval(start: at(16, 30), end: at(18, 0))])
        let next = SessionRecord(name: "Next", workType: .deepWork, start: at(17, 30), end: at(18, 30),
                                 workSeconds: 3_600, threadID: thread)
        SelfTest.expectClose(lens([before, next], [(at(17, 30), at(18, 30))]).sessions.first?.share ?? -1,
                             3_600.0 / 7_200, "Qwen's share across a thread whose first pause was saved long",
                             &problems)
        return problems
    }

    /// A 9 to 10 am session; Qwen in front inside it and at 11 am outside.
    private static func onePrecision() -> [String] {
        var problems: [String] = []
        let session = SessionRecord(name: "Short", workType: .deepWork, start: at(9, 0), end: at(10, 0),
                                    workSeconds: 3_600)
        let figure = HistorySessionRow.figure
        // 50 seconds each: neither part reaches a minute, so all print to
        // the second, the total floored to the minute as History's rows are.
        let fifty = lens([session], [(at(9, 10), at(9, 10, 50)), (at(11, 0), at(11, 0, 50))])
        let parts = HistorySearchText.lensParts(fifty)
        expect(parts == (figure(50), figure(50), figure(100)), "50s and 50s printed \(parts)", &problems)
        let subtitle = HistorySearchText.lensFacts(fifty).first ?? "nothing"
        expect(subtitle == "\(figure(50)) in 1 session", "the subtitle read \(subtitle)", &problems)
        let category = HistoryAppLensText.categoryLine(.deepWork, in: fifty)
        expect(category == "All time in \(WorkType.deepWork.displayName) sessions: \(figure(50)) of \(figure(100))",
               "the category line read \(category)", &problems)
        // Half a second, all of it: the total is not printed as none.
        let blink = HistorySearchText.lensTotal(lens([], [(at(11, 0), at(11, 0).addingTimeInterval(0.5))]))
        expect(blink == figure(0.5), "half a second's total read \(blink)", &problems)
        // 20 and 30 seconds: the total is the sum of the printed parts.
        let small = HistorySearchText.lensParts(lens([session], [(at(9, 10), at(9, 10, 20)),
                                                                 (at(11, 0), at(11, 0, 30))]))
        expect(small == (figure(20), figure(30), figure(50)), "20s and 30s printed \(small)", &problems)
        // 4m 59s and 3m 59s: whole minutes, and the total is still their sum.
        let whole = HistorySearchText.lensParts(lens([session], [(at(9, 10), at(9, 14, 59)),
                                                                 (at(11, 0), at(11, 3, 59))]))
        expect(whole == (Tokens.duration(240), Tokens.duration(180), Tokens.duration(420)),
               "4m 59s and 3m 59s printed \(whole)", &problems)
        return problems
    }
}
