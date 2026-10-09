import Foundation

/// Ask's ranges start and end at a midnight, in zones that skip one. Santiago
/// moved its clocks forward at midnight on 3 Sep 2023, so that day began at
/// 01:00 and adding days to it kept the hour.
enum AskRangeZoneChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's last 30 days and all time run from midnight to midnight where a zone skips one",
         rangesHoldWholeDaysWhereMidnightIsSkipped),
    ]

    private static func rangesHoldWholeDaysWhereMidnightIsSkipped() -> [String] {
        var problems: [String] = []
        var base = Calendar(identifier: .gregorian)
        base.timeZone = TimeZone(identifier: "America/Santiago")!
        let calendar = base.forPeriods
        func midnight(_ month: Int, _ day: Int) -> Date {
            calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2023, month: month, day: day))!)
        }
        let now = calendar.date(from: DateComponents(year: 2023, month: 9, day: 3, hour: 12))!
        expect(calendar.component(.hour, from: calendar.startOfDay(for: now)) == 1,
               "3 Sep 2023 in Santiago no longer begins at 01:00, so this case tests nothing", &problems)

        let firstDay = calendar.date(from: DateComponents(year: 2023, month: 1, day: 10, hour: 14))!
        let expected: [(AskRange, Date, Date)] = [
            (.last30Days, midnight(8, 5), midnight(9, 4)),
            (.allTime, midnight(1, 10), midnight(9, 4)),
        ]
        for (range, start, end) in expected {
            let interval = range.interval(now: now, firstDay: firstDay, calendar: calendar)
            expect(interval.start == start && interval.end == end,
                   "\(range.rawValue) spans \(interval.start) to \(interval.end), not \(start) to \(end)", &problems)
        }
        return problems
    }
}
