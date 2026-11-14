import Foundation
/// Checks for History's day grid: cell sizes, gaps and blocks per row.
/// The model's checks come first: the shade steps, the months it draws and
/// the cells of each month, in zones where a day is not 24 hours.
enum HistoryDayGridChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A day's shade steps at 2, 5 and 8 hours", stepBoundaries),
        ("A record inside one week draws no grid", weekDrawsNoGrid),
        ("The grid starts on the first recorded day and ends with the month", startsOnFirstDay),
        ("A long record draws its last twelve months", lastTwelveMonths),
        ("January and the first block carry the year when the grid spans two years", yearLabels),
        ("A block has one cell for each calendar day", oneCellPerDay),
        ("Days after today wait as days to come", daysToCome),
        ("A recorded day without focus is shaded none, not left out", noFocusIsNone),
        ("A running session lifts today's cell without a rebuild", runningSessionLiftsToday)
    ]
    private static let calendar = HistoryTreeChecks.calendar
    private static let today = HistoryTreeChecks.today
    private static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        HistoryTreeChecks.date(month, day, year: year)
    }
    private static func drawn(_ days: [HistoryDay], today: Date = HistoryTreeChecks.today,
                             calendar: Calendar = HistoryTreeChecks.calendar) -> HistoryDayGrid? {
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        return HistoryDayGridBuilder.grid(top: top, byDate: HistoryTreeBuilder.index(days, calendar: calendar),
                                          calendar: calendar)
    }
    private static func record(from month: Int, _ day: Int, year: Int = 2026) -> [HistoryDay] {
        [HistoryTreeChecks.row(month, day, year: year, focused: 600, sessions: 1)]
    }
    private static func stepBoundaries() -> [String] {
        var problems: [String] = []
        let table: [(seconds: TimeInterval, step: HistoryFocusStep)] = [
            (0, .none), (1, .under2h), (7_199, .under2h), (7_200, .under5h), (17_999, .under5h),
            (18_000, .under8h), (28_799, .under8h), (28_800, .over8h), (86_400, .over8h)
        ]
        for (seconds, want) in table {
            let got = HistoryFocusStep.step(for: seconds)
            expect(got == want, "\(seconds) seconds is \(want), got \(got)", &problems)
        }
        expect(HistoryFocusStep.allCases.sorted() == HistoryFocusStep.allCases,
               "the steps run from the lightest to the darkest, got \(HistoryFocusStep.allCases.sorted())", &problems)
        return problems
    }
    private static func weekDrawsNoGrid() -> [String] {
        var problems: [String] = []
        let week = [HistoryTreeChecks.row(9, 28, focused: 3_600, sessions: 1), HistoryTreeChecks.row(9, 29, focused: 600, sessions: 1)]
        let weekTop = HistoryTreeBuilder.top(days: week, today: today, calendar: calendar)
        expect(weekTop.place?.level == .week, "the fixture's top is a week, got \(String(describing: weekTop.place?.level))", &problems)
        expect(drawn(week) == nil, "a record inside one week draws no grid", &problems)
        expect(drawn([]) == nil, "no days draw no grid", &problems)
        // A month top, so only the missing days can be the reason.
        let monthTop = HistoryTreeBuilder.top(days: HistoryTreeChecks.september, today: today, calendar: calendar)
        expect(HistoryDayGridBuilder.grid(top: monthTop, byDate: [:], calendar: calendar) == nil,
               "a month top with no recorded day draws no grid", &problems)
        expect(drawn(HistoryTreeChecks.september) != nil, "a month of days does draw a grid", &problems)
        return problems
    }
    private static func startsOnFirstDay() -> [String] {
        var problems: [String] = []
        // 7 January 2026 is a Wednesday and 1 February a Sunday; 1 September is a Tuesday.
        let days = HistoryTreeChecks.september + [HistoryTreeChecks.row(1, 7, focused: 600, sessions: 1)]
        guard let grid = drawn(days), let first = grid.blocks.first else { return ["a record from January drew no grid"] }
        expect(first.cells.first?.day == date(1, 7), "the first cell is 7 Jan, got \(String(describing: first.cells.first?.day))", &problems)
        expect(first.cells.count == 25, "7 to 31 Jan is 25 cells, got \(first.cells.count)", &problems)
        expect(first.leadingBlanks == 2, "a Wednesday has 2 blank rows above it, got \(first.leadingBlanks)", &problems)
        expect(first.month.start == date(1, 1) && first.month.end == date(2, 1),
               "the block's month is the whole of January, got \(first.month)", &problems)
        expect(grid.blocks.count == 9 && grid.blocks.last?.month.start == date(9, 1),
               "January to September is 9 blocks ending with September, got \(grid.blocks.count)", &problems)
        if grid.blocks.count > 1 {
            let february = grid.blocks[1]
            expect(february.cells.first?.day == date(2, 1) && february.leadingBlanks == 6,
                   "February's first cell is the 1st, a Sunday with 6 blank rows, got \(String(describing: february.cells.first?.day)) and \(february.leadingBlanks)", &problems)
        }
        let onFirst = [HistoryTreeChecks.row(9, 1, sessions: 1)] + HistoryTreeChecks.september
        if let september = drawn(onFirst)?.blocks.first {
            expect(september.cells.first?.day == date(9, 1) && september.leadingBlanks == 1,
                   "a record from 1 Sep starts on the 1st, a Tuesday, got \(String(describing: september.cells.first?.day)) and \(september.leadingBlanks)", &problems)
        } else {
            problems.append("a record from 1 September drew no grid")
        }
        return problems
    }
    private static func lastTwelveMonths() -> [String] {
        var problems: [String] = []
        // Today is in September 2026. Capped records start on the 1st of their first month.
        let table: [(month: Int, day: Int, year: Int, blocks: Int, firstCell: Date)] = [
            (8, 3, 2026, 2, date(8, 3)),
            (10, 15, 2025, 12, date(10, 15, year: 2025)),
            (9, 10, 2025, 12, date(10, 1, year: 2025)),
            (3, 3, 2021, 12, date(10, 1, year: 2025))
        ]
        for row in table {
            guard let grid = drawn(record(from: row.month, row.day, year: row.year)) else {
                problems.append("a record from \(row.day)/\(row.month)/\(row.year) drew no grid")
                continue
            }
            let name = "a record from \(row.day)/\(row.month)/\(row.year)"
            expect(grid.blocks.count == row.blocks, "\(name) draws \(row.blocks) blocks, got \(grid.blocks.count)", &problems)
            expect(grid.blocks.first?.cells.first?.day == row.firstCell,
                   "\(name) starts on \(row.firstCell), got \(String(describing: grid.blocks.first?.cells.first?.day))", &problems)
            expect(grid.blocks.last?.month.start == date(9, 1), "\(name) ends with September 2026", &problems)
        }
        return problems
    }
    private static func yearLabels() -> [String] {
        var problems: [String] = []
        // The indices of the blocks that name their year, for records ending in September 2026.
        let table: [(month: Int, day: Int, year: Int, carriers: [Int])] = [
            (9, 3, 2026, []),       // one block
            (1, 7, 2026, []),       // January to September, one year
            (9, 10, 2025, [0, 3]),  // capped: October 2025 first, then January
            (12, 5, 2025, [0, 1])   // December 2025 first, then January
        ]
        for row in table {
            guard let grid = drawn(record(from: row.month, row.day, year: row.year)) else {
                problems.append("a record from \(row.day)/\(row.month)/\(row.year) drew no grid")
                continue
            }
            let carriers = grid.blocks.indices.filter { grid.blocks[$0].showsYear }
            expect(carriers == row.carriers,
                   "a record from \(row.day)/\(row.month)/\(row.year) names the year on blocks \(row.carriers), got \(carriers)", &problems)
        }
        return problems
    }
    private static func oneCellPerDay() -> [String] {
        var problems: [String] = []
        for zone in ["Europe/Berlin", "Pacific/Kiritimati"] {
            var base = Calendar(identifier: .gregorian)
            base.timeZone = TimeZone(identifier: zone)!
            let calendar = HistoryTreeBuilder.calendar(base)
            func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
                calendar.date(from: DateComponents(year: year, month: month, day: day))!
            }
            // December 2025 to November 2026 holds Berlin's clock changes on 29 March and 25 October.
            let first = HistoryDay(date: date(2025, 11, 20), tracked: 0, focused: 600, sessions: 1,
                                   appBundleIDs: [], workTypes: [.deepWork])
            guard let grid = drawn([first], today: date(2026, 11, 10), calendar: calendar) else {
                problems.append("\(zone) drew no grid")
                continue
            }
            let cells = grid.blocks.flatMap(\.cells)
            expect(grid.blocks.count == 12 && cells.count == 365,
                   "\(zone): December 2025 to November 2026 is 12 blocks and 365 cells, got \(grid.blocks.count) and \(cells.count)", &problems)
            expect(zip(cells, cells.dropFirst()).allSatisfy { $0.day < $1.day }, "\(zone): the cells run in order", &problems)
            expect(cells.allSatisfy { calendar.startOfDay(for: $0.day) == $0.day }, "\(zone): every cell is a start of day", &problems)
            for block in grid.blocks {
                let numbers = block.cells.map { calendar.component(.day, from: $0.day) }
                let firstNumber = numbers.first ?? 0
                let length = calendar.range(of: .day, in: .month, for: block.month.start)?.count ?? 0
                expect(block.cells.count + firstNumber - 1 == length,
                       "\(zone), month from \(block.month.start): \(block.cells.count) cells from day \(firstNumber) of \(length)", &problems)
                expect(numbers == Array(firstNumber ..< firstNumber + numbers.count),
                       "\(zone), month from \(block.month.start): days \(numbers) are not each day once", &problems)
            }
        }
        return problems
    }
    private static func daysToCome() -> [String] {
        var problems: [String] = []
        let days = HistoryTreeChecks.september + [HistoryTreeChecks.row(1, 7, focused: 600, sessions: 1)]
        guard let grid = drawn(days) else { return ["a record from January drew no grid"] }
        let cells = grid.blocks.flatMap(\.cells)
        let later = cells.filter { $0.day > today }
        expect(later.count == 1 && later.allSatisfy { $0.kind == .toCome && $0.focused == 0 && !$0.isToday },
               "30 September alone is to come, with no focus, got \(later)", &problems)
        expect(cells.filter { $0.day <= today }.allSatisfy { $0.kind != .toCome },
               "no cell on or before today is to come", &problems)
        let marked = cells.filter(\.isToday)
        expect(marked.count == 1 && marked.first?.day == today, "exactly today's cell is today, got \(marked.map(\.day))", &problems)
        if let cell = marked.first {
            expect(cell.kind == .recorded(.none) && cell.focused == 0, "today, with no focus yet, is shaded none, got \(cell)", &problems)
        }
        // On the last day of the month nothing is left to come.
        let last = drawn(days, today: date(9, 30))?.blocks.last?.cells
        expect(last?.last?.isToday == true && last?.contains { $0.kind == .toCome } == false,
               "on 30 September the last cell is today and none is to come", &problems)
        return problems
    }
    private static func noFocusIsNone() -> [String] {
        var problems: [String] = []
        guard let cells = drawn(HistoryTreeChecks.september)?.blocks.first?.cells else { return ["September drew no grid"] }
        // 19 Sep: at the Mac for ten minutes, no focus. 20 Sep: nothing recorded at all.
        for day in [date(9, 19), date(9, 20)] {
            guard let cell = cells.first(where: { $0.day == day }) else {
                problems.append("\(day) was left out of the grid")
                continue
            }
            expect(cell.kind == .recorded(.none) && cell.focused == 0, "\(day) is shaded none with no focus, got \(cell)", &problems)
        }
        if let cell = cells.first(where: { $0.day == date(9, 28) }) {
            expect(cell.kind == .recorded(.under2h) && cell.focused == 3_600, "an hour of focus on 28 Sep is under 2h, got \(cell)", &problems)
        }
        return problems
    }
    private static func runningSessionLiftsToday() -> [String] {
        var problems: [String] = []
        let indexed = HistoryTreeChecks.september + [HistoryTreeChecks.row(9, 29, focused: 3_600, sessions: 1)]
        guard let built = drawn(indexed) else { return ["September drew no grid"] }
        let before = built.blocks.flatMap(\.cells)
        let live = HistoryTreeChecks.row(9, 29, focused: 7_200, sessions: 1)
        let patched = HistoryDayGridBuilder.patching(built, live: live, today: today, calendar: calendar)
        let after = patched.blocks.flatMap(\.cells)
        expect(before.first(where: \.isToday)?.kind == .recorded(.under2h), "today starts under 2h", &problems)
        let changed = zip(before, after).filter { $0 != $1 }.map { $1 }
        expect(after.count == before.count && changed.count == 1 && changed.first?.day == today
                && changed.first?.kind == .recorded(.under5h) && changed.first?.focused == 7_200 && changed.first?.isToday == true,
               "only today's cell changes, to under 5h with 7200 seconds, got \(changed)", &problems)
        let rebuilt = drawn(HistoryTreeChecks.september + [live])
        expect(patched == rebuilt, "the patched grid is the grid an index holding the live day would build", &problems)
        expect(HistoryDayGridBuilder.patching(built, live: nil, today: today, calendar: calendar) == built,
               "without a live day the grid is left as indexed", &problems)
        let yesterdays = HistoryTreeChecks.row(9, 28, focused: 28_800, sessions: 1)
        expect(HistoryDayGridBuilder.patching(built, live: yesterdays, today: today, calendar: calendar) == built,
               "a live day that is not today changes nothing", &problems)
        // After midnight: 30 September becomes today, 29 September keeps what it held.
        let tomorrow = HistoryTreeBuilder.dayAfter(today, calendar: calendar)
        let rolled = HistoryDayGridBuilder.patching(built, live: nil, today: tomorrow, calendar: calendar)
        expect(rolled == drawn(indexed, today: tomorrow), "after midnight the grid is the one built on 30 September", &problems)
        let marked = rolled.blocks.flatMap(\.cells).filter(\.isToday)
        expect(marked.count == 1 && marked.first?.day == tomorrow && marked.first?.kind == .recorded(.none),
               "after midnight only 30 September is today, shaded none, got \(marked)", &problems)
        return problems
    }
}
