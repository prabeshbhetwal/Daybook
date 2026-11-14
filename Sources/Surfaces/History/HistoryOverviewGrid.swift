import SwiftUI

/// History's day grid where the column draws it, linked to the tree's rows: a
/// day or a month's name clicked opens in the tree below. A first week has none.
struct HistoryOverviewGrid: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let link: HistoryGridLink

    var body: some View {
        if let grid = store.historyDayGrid() {
            HistoryDayGridView(grid: grid, link: link, focusedSpan: focusedSpan,
                               onPickDay: { navigation.openHistory(day: $0) },
                               onPickMonth: { Self.openMonth($0, in: navigation) }, calendar: store.periodCalendar)
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

    /// A month's name clicked: its row, which History clips to the record.
    static func openMonth(_ month: DateInterval, in navigation: MainWindowModel) {
        navigation.openHistory(place: HistoryPlace(level: .month, span: month))
    }
}
