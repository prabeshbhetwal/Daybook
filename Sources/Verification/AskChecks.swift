import Foundation

/// Ask Daybook's ranges and wording: a range names the same period History
/// does, and every answer reads the same way whatever lookup produced it.
enum AskChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Each Ask range spans the period History draws, in the period calendar", rangesFollowPeriodCalendar),
        ("Ask reads range names, dates, weekdays and months, and refuses a date the calendar lacks",
         rangeNamesRoundTrip),
        ("Every Ask answer says plainly when nothing was found", nothingFoundIsSaid),
        ("Ask answers print durations as the rest of the app does", figuresAreDurationText),
        ("An Ask answer is cut to the byte cap at a line or clause boundary", outputStaysUnderCap),
        ("The best-hours window reads as a 12-hour range", windowLabels),
        ("Ask opens as a sheet over the story and closes back to nothing", askOpensAsASheet),
        ("The Ask sheet fits inside a small window", askSheetFitsWindow),
    ]

    private static func rangesFollowPeriodCalendar() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current.forPeriods
        func midnight(_ month: Int, _ day: Int, year: Int = 2023) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        let firstDay = calendar.date(from: DateComponents(year: 2023, month: 9, day: 2, hour: 14))!
        let expected: [(AskRange, Date, Date)] = [
            (.today, midnight(11, 15), midnight(11, 16)),
            (.yesterday, midnight(11, 14), midnight(11, 15)),
            (.thisWeek, midnight(11, 13), midnight(11, 20)),
            (.lastWeek, midnight(11, 6), midnight(11, 13)),
            (.thisMonth, midnight(11, 1), midnight(12, 1)),
            (.lastMonth, midnight(10, 1), midnight(11, 1)),
            (.last30Days, midnight(10, 17), midnight(11, 16)),
            (.allTime, midnight(9, 2), midnight(11, 16)),
            (.thisYear, midnight(1, 1), midnight(1, 1, year: 2024)),
            (.lastYear, midnight(1, 1, year: 2022), midnight(1, 1)),
            (.month(year: 2023, month: 8), midnight(8, 1), midnight(9, 1)),
            (.day(year: 2023, month: 10, day: 1), midnight(10, 1), midnight(10, 2)),
            (.year(2021), midnight(1, 1, year: 2021), midnight(1, 1, year: 2022)),
        ]
        for (range, start, end) in expected {
            let interval = range.interval(now: SelfTest.base, firstDay: firstDay, calendar: calendar)
            expect(interval.start == start && interval.end == end,
                   "\(range.rawValue) spans \(interval.start) to \(interval.end), not \(start) to \(end)", &problems)
        }
        return problems
    }

    private static func rangeNamesRoundTrip() -> [String] {
        var problems: [String] = []
        for range in AskRange.allCases {
            expect(AskRange(rawValue: range.rawValue) == range,
                   "\(range.rawValue) does not come back from its own name", &problems)
        }
        expect(Set(AskRange.allCases.map(\.rawValue)).count == AskRange.allCases.count,
               "two ranges share a name", &problems)
        // A date comes back as itself; one the calendar lacks is refused,
        // not rolled into the next month as `Calendar.date(from:)` would.
        let dates: [(String, AskRange?)] = [
            ("2026-10-03", .day(year: 2026, month: 10, day: 3)), ("2026-08", .month(year: 2026, month: 8)),
            ("2025", .year(2025)), ("2024-02-29", .day(year: 2024, month: 2, day: 29)), (" This Year ", .thisYear),
            ("2026-02-31", nil), ("2025-02-29", nil), ("2026-13", nil), ("2026-00", nil), ("0000", nil),
            ("26-10-03", nil), ("nonsense", nil), ("", nil),
        ]
        for (text, want) in dates {
            let got = AskRange(rawValue: text)
            expect(got == want, "“\(text)” reads as \(String(describing: got)), not \(String(describing: want))",
                   &problems)
            if let got { expect(AskRange(rawValue: got.rawValue) == got, "\(got.rawValue) does not round-trip", &problems) }
        }
        // A weekday or month by name is the latest one up to Wed 15 Nov 2023.
        let calendar = Calendar.current.forPeriods
        let named: [(String, AskRange?)] = [
            ("monday", .day(year: 2023, month: 11, day: 13)), ("Wednesday", .day(year: 2023, month: 11, day: 15)),
            ("thursday", .day(year: 2023, month: 11, day: 9)), ("august", .month(year: 2023, month: 8)),
            ("november", .month(year: 2023, month: 11)), ("december", .month(year: 2022, month: 12)),
            ("august 2021", .month(year: 2021, month: 8)), ("last week", .lastWeek), ("2023-10", .month(year: 2023, month: 10)),
            ("mon", .day(year: 2023, month: 11, day: 13)), ("sept", .month(year: 2023, month: 9)),
            ("3 october", .day(year: 2023, month: 10, day: 3)), ("October 3rd, 2021", .day(year: 2021, month: 10, day: 3)),
            ("august 21", .day(year: 2023, month: 8, day: 21)), ("20 november", .day(year: 2022, month: 11, day: 20)),
            ("31 february", nil), ("feb 29", .day(year: 2020, month: 2, day: 29)), ("feb 29 2023", nil),
            ("feb 29 2024", .day(year: 2024, month: 2, day: 29)), ("15 november", .day(year: 2023, month: 11, day: 15)),
            ("16 november", .day(year: 2022, month: 11, day: 16)),
            ("mo", nil), ("monday morning", nil), ("2023-02-29", nil), ("3 4 october", nil),
        ]
        for (text, want) in named {
            let got = AskRange.resolving(text, now: SelfTest.base, calendar: calendar)
            expect(got == want, "“\(text)” resolves to \(String(describing: got)), not \(String(describing: want))",
                   &problems)
        }
        return problems
    }

    private static func nothingFoundIsSaid() -> [String] {
        var problems: [String] = []
        let range = AskRange.thisWeek
        let cases: [(String, String, String)] = [
            ("focus totals", AskFacts.focusTotals(range, words: nil, AskTotals()),
             "No focus recorded this week."),
            ("focus totals for words", AskFacts.focusTotals(range, words: "thesis", AskTotals()),
             "No sessions match “thesis” this week."),
            ("best hours", AskFacts.bestHours(range, span: "This week", window: nil, strongest: nil),
             "Not enough focus this week to tell; it needs at least 30m."),
            ("sessions", AskFacts.sessions(range, words: "thesis", lines: []),
             "No sessions match “thesis” this week."),
            ("every session", AskFacts.sessions(range, words: "", lines: []),
             "No sessions recorded this week."),
            ("comparison", AskFacts.comparison(AskSide(range: range, focused: 0, isCurrent: true),
                                                AskSide(range: .lastWeek, focused: 0), words: nil),
             "Focus this week so far: 0m; last week: 0m. This week so far and last week are level."),
            ("a period still to come", AskFacts.stillToCome(.month(year: 2027, month: 1)),
             "January 2027 is still to come."),
            ("app time", AskFacts.appTime(range, app: (query: "Figma", name: nil, total: 0, sessions: 0), top: []),
             "No app called “Figma” was used this week."),
            ("app time, no app", AskFacts.appTime(range, app: nil, top: []),
             "No app use recorded this week."),
        ]
        for (name, got, want) in cases {
            expect(got == want, "\(name) says “\(got)”, not “\(want)”", &problems)
        }
        let allTime = AskFacts.bestHours(.allTime, span: "All time", window: nil, strongest: nil)
        expect(allTime == "Not enough focus in all your history to tell; it needs at least 30m.",
               "best hours over all time says “\(allTime)”", &problems)
        return problems
    }

    private static func figuresAreDurationText() -> [String] {
        var problems: [String] = []
        let got = AskFacts.focusTotals(.thisWeek, words: nil,
                                       AskTotals(focused: 24_000, sessions: 5, focusedDays: 4,
                                                 best: [AskBest(unit: "day", label: "Tue 14 Nov", focused: 7_500)],
                                                 longest: (name: "Thesis", day: "Tue 14 Nov", worked: 5_400)))
        let want = "This week: 6h 40m focused over 5 sessions on 4 days, an average of 1h 40m on each day with focus; "
            + "the most focused day was Tue 14 Nov, with 2h 5m; "
            + "the longest finished session was Thesis on Tue 14 Nov, 1h 30m."
        expect(got == want, "focus totals say “\(got)”, not “\(want)”", &problems)

        let one = AskFacts.focusTotals(.thisWeek, words: "thesis", AskTotals(focused: 3_600, sessions: 1, focusedDays: 1))
        expect(one == "Sessions matching “thesis” this week: 1h over 1 session on 1 day.",
               "one session on one day says “\(one)”", &problems)

        let parts = AskFacts.focusTotals(.thisWeek, words: nil,
                                         AskTotals(focused: 5_400, sessions: 2, focusedDays: 2,
                                                   parts: (name: "day", items: [(label: "Mon 13 Nov", focused: 3_600),
                                                                                (label: "Tue 14 Nov", focused: 1_800)])))
        expect(parts == "This week: 1h 30m focused over 2 sessions on 2 days, an average of 45m on each day with focus. "
               + "By day: Mon 13 Nov 1h, Tue 14 Nov 30m.",
               "the per-day breakdown says “\(parts)”", &problems)

        let day = AskFacts.focusTotals(.today, words: nil,
                                       AskTotals(focused: 5_400, sessions: 2, focusedDays: 1, firstStart: "9:10am",
                                                 longest: (name: "Thesis", day: "Wed 15 Nov", worked: 3_600)))
        expect(day == "Today: 1h 30m focused over 2 sessions on 1 day; the first session began at 9:10am; "
               + "the longest finished session was Thesis on Wed 15 Nov, 1h.",
               "a day's totals say “\(day)”", &problems)

        let current = AskFacts.focusTotals(.thisMonth, words: nil,
                                           AskTotals(focused: 7_200, sessions: 2, focusedDays: 1,
                                                     best: [AskBest(unit: "day", label: "today (Wed 15 Nov)",
                                                                    focused: 7_200, isCurrent: true)]))
        expect(current == "This month: 2h focused over 2 sessions on 1 day; "
               + "the most focused day so far is today (Wed 15 Nov), with 2h.",
               "a best day still under way says “\(current)”", &problems)

        // 2h 30m against 2h 0m 59s: 29m 1s apart, but 30m between the figures shown.
        let more = AskFacts.comparison(AskSide(range: .thisWeek, focused: 9_000, isCurrent: true, dates: "13 Nov – 19 Nov"),
                                       AskSide(range: .lastWeek, focused: 7_259, dates: "6 Nov – 12 Nov"),
                                       words: "thesis")
        expect(more == "Sessions matching “thesis” this week so far (13 Nov – 19 Nov): 2h 30m; "
               + "last week (6 Nov – 12 Nov): 2h. "
               + "This week so far (13 Nov – 19 Nov) has 30m more than last week (6 Nov – 12 Nov).",
               "a comparison says “\(more)”: its difference must be of the minutes it shows", &problems)
        let less = AskFacts.comparison(AskSide(range: .month(year: 2023, month: 8), focused: 3_600),
                                       AskSide(range: .day(year: 2023, month: 9, day: 3), focused: 7_200), words: nil)
        expect(less == "Focus in August 2023: 1h; on Sun 3 Sep 2023: 2h. August 2023 has 1h less than Sun 3 Sep 2023.",
               "a comparison of named periods says “\(less)”", &problems)

        let hours = AskFacts.bestHours(.thisWeek, span: "This week", window: (startHour: 9, seconds: 7_200),
                                       strongest: "on Tuesdays")
        expect(hours == "This week: most focus 9–11am (2h); strongest on Tuesdays.",
               "best hours say “\(hours)”", &problems)

        let lines = AskFacts.sessions(.thisWeek, words: "thesis",
                                      lines: [AskSessionLine(day: "Tue 14 Nov", time: "2:00pm", name: "Thesis",
                                                             worked: 3_600),
                                              AskSessionLine(day: "Mon 13 Nov", time: "9:00am", name: "Thesis",
                                                             worked: 1_800, note: "outline")])
        expect(lines == "Tue 14 Nov · 2:00pm · Thesis · 1h\nMon 13 Nov · 9:00am · Thesis · 30m · note: outline",
               "session lines say “\(lines)”", &problems)

        let long = AskFacts.sessions(.thisWeek, words: "x",
                                     lines: [AskSessionLine(day: "Tue 14 Nov", time: "", name: "X", worked: 60,
                                                            note: String(repeating: "n", count: 120))])
        expect(long.hasSuffix("note: " + String(repeating: "n", count: 80)),
               "a long note is cut to 80 characters", &problems)

        let found = AskFacts.appTime(.thisWeek, app: (query: "saf", name: "Safari", total: 5_400, sessions: 1),
                                     top: [])
        expect(found == "Safari this week: 1h 30m in front; used in 1 session.",
               "app time says “\(found)”", &problems)

        let top = AskFacts.appTime(.thisWeek, app: nil,
                                   top: (1...6).map { (name: "App\($0)", total: 60.0 * Double($0)) })
        expect(top == "Most-used apps this week: App1 1m, App2 2m, App3 3m, App4 4m, App5 5m.",
               "the top apps say “\(top)”", &problems)
        return problems
    }

    private static func outputStaysUnderCap() -> [String] {
        var problems: [String] = []
        let cap = AskFacts.maximumBytes
        let ellipsis = "…".utf8.count

        // Line break: the answer is exactly the first k whole lines, k the
        // most that leave room for the ellipsis, never a partial line.
        let note = String(repeating: "n", count: 80)
        let hits = (0..<200).map {
            AskSessionLine(day: "Tue 14 Nov", time: "9:00am", name: "Session \($0)", worked: 3_600, note: note)
        }
        let lines = (0..<200).map { "Tue 14 Nov · 9:00am · Session \($0) · 1h · note: \(note)" }
        var kept = 0
        while kept < lines.count, lines[...kept].joined(separator: "\n").utf8.count + ellipsis <= cap { kept += 1 }
        let text = AskFacts.sessions(.thisWeek, words: "session", lines: hits)
        expect(text.utf8.count <= cap, "the answer is \(text.utf8.count) bytes", &problems)
        expect(kept > 0 && kept < lines.count, "the fixture no longer needs a cut at a line break", &problems)
        expect(text == lines[..<kept].joined(separator: "\n") + "…",
               "an over-long list is not cut after its \(kept) whole lines: ends “\(text.suffix(40))”", &problems)

        // Clause break: with no line break, the cut lands on the last "; ".
        let days = (0..<100).map { (label: "Day \($0)", focused: 3_600.0) }
        let clause = AskFacts.focusTotals(.thisWeek, words: nil,
                                          AskTotals(focused: 24_000, sessions: 5, focusedDays: 4,
                                                    best: [AskBest(unit: "day", label: "Tue 14 Nov", focused: 7_500)],
                                                    parts: (name: "day", items: days)))
        expect(clause == "This week: 6h 40m focused over 5 sessions on 4 days, "
               + "an average of 1h 40m on each day with focus…",
               "an over-long total is not cut at its “; ”: “\(clause)”", &problems)

        // A separator that starts just past the kept text still counts: the
        // first two lines are exactly as long as the cap allows with the ellipsis.
        let fits = String(repeating: "a", count: 10) + "\n" + String(repeating: "b", count: cap - ellipsis - 11)
        let edge = AskFacts.capped(fits + "\n" + String(repeating: "c", count: 100))
        expect(edge == fits + "…" && edge.utf8.count == cap,
               "a cut that lands on a line break loses the line before it: ends “\(edge.suffix(20))”", &problems)

        // No separator at all: cut mid-text, still within the cap.
        let name = String(repeating: "x", count: 1_500)
        let bare = AskFacts.sessions(.thisWeek, words: "x",
                                     lines: [AskSessionLine(day: "Tue 14 Nov", time: "", name: name, worked: 60)])
        let bareLine = "Tue 14 Nov · \(name) · 1m"
        expect(bare == String(decoding: bareLine.utf8.prefix(cap - ellipsis), as: UTF8.self) + "…",
               "a single over-long line is not cut at the cap: \(bare.utf8.count) bytes", &problems)

        expect(AskFacts.capped("short") == "short", "a short answer was changed", &problems)
        let multibyte = AskFacts.capped(String(repeating: "é", count: 2_000))
        expect(multibyte.utf8.count <= AskFacts.maximumBytes, "a multibyte answer is over the cap", &problems)
        return problems
    }

    private static func windowLabels() -> [String] {
        var problems: [String] = []
        for (start, label) in [(9, "9–11am"), (11, "11am–1pm"), (0, "12–2am")] {
            let text = AskFacts.bestHours(.thisWeek, span: "This week",
                                          window: (startHour: start, seconds: 3_600), strongest: nil)
            expect(text.contains(label), "a window starting at \(start) reads “\(text)”, not \(label)", &problems)
        }
        return problems
    }

    private static func askOpensAsASheet() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated {
                let navigation = MainWindowModel(store: f.store)
                navigation.openAsk()
                expect(navigation.sheet == .ask, "openAsk left the sheet at \(String(describing: navigation.sheet))", &problems)
                expect(StorySheetKind.ask.title == "Ask Daybook", "the sheet is titled \(StorySheetKind.ask.title)", &problems)
                navigation.closeSheet()
                expect(navigation.sheet == nil, "closeSheet left a sheet showing", &problems)
                expect(navigation.askModel != nil, "closing the sheet dropped the thread", &problems)
            }
        }
    }

    private static func askSheetFitsWindow() -> [String] {
        var problems: [String] = []
        let window = CGSize(width: 600, height: 400)
        let size = SettingsLayout.sheetSize(for: .ask, within: window)
        expect(size.width <= window.width && size.height <= window.height,
               "the Ask sheet is \(size) in a \(window) window", &problems)
        let roomy = SettingsLayout.sheetSize(for: .ask, within: CGSize(width: 1_400, height: 1_000))
        expect(roomy == CGSize(width: 640.zoomed, height: 520.zoomed),
               "the Ask sheet is \(roomy) in a roomy window, not 640 × 520", &problems)
        return problems
    }
}
