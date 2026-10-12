import Foundation

/// History's search box reads one weekday as a day (`SearchQuery`, spec §2):
/// "last Tuesday" is the latest Tuesday before today, "Tuesday" or "on
/// Tuesday" the latest up to today, "this Tuesday" this week's and "Tuesday
/// before last" the one before last Tuesday, while "Tuesdays" stays every
/// Tuesday. "Now" is `SelfTest.base`, Wednesday 15 November 2023, and every
/// span is built through the period calendar.
enum HistorySearchWeekdayChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Last Tuesday is a chip for the latest Tuesday before today", lastWeekday),
        ("A lone weekday is the latest one up to today; plural weekdays stay recurring", loneWeekday),
        ("This Tuesday is this week's, and Tuesday before last the one before last Tuesday", thisAndBeforeLast),
        ("Weekday days hold on every day of the week, in any zone and across daylight saving", everyDayAndZone),
        ("With chips and nothing found, the empty search names the words it searched for", unreadWordsHint),
    ]

    private typealias Row = HistorySearchQueryChecks.Row

    private static func day(_ month: Int, _ day: Int, year: Int = 2023) -> DateInterval {
        HistorySearchQueryChecks.span(month, day, month, day + 1, y1: year)
    }

    private static func verify(_ rows: [(String, Row)], _ problems: inout [String]) {
        for (text, row) in rows { HistorySearchQueryChecks.verify(text, row, &problems) }
    }

    private static func lastWeekday() -> [String] {
        var problems: [String] = []
        verify([
            ("last Tuesday longer than an hour", Row(span: day(11, 14), min: 3_600,
                                                     labels: ["Last Tuesday · Tue 14 Nov", "Over 1h"])),
            ("LAST TUESDAY", Row(span: day(11, 14), labels: ["Last Tuesday · Tue 14 Nov"])),
            // Today is a Wednesday: last Wednesday is a week ago.
            ("last Wednesday", Row(span: day(11, 8), labels: ["Last Wednesday · Wed 8 Nov"])),
            ("last Thursday", Row(span: day(11, 9), labels: ["Last Thursday · Thu 9 Nov"])),
            ("last Sunday", Row(span: day(11, 12), labels: ["Last Sunday · Sun 12 Nov"])),
            ("last Monday", Row(span: day(11, 13), labels: ["Last Monday · Mon 13 Nov"])),
            ("this past Tuesday", Row(span: day(11, 14), labels: ["This past Tuesday · Tue 14 Nov"])),
            ("this past Wednesday", Row(span: day(11, 8), labels: ["This past Wednesday · Wed 8 Nov"])),
            ("last tue", Row(span: day(11, 14), labels: ["Last Tuesday · Tue 14 Nov"])),
            ("last tues", Row(span: day(11, 14), labels: ["Last Tuesday · Tue 14 Nov"])),
            ("last thurs", Row(span: day(11, 9), labels: ["Last Thursday · Thu 9 Nov"])),
            ("last sat", Row(span: day(11, 11), labels: ["Last Saturday · Sat 11 Nov"])),
            ("Thesis last Friday notes", Row(span: day(11, 10), leftover: "Thesis notes",
                                             labels: ["Last Friday · Fri 10 Nov"])),
            // The live probe's row 18 (spec §5a), typed with either apostrophe.
            ("last tuesday's sessions", Row(span: day(11, 14), leftover: "sessions", labels: ["Last Tuesday · Tue 14 Nov"])),
            ("Tuesday’s notes", Row(span: day(11, 14), leftover: "notes", labels: ["Tuesday · Tue 14 Nov"])),
            ("last Tuesdays", Row(weekdays: [3], leftover: "last", labels: ["Tuesdays"])),
        ], &problems)
        return problems
    }

    private static func loneWeekday() -> [String] {
        var problems: [String] = []
        verify([
            ("Tuesday", Row(span: day(11, 14), labels: ["Tuesday · Tue 14 Nov"])),
            ("on Tuesday", Row(span: day(11, 14), labels: ["Tuesday · Tue 14 Nov"])),
            // Today's own weekday is today.
            ("Wednesday", Row(span: day(11, 15), labels: ["Wednesday · Wed 15 Nov"])),
            ("thursday", Row(span: day(11, 9), labels: ["Thursday · Thu 9 Nov"])),
            ("on Tuesday longer than an hour", Row(span: day(11, 14), min: 3_600,
                                                   labels: ["Tuesday · Tue 14 Nov", "Over 1h"])),
            ("Tuesdays", Row(weekdays: [3], labels: ["Tuesdays"])),
            ("on Tuesdays", Row(weekdays: [3], labels: ["Tuesdays"])),
            ("tues", Row(weekdays: [3], labels: ["Tuesdays"])),
            ("wed", Row(leftover: "wed")),
            ("sat", Row(leftover: "sat")),
            ("\"Tuesday\"", Row(leftover: "\"Tuesday\"")),
            // Inside the other periods: the latest such weekday they hold.
            ("Tuesday last week", Row(span: day(11, 7), labels: ["Tuesday · Tue 7 Nov", "Last week · 6–12 Nov"])),
            ("Monday 13 November", Row(span: day(11, 13), labels: ["Monday · Mon 13 Nov", "Mon 13 Nov 2023"])),
            ("Tuesday 13 November", Row(labels: ["Tuesday · Tue 14 Nov", "Mon 13 Nov 2023"], noOverlap: true)),
            ("on Monday October", Row(span: day(10, 30), labels: ["Monday · Mon 30 Oct", "October 2023"])),
            ("Friday last year", Row(span: day(12, 30, year: 2022),
                                     labels: ["Friday · Fri 30 Dec 2022", "Last year · 1 Jan – 31 Dec 2022"])),
        ], &problems)
        return problems
    }

    private static func thisAndBeforeLast() -> [String] {
        var problems: [String] = []
        verify([
            ("this Tuesday", Row(span: day(11, 14), labels: ["This Tuesday · Tue 14 Nov"])),
            ("this Monday", Row(span: day(11, 13), labels: ["This Monday · Mon 13 Nov"])),
            ("this Wednesday", Row(span: day(11, 15), labels: ["This Wednesday · Wed 15 Nov"])),
            // Weeks run from Monday, so this Friday and this Sunday are still to come.
            ("this Friday", Row(span: day(11, 17), labels: ["This Friday · Fri 17 Nov"])),
            ("this Sunday", Row(span: day(11, 19), labels: ["This Sunday · Sun 19 Nov"])),
            ("Tuesday before last", Row(span: day(11, 7), labels: ["Tuesday before last · Tue 7 Nov"])),
            ("the Tuesday before last", Row(span: day(11, 7), labels: ["Tuesday before last · Tue 7 Nov"])),
            ("Wednesday before last", Row(span: day(11, 1), labels: ["Wednesday before last · Wed 1 Nov"])),
            ("the sunday before last", Row(span: day(11, 5), labels: ["Sunday before last · Sun 5 Nov"])),
            ("tue before last over 1h", Row(span: day(11, 7), min: 3_600,
                                            labels: ["Tuesday before last · Tue 7 Nov", "Over 1h"])),
        ], &problems)
        return problems
    }

    /// Every form for every weekday, on each of fourteen days around a zone's
    /// clock change and at three times of day, against days counted back from
    /// midnight here rather than the way the parser counts them.
    private static func everyDayAndZone() -> [String] {
        var problems: [String] = []
        var failures = 0
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        // Sydney's clocks went forward on 1 Oct 2023, Berlin's back on 29 Oct, Los Angeles's on 5 Nov.
        let windows: [(zone: String, month: Int, day: Int)] = [("Australia/Sydney", 9, 25), ("Europe/Berlin", 10, 23),
                                                              ("America/Los_Angeles", 10, 30), ("UTC", 11, 6)]
        for window in windows {
            var base = Calendar(identifier: .gregorian)
            base.timeZone = TimeZone(identifier: window.zone)!
            let calendar = base.forPeriods
            let first = calendar.date(from: DateComponents(year: 2023, month: window.month, day: window.day, hour: 12))!
            for offset in 0..<14 {
                let noon = calendar.date(byAdding: .day, value: offset, to: first)!
                for (hour, minute) in [(0, 30), (9, 13), (23, 30)] {
                    let now = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: noon)!
                    let today = calendar.startOfDay(for: now)
                    let week = calendar.dateInterval(of: .weekOfYear, for: now)!
                    func back(_ count: Int) -> DateInterval {
                        DateInterval(start: calendar.startOfDay(for: calendar.date(byAdding: .day, value: -count, to: today)!),
                                     end: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1 - count, to: today)!))
                    }
                    for (index, name) in names.enumerated() {
                        let isDay = { (count: Int) in calendar.component(.weekday, from: back(count).start) == index + 1 }
                        let lone = (0...6).first(where: isDay)!
                        let last = (1...7).first(where: isDay)!
                        let this = (-6...6).first { isDay($0) && week.holds(back($0).start) }!
                        for (text, expected) in [(name, back(lone)), ("last \(name)", back(last)),
                                                 ("this \(name)", back(this)), ("\(name) before last", back(last + 7))] {
                            let got = SearchQuery.parse(text, now: now, calendar: calendar, apps: [:], categories: [])
                            if got.span != expected {
                                failures += 1
                                if failures <= 8 {
                                    problems.append("\(window.zone) at \(now): \"\(text)\" read \(String(describing: got.span)), not \(expected)")
                                }
                            }
                        }
                    }
                }
            }
        }
        if failures > 8 { problems.append("…and \(failures - 8) more") }
        // A daylight-saving day keeps its own length: 23 hours in Sydney, 25 in Berlin.
        for (zone, now, text, expected, hours, label) in [
            ("Australia/Sydney", [10, 3], "last Sunday", [10, 1], 23.0, "Last Sunday · Sun 1 Oct"),
            ("Europe/Berlin", [10, 30], "Sunday", [10, 29], 25.0, "Sunday · Sun 29 Oct"),
        ] {
            var base = Calendar(identifier: .gregorian)
            base.timeZone = TimeZone(identifier: zone)!
            let calendar = base.forPeriods
            let at = calendar.date(from: DateComponents(year: 2023, month: now[0], day: now[1], hour: 9))!
            let got = SearchQuery.parse(text, now: at, calendar: calendar, apps: [:], categories: [])
            let span = HistorySearchQueryChecks.span(expected[0], expected[1], expected[0], expected[1] + 1, in: calendar)
            expect(got.span == span, "\(zone) \(text): span \(String(describing: got.span)), not \(span)", &problems)
            expect(got.span?.duration == hours * 3_600, "\(zone) \(text): \(String(describing: got.span?.duration)) s, not \(hours) h", &problems)
            expect(got.phrases.map(\.label) == [label], "\(zone) \(text): chips \(got.phrases.map(\.label)), not \(label)", &problems)
        }
        return problems
    }

    private static func unreadWordsHint() -> [String] {
        var problems: [String] = []
        func detail(_ text: String) -> String {
            HistorySearchChips.emptyDetail(SearchQuery.parse(text, now: SelfTest.base, calendar: HistorySearchQueryChecks.periods,
                                                             apps: [:], categories: []))
        }
        let general = detail("Thesis")
        let words = detail("banana split over 1h")
        expect(words.contains("“banana split” was searched as words"), "chips and two unread words: \(words)", &problems)
        let word = detail("over 1h fortnightly")
        expect(word.contains("“fortnightly” was searched as a word"), "chips and one unread word: \(word)", &problems)
        expect(!general.contains("searched as"), "no chips: the general hint, not \(general)", &problems)
        expect(detail("over 1h") == general, "chips and no words: the general hint, not \(detail("over 1h"))", &problems)
        return problems
    }
}
