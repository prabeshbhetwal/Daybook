import Foundation

/// History's overview cards: a card draws its whole calendar period, with
/// the days before the record and after today left blank rather than shown
/// as days without focus, and its line names its days and its best one.
enum HistoryOverviewChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A History card draws its whole period, blank before the record and after today", cardSlots),
        ("A History card names its focused days and its best day", cardDetail)
    ]

    private static let calendar = HistoryTreeChecks.calendar
    private static let today = HistoryTreeChecks.today

    /// The September fixture plus a day in January: the top is the year 2026,
    /// and its rows are months.
    private static var year: [HistoryDay] {
        HistoryTreeChecks.september + [HistoryTreeChecks.row(1, 5, focused: 600, sessions: 1)]
    }

    private static func cardSlots() -> [String] {
        var problems: [String] = []
        let top = HistoryTreeBuilder.top(days: year, today: today, calendar: calendar)
        let rows = HistoryTreeBuilder.rows(under: nil, top: top, days: year, calendar: calendar)
        guard let september = rows.first(where: { calendar.component(.month, from: $0.place.start) == 9 }) else {
            return ["the year's rows had no September, got \(rows.count) rows"]
        }
        let slots = HistoryPeriodCard.slots(september, top: top, calendar: calendar)
        expect(slots.count == 30, "September draws 30 days, got \(slots.count)", &problems)
        if slots.count == 30 {
            expect(slots[29] == nil, "30 September is after today and blank, got \(String(describing: slots[29]))", &problems)
            expect(slots[27] == 3_600, "28 September holds its hour, got \(String(describing: slots[27]))", &problems)
            expect(slots[0] == 0, "1 September was recorded without focus, got \(String(describing: slots[0]))", &problems)
        }

        // Over two years the rows are years, drawn as twelve months each.
        let record = HistoryTreeChecks.september + [HistoryTreeChecks.row(7, 3, year: 2025, focused: 60, sessions: 1)]
        let recordTop = HistoryTreeBuilder.top(days: record, today: today, calendar: calendar)
        let years = HistoryTreeBuilder.rows(under: nil, top: recordTop, days: record, calendar: calendar)
        if let earlier = years.first(where: { calendar.component(.year, from: $0.place.start) == 2025 }) {
            let months = HistoryPeriodCard.slots(earlier, top: recordTop, calendar: calendar)
            expect(months.count == 12, "2025 draws 12 months, got \(months.count)", &problems)
            if months.count == 12 {
                expect(months[0...5].allSatisfy { $0 == nil }, "January to June 2025 precede the record", &problems)
                expect(months[6] == 60, "July 2025 holds its minute, got \(String(describing: months[6]))", &problems)
                expect(months[7] == 0, "August 2025 is on record without focus", &problems)
            }
        } else {
            problems.append("the record's rows had no 2025, got \(years.count) rows")
        }
        if let current = years.first(where: { calendar.component(.year, from: $0.place.start) == 2026 }) {
            let months = HistoryPeriodCard.slots(current, top: recordTop, calendar: calendar)
            expect(months.count == 12 && months[9] == nil && months[8] == 6_300,
                   "2026 shows September's 1h 45m and leaves October blank, got \(months)", &problems)
        }
        return problems
    }

    private static func cardDetail() -> [String] {
        var problems: [String] = []
        let top = HistoryTreeBuilder.top(days: year, today: today, calendar: calendar)
        let rows = HistoryTreeBuilder.rows(under: nil, top: top, days: year, calendar: calendar)
        guard let september = rows.first(where: { calendar.component(.month, from: $0.place.start) == 9 }) else {
            return ["the year's rows had no September"]
        }
        let summary = HistoryTreeBuilder.summary(top: HistoryTop(place: september.place, firstDay: september.place.span.start,
                                                                 today: top.today),
                                                 days: year, calendar: calendar)
        let line = HistoryPeriodCard.detail(september, summary: summary, today: today, calendar: calendar)
        let wanted = "3 days · best Mon 28 Sep, \(Tokens.duration(3_600))"
        expect(line == wanted, "September's card read \"\(line)\", wanted \"\(wanted)\"", &problems)
        expect(HistoryPeriodCard.figure(september) == Tokens.duration(6_300),
               "September's figure read \(HistoryPeriodCard.figure(september))", &problems)
        return problems
    }
}
