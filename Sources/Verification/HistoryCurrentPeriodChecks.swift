import AppKit
import SwiftUI

/// A History period is still running only while today lies inside it. One
/// that ends at the midnight starting today (last week on a Monday, last
/// month on the 1st, last year on 1 January) is over: its card says no
/// "So far" and its rail shows none of this month's Insights.
enum HistoryCurrentPeriodChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A History period that ended at today's midnight is not drawn as still running",
         endedPeriodIsNotCurrent),
    ]

    /// The Ask fixture's History runs from Tue 17 Oct to Wed 15 Nov 2023. Each
    /// case moves the clock to the first day of a period, so the one before
    /// it ends exactly at the start of today.
    private static let cases: [(label: String, daysLater: Int, level: HistoryLevel)] = [
        ("last week on a Monday", 5, .week),
        ("last month on the 1st", 16, .month),
        ("last year on 1 January", 47, .year),
    ]

    private static func endedPeriodIsNotCurrent() -> [String] {
        var problems: [String] = []
        for item in cases {
            problems += AskLookupChecks.withFixture { f, problems in
                let calendar = f.calendar
                f.clock.value = calendar.date(byAdding: .day, value: item.daysLater, to: f.clock.value) ?? f.clock.value
                f.store.setReviewVisible(true)
                f.store.refreshReview()
                let top = f.store.historyTop()
                let today = calendar.startOfDay(for: f.clock.value)
                // Down the tree through the rows holding today to the level under test.
                var rows = f.store.historyRows(under: top.place)
                while let first = rows.first, first.place.level != item.level,
                      let parent = rows.first(where: { $0.place.start <= today && today < $0.place.span.end }) {
                    rows = f.store.historyRows(under: parent.place)
                }
                guard let ended = rows.first(where: { $0.place.span.end == today }),
                      let current = rows.first(where: { $0.place.start == today }) else {
                    problems.append("\(item.label): no \(item.level) rows end and start at \(today), "
                                    + "so the case tests nothing: \(rows.map(\.place.span))")
                    return
                }
                expect(!soFar(ended, store: f.store), "\(item.label): the card for \(ended.place.span), "
                       + "which ended at the start of today, says So far", &problems)
                expect(soFar(current, store: f.store), "\(item.label): the card for \(current.place.span), "
                       + "today's, does not say So far", &problems)
                guard item.level == .month else { return }
                expect(!HistoryPeriodRail.showsThisMonth(place: ended.place, top: top),
                       "\(item.label): last month's rail shows this month's Insights", &problems)
                expect(HistoryPeriodRail.showsThisMonth(place: current.place, top: top),
                       "\(item.label): this month's rail does not show this month's Insights", &problems)
            }
        }
        return problems
    }

    private static func soFar(_ row: HistoryRow, store: SessionStore) -> Bool {
        MainActor.assumeIsolated {
            ActivityRuleChecks.renderEvidence(AnyView(HistoryPeriodCard(store: store, row: row, isOpen: false,
                                                                        isFocused: false)),
                                              width: 640, height: 260).contains(.historySoFar)
        }
    }
}
