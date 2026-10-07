import SwiftUI
import AppKit

/// History below the chrome: the tree, and beside it the rail for the
/// deepest open row.
struct HistoryWorkspace: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @ObservedObject var settings: SettingsModel
    var scrolls = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HistoryTree(store: store, navigation: navigation, scrolls: scrolls)
            Divider()
            Group {
                if scrolls {
                    ScrollView { HistoryJournalRail(store: store, navigation: navigation, settings: settings) }
                } else {
                    HistoryJournalRail(store: store, navigation: navigation, settings: settings)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: StoryLayout.railWidth)
            .background(StoryStyle.rail)
        }
        .background(Tokens.Colour.ground)
    }
}

/// A month's name, for the search results' month lines, read in the zone of
/// the calendar that worked the month out.
enum HistoryMonthHeader {
    static func title(_ start: Date, in timeZone: TimeZone) -> String {
        DateFormats.australian("MMMM yyyy", in: timeZone).string(from: start)
    }
}

/// One bar per calendar day, height by focus. The dates are in the rows
/// below, so the bars carry no labels.
struct HistoryMonthBars: View {
    let daily: [TimeInterval]

    var body: some View {
        let peak = max(daily.max() ?? 0, 1)
        let tallest = 18.zoomed
        HStack(alignment: .bottom, spacing: 2.zoomed) {
            ForEach(Array(daily.enumerated()), id: \.offset) { _, seconds in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(seconds > 0 ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(StoryStyle.line))
                    .frame(maxWidth: .infinity)
                    .frame(height: seconds > 0 ? max(3.zoomed, tallest * seconds / peak) : 2.zoomed)
            }
        }
        .frame(height: tallest, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// A day's title and whether its figure is said on its row.
enum HistoryDayHeader {
    /// The day's focus, unless the day is one finished session and nothing else
    /// and its row shows the same figure: then the header would say it twice.
    /// A running session's row says "in progress", so the header keeps the figure.
    static func showsTotal(day: JournalDay, rows: [DayEntry]) -> Bool {
        guard day.focused > 0 else { return false }
        if rows.count == 1, case .session(let session) = rows[0], !session.isRunning,
           Tokens.duration(day.focused) == Tokens.duration(session.worked) { return false }
        return true
    }

    static func title(_ date: Date, isToday: Bool) -> String {
        isToday ? "Today" : DateFormats.australian("EEE d MMM").string(from: date)
    }
}
