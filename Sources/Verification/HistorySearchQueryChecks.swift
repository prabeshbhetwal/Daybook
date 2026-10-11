import Foundation

/// History's search box reads periods, weekdays, lengths and exact app or
/// category names out of what is typed (`SearchQuery`), and leaves every other
/// word as it was. "Now" is `SelfTest.base`, Wednesday 15 November 2023, and
/// every expected span is built through the period calendar.
enum HistorySearchQueryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The search box reads periods, weekdays, lengths and names out of free text", grammarRows),
        ("The longest phrase wins and the rest stays as words", longestMatch),
        ("Quoted words and a single weekday stay words", literalWords),
        ("Names match only with their own capital", nameCase),
        ("Periods intersect, and disjoint ones say No overlap", intersection),
        ("A week just after midnight on Monday is the week before", mondayMidnight),
        ("A week holding a daylight-saving change keeps its seven days", dstWeek),
        ("Number words read in counts and lengths", numberWords),
    ]

    // MARK: Grammar

    private static func grammarRows() -> [String] {
        var problems: [String] = []
        let periodRows: [(String, Row)] = [
            ("today", Row(span: span(11, 15, 11, 16), labels: ["Today · Wed 15 Nov"])),
            ("yesterday", Row(span: span(11, 14, 11, 15), labels: ["Yesterday · Tue 14 Nov"])),
            ("this week", Row(span: span(11, 13, 11, 20), labels: ["This week · 13–19 Nov"])),
            ("Last Week", Row(span: span(11, 6, 11, 13), labels: ["Last week · 6–12 Nov"])),
            ("this month", Row(span: span(11, 1, 12, 1), labels: ["This month · 1–30 Nov"])),
            ("last month", Row(span: span(10, 1, 11, 1), labels: ["Last month · 1–31 Oct"])),
            ("this year", Row(span: span(1, 1, 1, 1, y2: 2024), labels: ["This year · 1 Jan – 31 Dec"])),
            ("last year", Row(span: span(1, 1, 1, 1, y1: 2022, y2: 2023), labels: ["Last year · 1 Jan – 31 Dec 2022"])),
            ("the week before last", Row(span: span(10, 30, 11, 6), labels: ["Week before last · 30 Oct – 5 Nov"])),
            ("the month before last", Row(span: span(9, 1, 10, 1), labels: ["Month before last · 1–30 Sep"])),
            ("3 days ago", Row(span: span(11, 12, 11, 13), labels: ["3 days ago · Sun 12 Nov"])),
            ("2 weeks ago", Row(span: span(10, 30, 11, 6), labels: ["2 weeks ago · 30 Oct – 5 Nov"])),
            ("3 months ago", Row(span: span(8, 1, 9, 1), labels: ["3 months ago · 1–31 Aug"])),
            ("last 7 days", Row(span: span(11, 9, 11, 16), labels: ["Last 7 days · 9–15 Nov"])),
            ("last 2 weeks", Row(span: span(11, 2, 11, 16), labels: ["Last 2 weeks · 2–15 Nov"])),
            ("last fortnight", Row(span: span(11, 2, 11, 16), labels: ["Last fortnight · 2–15 Nov"])),
            ("past fortnight", Row(span: span(11, 2, 11, 16), labels: ["Past fortnight · 2–15 Nov"])),
            ("the past fortnight", Row(span: span(11, 2, 11, 16), labels: ["Past fortnight · 2–15 Nov"])),
            ("the fortnight before last", Row(span: span(10, 19, 11, 2), labels: ["Fortnight before last · 19 Oct – 1 Nov"])),
            ("fortnight before last", Row(span: span(10, 19, 11, 2), labels: ["Fortnight before last · 19 Oct – 1 Nov"])),
            ("a fortnight ago", Row(span: span(10, 30, 11, 6), labels: ["A fortnight ago · 30 Oct – 5 Nov"])),
            ("2 fortnights ago", Row(span: span(10, 16, 10, 23), labels: ["2 fortnights ago · 16–22 Oct"])),
            ("3 days back", Row(span: span(11, 12, 11, 13), labels: ["3 days back · Sun 12 Nov"])),
            ("a week back", Row(span: span(11, 6, 11, 13), labels: ["A week back · 6–12 Nov"])),
            ("a fortnight back", Row(span: span(10, 30, 11, 6), labels: ["A fortnight back · 30 Oct – 5 Nov"])),
            ("a month back", Row(span: span(10, 1, 11, 1), labels: ["A month back · 1–31 Oct"])),
            ("three weeks back", Row(span: span(10, 23, 10, 30), labels: ["Three weeks back · 23–29 Oct"])),
            ("two months back", Row(span: span(9, 1, 10, 1), labels: ["Two months back · 1–30 Sep"])),
            ("last weekend", Row(span: span(11, 11, 11, 13), labels: ["Last weekend · 11–12 Nov"])),
            ("this past weekend", Row(span: span(11, 11, 11, 13), labels: ["This past weekend · 11–12 Nov"])),
            ("the past weekend", Row(span: span(11, 11, 11, 13), labels: ["Past weekend · 11–12 Nov"])),
            ("the weekend before last", Row(span: span(11, 4, 11, 6), labels: ["Weekend before last · 4–5 Nov"])),
            ("weekend before last", Row(span: span(11, 4, 11, 6), labels: ["Weekend before last · 4–5 Nov"])),
            ("September", Row(span: span(9, 1, 10, 1), labels: ["September 2023"])),
            ("Sept 2022", Row(span: span(9, 1, 10, 1, y1: 2022, y2: 2022), labels: ["September 2022"])),
            ("3 October", Row(span: span(10, 3, 10, 4), labels: ["Tue 3 Oct 2023"])),
            ("October 3rd", Row(span: span(10, 3, 10, 4), labels: ["Tue 3 Oct 2023"])),
            ("3 Oct 2022", Row(span: span(10, 3, 10, 4, y1: 2022, y2: 2022), labels: ["Mon 3 Oct 2022"])),
            ("2022", Row(span: span(1, 1, 1, 1, y1: 2022, y2: 2023), labels: ["2022"])),
            ("dec", Row(span: span(12, 1, 1, 1, y1: 2022, y2: 2023), labels: ["December 2022"])),
            ("3 Dec", Row(span: span(12, 3, 12, 4, y1: 2022, y2: 2022), labels: ["Sat 3 Dec 2022"])),
        ]
        for (text, row) in periodRows { verify(text, row, &problems) }

        let weekdayRows: [(String, Row)] = [
            ("Mondays", Row(weekdays: [2], labels: ["Mondays"])),
            ("on Mondays", Row(weekdays: [2], labels: ["Mondays"])),
            ("mons", Row(weekdays: [2], labels: ["Mondays"])),
            ("Mondays and Fridays", Row(weekdays: [2, 6], labels: ["Mondays, Fridays"])),
            ("on Mondays, Fridays", Row(weekdays: [2, 6], labels: ["Mondays, Fridays"])),
            ("Tuesdays, Thursdays and Saturdays", Row(weekdays: [3, 5, 7], labels: ["Tuesdays, Thursdays, Saturdays"])),
            ("weekends", Row(weekdays: [1, 7], labels: ["Weekends"])),
            ("weekdays", Row(weekdays: [2, 3, 4, 5, 6], labels: ["Weekdays"])),
            ("Sundays", Row(weekdays: [1], labels: ["Sundays"])),
        ]
        for (text, row) in weekdayRows { verify(text, row, &problems) }

        let lengthRows: [(String, Row)] = [
            ("over 1h", Row(min: 3_600, labels: ["Over 1h"])),
            ("over 1 h", Row(min: 3_600, labels: ["Over 1h"])),
            ("longer than 1 hour", Row(min: 3_600, labels: ["Over 1h"])),
            ("more than 90m", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("at least 90 min", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("over 1h 30m", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("over 1.5h", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("under 20m", Row(max: 1_200, labels: ["Under 20m"])),
            ("shorter than 20 minutes", Row(max: 1_200, labels: ["Under 20m"])),
            ("less than 1.5h", Row(max: 5_400, labels: ["Under 1h 30m"])),
            ("at most an hour", Row(max: 3_600, labels: ["Under 1h"])),
            ("between 30m and 1h", Row(min: 1_800, max: 3_600, labels: ["30m–1h"])),
            ("over 1 hour 30 minutes", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("longer than an hour and a half", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("over a hour and a half", Row(min: 5_400, labels: ["Over 1h 30m"])),
            ("under half an hour", Row(max: 1_800, labels: ["Under 30m"])),
            ("at least half hour", Row(min: 1_800, labels: ["Over 30m"])),
            ("over two and a half hours", Row(min: 9_000, labels: ["Over 2h 30m"])),
            ("over 2 and a half hour", Row(min: 9_000, labels: ["Over 2h 30m"])),
            ("over 2 hours and a half", Row(min: 9_000, labels: ["Over 2h 30m"])),
        ]
        for (text, row) in lengthRows { verify(text, row, &problems) }

        let deep = WorkType.deepWork
        let nameRows: [(String, Row)] = [
            ("Xcode", Row(app: "com.apple.dt.Xcode", labels: ["Xcode"])),
            ("Visual Studio Code", Row(app: "com.microsoft.VSCode", labels: ["Visual Studio Code"])),
            (deep.displayName, Row(type: deep, labels: [deep.displayName])),
        ]
        for (text, row) in nameRows { verify(text, row, types: [deep, .meetings], &problems) }

        verify("Thesis last week on Mondays over 1h",
               Row(span: span(11, 6, 11, 13), weekdays: [2], min: 3_600, leftover: "Thesis",
                   labels: ["Last week · 6–12 Nov", "Mondays", "Over 1h"]), &problems)
        let text = "Thesis last week on Mondays over 1h"
        let parsed = SearchQuery.parse(text, now: SelfTest.base, calendar: periods, apps: apps, categories: [])
        expect(parsed.phrases.map { String(text[$0.range]) } == ["last week", "on Mondays", "over 1h"],
               "phrase ranges cover the typed phrases, got \(parsed.phrases.map { String(text[$0.range]) })", &problems)
        expect(parsed.phrases.map(\.kind) == [.period, .weekdays, .length], "phrase kinds were \(parsed.phrases.map(\.kind))",
               &problems)
        return problems
    }

    // MARK: Longest match, quotes, case

    private static func longestMatch() -> [String] {
        var problems: [String] = []
        verify("the week before last", Row(span: span(10, 30, 11, 6), labels: ["Week before last · 30 Oct – 5 Nov"]), &problems)
        verify("week before last", Row(span: span(10, 30, 11, 6), labels: ["Week before last · 30 Oct – 5 Nov"]), &problems)
        verify("Sprint 42 over 1h", Row(min: 3_600, leftover: "Sprint 42", labels: ["Over 1h"]), &problems)
        verify("Sprint 42 days ago", Row(span: span(10, 4, 10, 5), leftover: "Sprint",
                                         labels: ["42 days ago · Wed 4 Oct"]), &problems)
        verify("over budget", Row(leftover: "over budget"), &problems)
        verify("notes on Mondays and Fridays", Row(weekdays: [2, 6], leftover: "notes",
                                                  labels: ["Mondays, Fridays"]), &problems)
        verify("1 hour ago", Row(leftover: "1 hour ago"), &problems)
        // A fortnight is two weeks, built through the calendar rather than from the dates above.
        let tomorrow = periods.date(byAdding: .day, value: 1, to: periods.startOfDay(for: SelfTest.base))!
        func daysBefore(_ days: Int) -> Date { periods.date(byAdding: .day, value: -days, to: tomorrow)! }
        let last14 = DateInterval(start: daysBefore(14), end: tomorrow)
        verify("past fortnight", Row(span: last14, labels: ["Past fortnight · 2–15 Nov"]), &problems)
        verify("the fortnight before last", Row(span: DateInterval(start: daysBefore(28), end: daysBefore(14)),
                                               labels: ["Fortnight before last · 19 Oct – 1 Nov"]), &problems)
        verify("parser stuff from last fortnight", Row(span: last14, leftover: "parser stuff from",
                                                       labels: ["Last fortnight · 2–15 Nov"]), &problems)
        // The plural "weekends" is still the weekday set, and a weekend phrase is a period.
        verify("last weekends", Row(weekdays: [1, 7], leftover: "last", labels: ["Weekends"]), &problems)
        verify("weekends last weekend", Row(span: span(11, 11, 11, 13), weekdays: [1, 7],
                                            labels: ["Weekends", "Last weekend · 11–12 Nov"]), &problems)
        verify("weekend", Row(leftover: "weekend"), &problems)
        verify("this weekend", Row(leftover: "this weekend"), &problems)
        verify("a fortnight", Row(leftover: "a fortnight"), &problems)
        let text = "the weekend before last"
        let parsed = SearchQuery.parse(text, now: SelfTest.base, calendar: periods, apps: apps, categories: [])
        expect(parsed.phrases.map(\.kind) == [.period] && parsed.phrases.map { String(text[$0.range]) } == [text],
               "\"\(text)\" is one period phrase, got \(parsed.phrases.map(\.kind))", &problems)
        return problems
    }

    private static func literalWords() -> [String] {
        var problems: [String] = []
        verify("\"Mondays standup\"", Row(leftover: "\"Mondays standup\""), &problems)
        verify("\"Over budget\"", Row(leftover: "\"Over budget\""), &problems)
        verify("Thesis \"last week\" notes", Row(leftover: "Thesis \"last week\" notes"), &problems)
        verify("\"Xcode\"", Row(leftover: "\"Xcode\""), &problems)
        verify("\"last week", Row(leftover: "\"last week"), &problems)
        verify("\"over 1h\" over 2h", Row(min: 7_200, leftover: "\"over 1h\"", labels: ["Over 2h"]), &problems)
        verify("Monday", Row(leftover: "Monday"), &problems)
        verify("on Monday", Row(leftover: "on Monday"), &problems)
        return problems
    }

    private static func nameCase() -> [String] {
        var problems: [String] = []
        verify("Notes", Row(app: "com.apple.Notes", labels: ["Notes"]), &problems)
        verify("notes", Row(leftover: "notes"), &problems)
        verify("Thesis notes", Row(leftover: "Thesis notes"), &problems)
        verify("Visual studio code", Row(app: "com.microsoft.VSCode", labels: ["Visual Studio Code"]), &problems)
        verify("visual Studio Code", Row(leftover: "visual Studio Code"), &problems)
        verify("Notes Xcode", Row(app: "com.apple.Notes", leftover: "Xcode", labels: ["Notes"]), &problems)
        let deep = WorkType.deepWork
        let name = deep.displayName
        expect(name.lowercased() != name, "the default category name has a capital, so this check can tell cases apart",
               &problems)
        verify(name, Row(type: deep, labels: [name]), types: [deep], &problems)
        verify(name.lowercased(), Row(leftover: name.lowercased()), types: [deep], &problems)
        return problems
    }

    // MARK: Periods together

    private static func intersection() -> [String] {
        var problems: [String] = []
        let lastYear = "Last year · 1 Jan – 31 Dec 2022"
        let sep22 = span(9, 1, 10, 1, y1: 2022, y2: 2022)
        verify("September last year", Row(span: sep22, labels: ["September 2022", lastYear]), &problems)
        verify("last year September", Row(span: sep22, labels: [lastYear, "September 2022"]), &problems)
        verify("3 October last year", Row(span: span(10, 3, 10, 4, y1: 2022, y2: 2022),
                                          labels: ["Mon 3 Oct 2022", lastYear]), &problems)
        verify("October last month", Row(span: span(10, 1, 11, 1), labels: ["October 2023", "Last month · 1–31 Oct"]),
               &problems)
        verify("November last week", Row(span: span(11, 6, 11, 13), labels: ["November 2023", "Last week · 6–12 Nov"]),
               &problems)
        verify("this week today", Row(span: span(11, 15, 11, 16),
                                      labels: ["This week · 13–19 Nov", "Today · Wed 15 Nov"]), &problems)
        verify("today last week", Row(labels: ["Today · Wed 15 Nov", "Last week · 6–12 Nov"], noOverlap: true), &problems)
        verify("last week this week", Row(labels: ["Last week · 6–12 Nov", "This week · 13–19 Nov"], noOverlap: true),
               &problems)
        verify("yesterday today", Row(labels: ["Yesterday · Tue 14 Nov", "Today · Wed 15 Nov"], noOverlap: true),
               &problems)
        verify("December last week", Row(labels: ["December 2022", "Last week · 6–12 Nov"], noOverlap: true), &problems)
        verify("over 30m under 2h", Row(min: 1_800, max: 7_200, labels: ["Over 30m", "Under 2h"]), &problems)
        verify("Mondays Fridays", Row(weekdays: [2, 6], labels: ["Mondays", "Fridays"]), &problems)
        return problems
    }

    // MARK: Midnight, years and daylight saving

    private static func mondayMidnight() -> [String] {
        var problems: [String] = []
        for zone in ["Australia/Sydney", "Europe/Berlin", "America/Los_Angeles", "UTC"] {
            var base = Calendar(identifier: .gregorian)
            base.timeZone = TimeZone(identifier: zone)!
            let calendar = base.forPeriods
            let now = calendar.date(from: DateComponents(year: 2023, month: 11, day: 13, hour: 0, minute: 30))!
            let last = SearchQuery.parse("last week", now: now, calendar: calendar, apps: [:], categories: [])
            expect(last.span == span(11, 6, 11, 13, in: calendar), "\(zone): last week at 00:30 on Monday is \(String(describing: last.span))", &problems)
            expect(last.phrases.map(\.label) == ["Last week · 6–12 Nov"], "\(zone): chips \(last.phrases.map(\.label))", &problems)
            let this = SearchQuery.parse("this week", now: now, calendar: calendar, apps: [:], categories: [])
            expect(this.span == span(11, 13, 11, 20, in: calendar), "\(zone): this week at 00:30 on Monday is \(String(describing: this.span))", &problems)
        }
        return problems
    }

    private static func dstWeek() -> [String] {
        var problems: [String] = []
        // Sydney clocks went forward on Sunday 1 Oct 2023, Berlin's back on Sunday 29 Oct.
        let cases: [(zone: String, now: [Int], text: String, from: [Int], to: [Int], hours: Double, label: String)] = [
            ("Australia/Sydney", [9, 27], "this week", [9, 25], [10, 2], 167, "This week · 25 Sep – 1 Oct"),
            ("Australia/Sydney", [10, 3], "last week", [9, 25], [10, 2], 167, "Last week · 25 Sep – 1 Oct"),
            ("Australia/Sydney", [10, 3], "last 7 days", [9, 27], [10, 4], 167, "Last 7 days · 27 Sep – 3 Oct"),
            ("Europe/Berlin", [10, 25], "this week", [10, 23], [10, 30], 169, "This week · 23–29 Oct"),
            ("Europe/Berlin", [10, 31], "last week", [10, 23], [10, 30], 169, "Last week · 23–29 Oct"),
            ("Europe/Berlin", [10, 31], "last 7 days", [10, 25], [11, 1], 169, "Last 7 days · 25–31 Oct"),
            ("Europe/Berlin", [10, 31], "last weekend", [10, 28], [10, 30], 49, "Last weekend · 28–29 Oct"),
            ("Europe/Berlin", [10, 31], "last fortnight", [10, 18], [11, 1], 337, "Last fortnight · 18–31 Oct"),
            ("Australia/Sydney", [10, 3], "last weekend", [9, 30], [10, 2], 47, "Last weekend · 30 Sep – 1 Oct"),
        ]
        for item in cases {
            var base = Calendar(identifier: .gregorian)
            base.timeZone = TimeZone(identifier: item.zone)!
            let calendar = base.forPeriods
            let now = calendar.date(from: DateComponents(year: 2023, month: item.now[0], day: item.now[1], hour: 9))!
            let expected = span(item.from[0], item.from[1], item.to[0], item.to[1], in: calendar)
            let got = SearchQuery.parse(item.text, now: now, calendar: calendar, apps: [:], categories: [])
            let tag = "\(item.zone) \(item.text)"
            expect(got.span == expected, "\(tag): span \(String(describing: got.span)), not \(expected)", &problems)
            expect(got.span.map { $0.duration / 3_600 } == item.hours, "\(tag): spans \(String(describing: got.span.map { $0.duration / 3_600 })) hours, not \(item.hours)", &problems)
            expect(got.phrases.map(\.label) == [item.label], "\(tag): chip \(got.phrases.map(\.label)), not \(item.label)", &problems)
        }
        // A span in another year says so: a week wholly in last year, and one that crosses New Year.
        var calendar = periods
        calendar.timeZone = SelfTest.gregorian.timeZone
        let january = calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 9))!
        let years: [(String, String)] = [("last week", "Last week · 25–31 Dec 2023"),
                                         ("last 7 days", "Last 7 days · 27 Dec 2023 – 2 Jan 2024"),
                                         ("yesterday", "Yesterday · Mon 1 Jan")]
        for (text, label) in years {
            let got = SearchQuery.parse(text, now: january, calendar: calendar, apps: [:], categories: [])
            expect(got.phrases.map(\.label) == [label], "\(text) in January reads \(got.phrases.map(\.label)), not \(label)", &problems)
        }
        return problems
    }

    private static func numberWords() -> [String] {
        var problems: [String] = []
        verify("two weeks ago", Row(span: span(10, 30, 11, 6), labels: ["Two weeks ago · 30 Oct – 5 Nov"]), &problems)
        verify("twenty one days ago", Row(span: span(10, 25, 10, 26), labels: ["Twenty one days ago · Wed 25 Oct"]), &problems)
        verify("a week ago", Row(span: span(11, 6, 11, 13), labels: ["A week ago · 6–12 Nov"]), &problems)
        verify("last three days", Row(span: span(11, 13, 11, 16), labels: ["Last three days · 13–15 Nov"]), &problems)
        verify("two fortnights ago", Row(span: span(10, 16, 10, 23), labels: ["Two fortnights ago · 16–22 Oct"]), &problems)
        verify("twenty one days back", Row(span: span(10, 25, 10, 26), labels: ["Twenty one days back · Wed 25 Oct"]), &problems)
        verify("over two and a half hours", Row(min: 9_000, labels: ["Over 2h 30m"]), &problems)
        verify("over an hour", Row(min: 3_600, labels: ["Over 1h"]), &problems)
        verify("over one hour", Row(min: 3_600, labels: ["Over 1h"]), &problems)
        verify("under forty minutes", Row(max: 2_400, labels: ["Under 40m"]), &problems)
        verify("over forty-five minutes", Row(min: 2_700, labels: ["Over 45m"]), &problems)
        verify("between ninety minutes and two hours", Row(min: 5_400, max: 7_200, labels: ["1h 30m–2h"]), &problems)
        return problems
    }
}
