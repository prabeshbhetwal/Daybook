import SwiftUI

/// History's day grid where the column draws it, linked to the tree's rows: a
/// day or a month's name clicked opens in the tree below. A first week has none.
struct HistoryOverviewGrid: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let link: HistoryGridLink

    var body: some View {
        if let grid = store.historyDayGrid() {
            let rootLevel = store.historyTop().rootLevel
            HistoryDayGridView(grid: grid, link: link, focusedSpan: focusedSpan,
                               onPickDay: { navigation.openHistory(day: $0) },
                               onPickMonth: Self.reachesMonths(rootLevel)
                                   ? { Self.openMonth($0, in: navigation, rootLevel: rootLevel) } : nil,
                               calendar: store.periodCalendar)
                .padding(.horizontal, HistoryRowLayout.inset)
                // Once the grid leaves, as when a search takes over, no cell stays lowered.
                .onDisappear(perform: link.clear)
        }
    }

    /// The row the keyboard is on, which the grid marks as it marks a pointed row.
    private var focusedSpan: DateInterval? {
        if case .row(let place) = navigation.historyFocus { return place.span }
        return nil
    }

    /// Months are rows, or lie under year rows, only when the top is the whole
    /// record or a year; under a month or a week the name has no row to open.
    static func reachesMonths(_ rootLevel: HistoryLevel) -> Bool { rootLevel == .year || rootLevel == .month }

    /// A month's name clicked: its row, which History clips to the record.
    static func openMonth(_ month: DateInterval, in navigation: MainWindowModel, rootLevel: HistoryLevel) {
        guard reachesMonths(rootLevel) else { return }
        navigation.openHistory(place: HistoryPlace(level: .month, span: month))
    }
}
