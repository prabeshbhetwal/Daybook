import AppKit
import SwiftUI

/// Checks for History's front view as a whole: the grid stands where the
/// chart stood, only unfiltered and only above weeks or longer, a month's
/// name opens its row, and the root spine runs through the rows' dots.
enum HistoryFrontViewChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A search or filter shows results, not the grid", searchShowsNoGrid),
        ("Clicking a month's name opens that month", monthNameOpensMonth),
        ("A first week shows no grid", firstWeekShowsNoGrid),
        ("The spine meets the dots at every root level", spineMeetsDots)
    ]

    @MainActor private static func drawn(_ store: SessionStore) -> Set<StoryRenderEvidence> {
        ActivityRuleChecks.renderEvidence(
            AnyView(HistoryTree(store: store, navigation: MainWindowModel(store: store), scrolls: false)),
            width: 1_000, height: 1_400)
    }

    private static func names(_ evidence: Set<StoryRenderEvidence>) -> [String] { evidence.map(\.rawValue).sorted() }

    /// The Ask fixture runs from Tue 17 October to Wed 15 November 2023: its
    /// rows are two months, and a search for Thesis matches two of its days.
    private static func searchShowsNoGrid() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated {
                f.store.setReviewVisible(true)
                f.store.refreshReview()
                let unfiltered = drawn(f.store)
                expect(unfiltered.isSuperset(of: [.historyTree, .historyGrid]),
                       "History with no search drew \(names(unfiltered)), wanted its tree and grid", &problems)
                f.store.setHistoryQuery("Thesis")
                guard f.store.historyFilter.isActive else {
                    problems.append("searching for Thesis set no filter, so the case tests nothing")
                    return
                }
                let searched = drawn(f.store)
                expect(!searched.contains(.historyGrid),
                       "History searching for Thesis drew \(names(searched)), with the grid over its results", &problems)
            }
        }
    }

    /// October's block is the whole calendar month, but its row starts on the
    /// first recorded day, 17 October; November's runs to today.
    private static func monthNameOpensMonth() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated {
                f.store.setReviewVisible(true)
                f.store.refreshReview()
                let top = f.store.historyTop()
                let rows = f.store.historyRows(under: nil)
                guard top.rootLevel == .month, let grid = f.store.historyDayGrid(), grid.blocks.count == 2 else {
                    problems.append("the fixture's first view held \(top.rootLevel) rows and "
                                    + "\(f.store.historyDayGrid()?.blocks.count ?? 0) blocks, so the case tests nothing")
                    return
                }
                for block in grid.blocks {
                    let start = max(block.month.start, f.calendar.startOfDay(for: top.firstDay))
                    guard let month = rows.first(where: { $0.place.span.holds(start) })?.place else {
                        problems.append("no row holds \(start), the start of \(block.month)")
                        continue
                    }
                    expect(month.span.start == start && month.span.end <= block.month.end,
                           "the row for \(block.month) spans \(month.span), not the month clipped to the record",
                           &problems)
                    let navigation = MainWindowModel(store: f.store)
                    HistoryOverviewGrid.openMonth(block.month, in: navigation, rootLevel: top.rootLevel)
                    expect(navigation.historyOpen == [month] && navigation.historyFocus == .row(month),
                           "clicking \(block.month)'s name opened \(navigation.historyOpen.map(\.span)), "
                           + "wanted \(month.span)", &problems)
                    // Under a month or a week top, months are no rows: another month's name does nothing.
                    for other in grid.blocks where other.month != block.month {
                        for rootLevel in [HistoryLevel.week, .day] {
                            HistoryOverviewGrid.openMonth(other.month, in: navigation, rootLevel: rootLevel)
                            expect(navigation.historyOpen == [month],
                                   "with \(rootLevel) rows, clicking \(other.month)'s name left "
                                   + "\(navigation.historyOpen.map(\.span)) open, wanted \(month.span)", &problems)
                        }
                    }
                }
            }
        }
    }

    /// A record of one morning: the top is this week, its rows are days.
    private static func firstWeekShowsNoGrid() -> [String] {
        NameSuggestionStoreChecks.withFixture(records: { days in
            [NameSuggestionStoreChecks.record(days.at(0, 8), days.at(0, 9))]
        }) { f, _, problems in
            f.store.setReviewVisible(true)
            f.store.refreshReview()
            guard f.store.historyTop().rootLevel == .day else {
                problems.append("a record of one morning gave \(f.store.historyTop().rootLevel) rows, "
                                + "so the case tests nothing")
                return
            }
            let first = drawn(f.store)
            expect(first.contains(.historyTree) && !first.contains(.historyGrid),
                   "a first week drew \(names(first)), wanted its day rows and no grid", &problems)
        }
    }

    /// The 2-point spine is centred on the root rows' dots: past the gutter,
    /// the row's inset and half a dot. Day rows have no gutter.
    private static func spineMeetsDots() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let dotCentre = HistoryRowLayout.inset + HistoryTreeRow.dotSize / 2
            for level in [HistoryLevel.week, .month, .year] {
                let gutter = HistoryPeriodRow.gutterWidth(for: level)
                let got = HistoryTree.spineLeading(for: level) + 1.zoomed
                expect(gutter > 0 && got == gutter + dotCentre,
                       "the spine over \(level) rows is centred at \(got), wanted gutter \(gutter) "
                       + "plus the dot's centre \(dotCentre)", &problems)
            }
            let days = HistoryTree.spineLeading(for: .day) + 1.zoomed
            expect(days == dotCentre, "the spine over a first week's days is centred at \(days), "
                   + "wanted the dot's centre \(dotCentre)", &problems)
            return problems
        }
    }
}
