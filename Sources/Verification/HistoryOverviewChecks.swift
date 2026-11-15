import AppKit
import SwiftUI

/// History's first view: only the period holding today is drawn as the card,
/// and a row's second line says only what the whole record found, never the
/// row's own totals over again.
enum HistoryOverviewChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Only the period holding today is drawn as a card", onlyCurrentIsCard),
        ("A row's second line names no figure the record does not hold", lineFromRecord)
    ]

    private static let calendar = HistoryTreeChecks.calendar
    private static let today = HistoryTreeChecks.today

    /// The Ask fixture runs from 17 October to today, 15 November 2023, so its
    /// first view is two months. The card and its "so far" both follow the
    /// period holding today; the sentence reports the second.
    private static func onlyCurrentIsCard() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setReviewVisible(true)
            f.store.refreshReview()
            let top = f.store.historyTop()
            let rows = f.store.historyRows(under: nil)
            guard rows.count > 1, rows.filter({ $0.place.span.holds(top.today) }).count == 1 else {
                problems.append("the first view held \(rows.map(\.place.span)), so the case tests nothing")
                return
            }
            MainActor.assumeIsolated {
                let navigation = MainWindowModel(store: f.store)
                for row in rows {
                    let drawn = ActivityRuleChecks.renderEvidence(
                        AnyView(HistoryTreeRow(store: f.store, navigation: navigation, row: row, depth: 0,
                                               link: HistoryGridLink())),
                        width: 640, height: 260)
                    let isCard = drawn.contains(.historySoFar)
                    expect(isCard == row.place.span.holds(top.today),
                           "\(row.place.span) was \(isCard ? "" : "not ")drawn as today's card", &problems)
                }
            }
        }
    }

    /// Fourteen focused days in August, then the September fixture: 17 days
    /// on record, the longest Monday 28 September's hour.
    private static func lineFromRecord() -> [String] {
        var problems: [String] = []
        let days = HistoryTreeChecks.september
            + (13...26).map { HistoryTreeChecks.row(8, $0, focused: 1_800, tracked: 1_800, sessions: 1) }
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let rows = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
        let facts = HistoryRowFactsBuilder.facts(rows: rows, top: top,
                                                 record: HistoryRecord.of(byDate: HistoryTreeBuilder.index(days, calendar: calendar)),
                                                 calendar: calendar)
        let lines = rows.map { HistoryRowText.detail(facts[$0.id] ?? .none, row: $0, calendar: calendar) }
        let wanted: [String?] = ["Mon 28 Sep was your longest day yet, at \(Tokens.duration(3_600)). 1 day left.",
                                 "You started on 13 Aug."]
        expect(lines == wanted, "September and August read \(lines), wanted \(wanted)", &problems)
        // A row's own focus and days are its sentence's to say.
        for (row, line) in zip(rows, lines) {
            let own = [Tokens.duration(row.focused), "\(row.focusedDays) days"]
            expect(!own.contains { (line ?? "").contains($0) }, "\(row.place.span)'s line \"\(line ?? "")\" "
                   + "repeats its own \(own)", &problems)
        }
        if let september = rows.first {
            expect(HistoryRowText.detail(.none, row: september, calendar: calendar) == nil,
                   "a row with nothing to say about it still has a second line", &problems)
        }
        return problems
    }
}
