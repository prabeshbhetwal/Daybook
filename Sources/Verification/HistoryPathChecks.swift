import Foundation

/// The path bar under History's search: what it names and where each part
/// leads. Fixtures reuse the tree checks' Sydney calendar and invented days.
enum HistoryPathChecks {
    static let tests: [(String, () -> [String])] = [
        ("History's path names the year, month, week, day and session that are open, each leading to its row",
         pathNamesOpenPlaces),
        ("A place on the path is gone to: what is under it folds, and the top period folds everything",
         pathClickGoesThere)
    ]

    static func pathNamesOpenPlaces() -> [String] {
        let calendar = HistoryTreeChecks.calendar
        let today = HistoryTreeChecks.date(9, 29)
        let sunday = HistoryTreeChecks.date(9, 27)
        let start = HistoryTreeChecks.date(1, 1)
        let year = HistoryPlace(level: .year,
                                span: DateInterval(start: start, end: HistoryTreeChecks.date(1, 1, year: 2027)))
        let top = HistoryTop(place: year, firstDay: HistoryTreeChecks.date(9, 17), today: today, calendar: calendar)
        let open = HistoryTreeBuilder.path(to: sunday, top: top, calendar: calendar)
        let thread = UUID()
        let crumbs = HistoryPath.crumbs(top: top, open: open,
                                        session: (thread: thread, day: sunday, title: "Coding"),
                                        today: today, calendar: calendar)
        var problems: [String] = []
        let titles = crumbs.map(\.title)
        if titles != ["2026", "September", "21 – 27 Sep", "Sun 27 Sep", "Coding"] {
            problems.append("path read \(titles)")
        }
        if crumbs.first?.target != HistoryPath.topID || crumbs.first?.focus != nil {
            problems.append("the top period did not lead to the headline")
        }
        if zip(crumbs.dropFirst(), open).contains(where: { $0.target != $1.id || $0.focus != .row($1) }) {
            problems.append("an open row's part did not lead to that row")
        }
        if crumbs.last?.target != "session-\(thread.uuidString)"
            || crumbs.last?.focus != .session(thread: thread, day: sunday) {
            problems.append("the session's part did not lead to the session")
        }

        // A record shorter than a year sits under its month, which must say the year.
        let month = HistoryPlace(level: .month,
                                 span: DateInterval(start: HistoryTreeChecks.date(9, 1), end: HistoryTreeChecks.date(10, 1)))
        let monthTop = HistoryTop(place: month, firstDay: HistoryTreeChecks.date(9, 17), today: today,
                                  calendar: calendar)
        let monthTitle = HistoryPath.crumbs(top: monthTop, open: [], session: nil, today: today, calendar: calendar)
            .first?.title
        if monthTitle != "September 2026" { problems.append("a month on top read \(monthTitle ?? "nothing")") }

        // Several years on top and nothing open: there is no place to name.
        let allYears = HistoryTop(place: nil, firstDay: HistoryTreeChecks.date(9, 17, year: 2024), today: today,
                                  calendar: calendar)
        if !HistoryPath.crumbs(top: allYears, open: [], session: nil, today: today, calendar: calendar).isEmpty {
            problems.append("an all-years record with nothing open still drew a path")
        }
        return problems
    }

    static func pathClickGoesThere() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            var problems: [String] = []
            let start = navigation.historyOpen
            guard start.count >= 2 else { return ["the fixture did not open History two levels deep"] }
            if let day = store.historyDays.first(where: { $0.sessions > 0 })?.date,
               let thread = store.journalThreads(on: day, only: nil).first {
                navigation.selectHistory(session: thread, on: day)
            } else {
                problems.append("the fixture has no day with a session to pick")
            }
            let open = navigation.historyOpen
            navigation.navigateHistory(to: open[0])
            if navigation.historyOpen != [open[0]] {
                problems.append("a place on the path left \(navigation.historyOpen.count) rows open, not 1")
            }
            if navigation.historySession != nil { problems.append("a place on the path kept the picked session") }
            if navigation.historyFocus != .row(open[0]) { problems.append("the keyboard did not land on the place clicked") }
            navigation.navigateHistory(to: nil)
            if !navigation.historyOpen.isEmpty { problems.append("the top period left rows open") }
            // A place no longer open is not on the path, so it cannot be gone to.
            navigation.navigateHistory(to: open[1])
            if !navigation.historyOpen.isEmpty { problems.append("a place off the path opened rows") }
            return problems
        }
    }
}
