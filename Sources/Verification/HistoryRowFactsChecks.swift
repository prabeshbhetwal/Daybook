import Foundation

/// Checks for the facts a History row states about its day.
enum HistoryRowFactsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The month holding the longest day says so, and the earliest day wins a tie", longestDay),
        ("A record under 14 focused days names no longest day", recordNeedsFourteenDays),
        ("The month with the most focus is the biggest, once there are three", biggest),
        ("Two months level on focus name no biggest", biggestNeedsOneLeader),
        ("A whole month is compared with the whole month before", wholeMonthChange),
        ("A month is not compared with a part month, a month without focus, or while it is still running", noChange),
        ("The month the record starts in says when", started),
        ("A row says at most two things, in order", atMostTwo),
        ("The period still running counts its days left", daysLeft),
        ("A day row says nothing extra", dayRows),
        ("Today's live figures patch the record the way a rebuild would", patchedRecord)
    ]

    private static let calendar = HistoryTreeChecks.calendar

    // MARK: - Fixtures

    private static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        HistoryTreeChecks.date(month, day, year: year)
    }

    private static func day(_ month: Int, _ day: Int, year: Int = 2026, focus: TimeInterval) -> HistoryDay {
        HistoryTreeChecks.row(month, day, year: year, focused: focus, sessions: focus > 0 ? 1 : 0)
    }

    /// `count` days of `focus` each, from `first` of a month.
    private static func run(_ month: Int, _ count: Int, from first: Int = 1, focus: TimeInterval) -> [HistoryDay] {
        (0..<count).map { day(month, first + $0, focus: focus) }
    }

    /// A month's hours on its first two days, so a record holding it starts on the 1st.
    private static func month(_ month: Int, hours: Double, year: Int = 2026) -> [HistoryDay] {
        [1, 2].map { day(month, $0, year: year, focus: hours * 1_800) }
    }

    /// The rows History draws for `days` at its first level, and their facts.
    private struct Reading {
        let rows: [HistoryRow]
        let byID: [String: HistoryRowFacts]

        func row(_ month: Int) -> HistoryRow? {
            rows.first { HistoryTreeChecks.calendar.component(.month, from: $0.place.start) == month }
        }

        func facts(_ month: Int) -> HistoryRowFacts? { row(month).flatMap { byID[$0.id] } }

        /// The facts of the row `index` places from the newest.
        func facts(at index: Int) -> HistoryRowFacts? { rows.indices.contains(index) ? byID[rows[index].id] : nil }
    }

    private static func read(_ days: [HistoryDay], today: Date, record: HistoryRecord? = nil) -> Reading {
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let rows = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
        let record = record ?? .of(byDate: HistoryTreeBuilder.index(days, calendar: calendar))
        return Reading(rows: rows, byID: HistoryRowFactsBuilder.facts(rows: rows, top: top, record: record, calendar: calendar))
    }

    private static func kind(_ fact: HistoryRowFact) -> String {
        switch fact {
        case .recordDay: return "recordDay"
        case .biggest: return "biggest"
        case .change: return "change"
        case .started: return "started"
        }
    }

    private static func kinds(_ facts: HistoryRowFacts?) -> [String]? { facts?.facts.map(kind) }

    // MARK: - Longest day

    private static func longestDay() -> [String] {
        var problems: [String] = []
        // Seven days tie for the longest; the earliest is 20 August.
        let tied = run(8, 5, from: 20, focus: 7_200) + [day(9, 14, focus: 7_200), day(10, 3, focus: 7_200)]
        let days = run(8, 10, focus: 3_600) + run(9, 10, focus: 3_600) + tied
        let record = HistoryRecord.of(byDate: HistoryTreeBuilder.index(days, calendar: calendar))
        let wanted = HistoryRecord(longestDay: date(8, 20), longestFocus: 7_200, focusedDays: 27)
        expect(record == wanted, "the record read \(record), wanted \(wanted)", &problems)
        let reading = read(days, today: date(10, 15))
        let says = HistoryRowFact.recordDay(day: date(8, 20), focused: 7_200)
        expect(reading.facts(8)?.facts.first == says, "August holds the longest day, its facts read \(String(describing: reading.facts(8)))", &problems)
        for other in [9, 10] {
            expect(kinds(reading.facts(other))?.contains("recordDay") == false,
                   "month \(other) does not hold the longest day, its facts read \(String(describing: reading.facts(other)))", &problems)
        }
        return problems
    }

    private static func recordNeedsFourteenDays() -> [String] {
        var problems: [String] = []
        let none = HistoryRecord(longestDay: nil, longestFocus: 0, focusedDays: 0)
        expect(HistoryRecord.of(byDate: [:]) == none, "no days read \(HistoryRecord.of(byDate: [:]))", &problems)
        for (count, says) in [(13, false), (14, true)] {
            // The last focused day is the longest; a day at the Mac without focus is not a focused day.
            let days = run(8, count - 1, focus: 3_600) + [day(8, count, focus: 7_200), HistoryTreeChecks.row(8, 30, tracked: 600)]
            let reading = read(days, today: date(10, 15))
            let record = HistoryRecord.of(byDate: HistoryTreeBuilder.index(days, calendar: calendar))
            expect(record.focusedDays == count, "\(count) focused days read as \(record.focusedDays)", &problems)
            expect((kinds(reading.facts(8))?.contains("recordDay") == true) == says,
                   "\(count) focused days: the longest day \(says ? "should" : "should not") be named, facts read \(String(describing: reading.facts(8)))", &problems)
        }
        return problems
    }

    // MARK: - Biggest

    private static func biggest() -> [String] {
        var problems: [String] = []
        let three = month(8, hours: 10) + month(9, hours: 30) + month(10, hours: 20)
        let reading = read(three, today: date(10, 20))
        expect(reading.rows.count == 3, "three months gave \(reading.rows.count) rows", &problems)
        for (number, says) in [(8, false), (9, true), (10, false)] {
            expect(kinds(reading.facts(number))?.contains("biggest") == says,
                   "month \(number) \(says ? "has" : "lacks") the most focus, facts read \(String(describing: reading.facts(number)))", &problems)
        }
        let two = read(month(9, hours: 30) + month(10, hours: 20), today: date(10, 20))
        for number in [9, 10] {
            expect(kinds(two.facts(number))?.contains("biggest") == false,
                   "two months name no biggest, month \(number) read \(String(describing: two.facts(number)))", &problems)
        }
        return problems
    }

    private static func biggestNeedsOneLeader() -> [String] {
        var problems: [String] = []
        let level = read(month(8, hours: 10) + month(9, hours: 30) + month(10, hours: 30), today: date(10, 20))
        for number in [8, 9, 10] {
            expect(kinds(level.facts(number))?.contains("biggest") == false,
                   "months level on focus name no biggest, month \(number) read \(String(describing: level.facts(number)))", &problems)
        }
        // Three months at the Mac without focus have no most focus to name.
        let idle = [8, 9, 10].map { HistoryTreeChecks.row($0, 1, tracked: 600) }
        let reading = read(idle, today: date(10, 20))
        expect(reading.rows.count == 3 && reading.rows.allSatisfy { kinds(reading.byID[$0.id])?.contains("biggest") == false },
               "months without focus name no biggest, got \(reading.byID.values)", &problems)
        return problems
    }

    // MARK: - Change

    private static func wholeMonthChange() -> [String] {
        var problems: [String] = []
        // October and September are both over and both start on the 1st.
        let table: [(october: Double, september: Double, percent: Int?)] = [
            (74.5, 45.67, 63), (45.67, 74.5, -39), (110, 100, 10), (90, 100, -10), (109, 100, nil), (91, 100, nil), (100, 100, nil)
        ]
        for (october, september, percent) in table {
            let reading = read(month(9, hours: september) + month(10, hours: october), today: date(11, 5))
            guard let previous = reading.row(9)?.place else { problems.append("the rows had no September"); continue }
            let facts = reading.facts(10)
            if let percent {
                expect(facts?.facts.contains(.change(percent: percent, previous: previous)) == true,
                       "\(october)h against \(september)h should read \(percent)%, facts read \(String(describing: facts))", &problems)
            } else {
                expect(kinds(facts)?.contains("change") == false,
                       "\(october)h against \(september)h is under 10%, facts read \(String(describing: facts))", &problems)
            }
        }
        // The month with the most focus is named before the change.
        let rise = read(month(9, hours: 45.67) + month(10, hours: 74.5), today: date(11, 5))
        expect(kinds(rise.facts(10)) == ["biggest", "change"], "a bigger month reads \(String(describing: kinds(rise.facts(10))))", &problems)
        return problems
    }

    private static func noChange() -> [String] {
        var problems: [String] = []
        func says(_ days: [HistoryDay], today: Date) -> Bool? { kinds(read(days, today: today).facts(10))?.contains("change") }
        // Control: the same two months, both over, are compared.
        expect(says(month(9, hours: 40) + month(10, hours: 80), today: date(11, 1)) == true, "a finished October did not read against September", &problems)
        expect(says(run(9, 2, from: 17, focus: 72_000) + month(10, hours: 80), today: date(11, 5)) == false,
               "October was compared with a September that began on the 17th", &problems)
        expect(says([HistoryTreeChecks.row(9, 1, tracked: 600)] + month(10, hours: 50), today: date(11, 5)) == false,
               "October was compared with a September without focus", &problems)
        // A month without focus says nothing: no fall of 100%, and neither the first day nor the longest day.
        let idle = HistoryTreeChecks.row(10, 1, tracked: 600)
        let fell = read(month(9, hours: 40) + [idle], today: date(11, 5))
        expect(fell.facts(10) == HistoryRowFacts.none, "an October without focus read \(String(describing: fell.facts(10)))", &problems)
        let quiet = HistoryRecord(longestDay: date(9, 1), longestFocus: 3_600, focusedDays: 20)
        let first = read([HistoryTreeChecks.row(9, 1, tracked: 600)] + month(10, hours: 80), today: date(11, 5), record: quiet)
        expect(first.facts(9) == HistoryRowFacts.none, "a September without focus read \(String(describing: first.facts(9)))", &problems)
        // A corrupt month of 1e300 focus after a real one is too large to be a change: no fact, and no trap.
        expect(says(month(9, hours: 40) + month(10, hours: 1e297), today: date(11, 5)) == false,
               "an impossible October was compared with September", &problems)
        // Still running, it keeps its days left.
        let running = read(month(9, hours: 40) + [idle], today: date(10, 15))
        expect(running.facts(10) == HistoryRowFacts(facts: [], daysLeft: 16), "a running October without focus read \(String(describing: running.facts(10)))", &problems)
        // 31 October is the last day: the row is whole, but the month is still running.
        for today in [date(10, 15), date(10, 31)] {
            expect(says(month(9, hours: 40) + month(10, hours: 80), today: today) == false,
                   "October was compared while it was still running, on \(today)", &problems)
        }
        return problems
    }

    // MARK: - Started, order and days left

    private static func started() -> [String] {
        var problems: [String] = []
        let reading = read(run(9, 2, from: 17, focus: 1_800) + month(10, hours: 2), today: date(10, 15))
        expect(reading.facts(9)?.facts.contains(.started(day: date(9, 17))) == true,
               "September holds the first day, facts read \(String(describing: reading.facts(9)))", &problems)
        expect(kinds(reading.facts(10))?.contains("started") == false, "October does not hold the first day", &problems)
        // Over two years the rows are years, and the older one holds the first day.
        let years = read([day(7, 3, year: 2025, focus: 600)] + month(9, hours: 2), today: date(9, 29))
        expect(years.rows.count == 2 && years.rows.last.flatMap { years.byID[$0.id] }?.facts.contains(.started(day: date(7, 3, year: 2025))) == true,
               "the first year did not say it started on 3 July 2025", &problems)
        return problems
    }

    private static func atMostTwo() -> [String] {
        // August holds the longest day, the most focus and the first day.
        let days = run(8, 15, focus: 3_600) + [day(8, 20, focus: 7_200)] + month(9, hours: 2) + month(10, hours: 2)
        let reading = read(days, today: date(10, 20))
        var problems: [String] = []
        expect(kinds(reading.facts(8)) == ["recordDay", "biggest"], "August read \(String(describing: kinds(reading.facts(8))))", &problems)
        expect(kinds(reading.facts(9)) == ["change"], "September read \(String(describing: kinds(reading.facts(9))))", &problems)
        return problems
    }

    private static func daysLeft() -> [String] {
        var problems: [String] = []
        let record = [day(8, 10, focus: 3_600), day(9, 3, focus: 3_600)]
        // 15 September: the row holds only the first fifteen days, the count is for the whole month.
        let middle = read(record, today: date(9, 15))
        expect(middle.facts(9)?.daysLeft == 15, "15 of 30 days left read \(String(describing: middle.facts(9)))", &problems)
        expect(middle.facts(8).map { $0.daysLeft == nil } == true, "a finished month counted days left", &problems)
        let last = read(record, today: date(9, 30))
        expect(last.facts(9).map { $0.daysLeft == nil } == true, "the last day read \(String(describing: last.facts(9)))", &problems)
        // A week counts to its Sunday, not to the end of the month the record is inside.
        let weeks = read(HistoryTreeChecks.september, today: HistoryTreeChecks.today)
        expect(weeks.facts(at: 0)?.daysLeft == 5, "Tuesday 29 September read \(String(describing: weeks.facts(at: 0)))", &problems)
        expect([1, 2].allSatisfy { weeks.facts(at: $0).map { $0.daysLeft == nil } == true }, "a finished week counted days left", &problems)
        // A year counts to 31 December: 30 September, 31 October, 30 November and 31 December.
        let years = read([day(7, 3, year: 2025, focus: 600)] + record, today: date(9, 29))
        expect(years.facts(at: 0)?.daysLeft == 93, "29 September 2026 read \(String(describing: years.facts(at: 0)))", &problems)
        expect(years.facts(at: 1).map { $0.daysLeft == nil } == true, "a finished year counted days left", &problems)
        return problems
    }

    private static func dayRows() -> [String] {
        // Everything a day row could be named for: the longest day, the most focus, the first day, today.
        let days = [day(9, 28, focus: 3_600), day(9, 29, focus: 1_800), day(9, 30, focus: 10_800), day(10, 1, focus: 600), day(10, 2, focus: 300)]
        let record = HistoryRecord(longestDay: date(9, 30), longestFocus: 10_800, focusedDays: 20)
        let reading = read(days, today: date(10, 2), record: record)
        var problems: [String] = []
        expect(reading.rows.count == 5 && reading.rows.allSatisfy { $0.place.level == .day }, "the fixture did not give five day rows", &problems)
        expect(reading.rows.allSatisfy { reading.byID[$0.id] == HistoryRowFacts.none }, "a day row said \(reading.byID.values.filter { $0 != HistoryRowFacts.none })", &problems)
        return problems
    }

    // MARK: - Live figures

    private static func patchedRecord() -> [String] {
        var problems: [String] = []
        let past = run(9, 14, focus: 3_600)
        func live(_ focus: TimeInterval) -> HistoryDay { day(9, 15, focus: focus) }
        func index(_ today: HistoryDay?) -> [Date: HistoryDay] {
            HistoryTreeBuilder.index(past + [today].compactMap { $0 }, calendar: calendar)
        }
        // Today as the index held it (nil: not in it) and as it is now, against a rebuild with today live.
        let table: [(cached: TimeInterval?, now: TimeInterval)] = [
            (nil, 600), (nil, 3_600), (nil, 5_400), (600, 5_400), (5_400, 7_200), (600, 0), (3_600, 3_600)
        ]
        for (cached, now) in table {
            let before = cached.map(live)
            let base = HistoryRecord.of(byDate: index(before))
            let patched = base.patched(live: live(now), cachedToday: before, calendar: calendar)
            let rebuilt = HistoryRecord.of(byDate: index(live(now)))
            expect(patched == rebuilt, "today \(String(describing: cached)) to \(now) read \(patched), a rebuild reads \(rebuilt)", &problems)
            expect(base.patched(live: nil, cachedToday: before, calendar: calendar) == base, "no live day changed the record", &problems)
        }
        return problems
    }
}
