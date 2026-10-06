import Foundation

/// A session continued past midnight is listed under each day it touched.
/// History's results are one lazy list, which draws one view per id, so
/// cards that shared an id left blank slots where the others belonged.
enum HistorySessionIDChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session continued past midnight has its own card, and its own place on the path, on each day it touched",
         eachDayHasItsOwnCard),
    ]

    private static func eachDayHasItsOwnCard() -> [String] {
        var problems: [String] = []
        let calendar = HistoryTreeChecks.calendar
        let today = HistoryTreeChecks.date(10, 6)
        let days = [HistoryTreeChecks.date(10, 5), today]
        let thread = UUID()
        let ids = days.map { HistorySessionPick(thread: thread, day: $0).scrollID }
        expect(Set(ids).count == days.count,
               "a session on two days should have a card id for each day, got \(ids)", &problems)
        let other = HistorySessionPick(thread: UUID(), day: days[0]).scrollID
        expect(!ids.contains(other), "another session on the same day should not share its card id, got \(other)",
               &problems)

        // The path's session part leads to the card on the day that was picked.
        let top = HistoryTop(place: nil, firstDay: HistoryTreeChecks.date(9, 17, year: 2024), today: today,
                             calendar: calendar)
        for (day, id) in zip(days, ids) {
            let target = HistoryPath.crumbs(top: top, open: [], session: (thread: thread, day: day, title: "Coding"),
                                            today: today, calendar: calendar).last?.target
            expect(target == id, "the path should lead to \(id), got \(target ?? "nothing")", &problems)
        }
        return problems
    }
}
