import Foundation

/// How much focus a day held, as one of the five shades the grid draws.
enum HistoryFocusStep: Int, CaseIterable, Comparable {
    case none, under2h, under5h, under8h, over8h

    static func < (lhs: HistoryFocusStep, rhs: HistoryFocusStep) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Half-open, so exactly 2, 5 and 8 hours step up. A second of focus is
    /// already a shade; only no focus at all is none.
    static func step(for focused: TimeInterval) -> HistoryFocusStep {
        switch focused {
        case ...0: return .none
        case ..<7_200: return .under2h
        case ..<18_000: return .under5h
        case ..<28_800: return .under8h
        default: return .over8h
        }
    }
}

/// One calendar day in the grid.
struct HistoryGridCell: Equatable {
    enum Kind: Equatable { case recorded(HistoryFocusStep), toCome }

    /// The start of the day in the grid's calendar.
    let day: Date
    let focused: TimeInterval
    let kind: Kind
    let isToday: Bool
}

/// One month of cells, drawn as a block of weeks.
struct HistoryGridBlock: Equatable, Identifiable {
    /// The whole calendar month, though the first block's cells may start later in it.
    let month: DateInterval
    /// Rows above the first cell, Monday = 0.
    let leadingBlanks: Int
    let cells: [HistoryGridCell]
    let showsYear: Bool

    var id: Date { month.start }
}

struct HistoryDayGrid: Equatable {
    let blocks: [HistoryGridBlock]
}

/// Lays the recorded days out as month blocks, oldest first. Pure, like the
/// tree builder: the checks hand it any index and any today.
enum HistoryDayGridBuilder {
    static let maximumMonths = 12

    /// The weekday letter beside each of the seven rows, Monday first.
    static let weekdayLetters = ["M", "", "W", "", "F", "", ""]

    /// Built from the day index alone, so it can be cached. Today is
    /// `top.today`, in `calendar`. nil when the top is a week or there is
    /// no recorded day. Runs from the month of the first recorded day, or of
    /// the month eleven before today's if that is later, to today's month;
    /// the first block starts at the first recorded day, the others on the 1st.
    static func grid(top: HistoryTop, byDate: [Date: HistoryDay], calendar: Calendar) -> HistoryDayGrid? {
        guard top.place?.level != .week, !byDate.isEmpty else { return nil }
        let today = calendar.startOfDay(for: top.today)
        let thisMonth = HistoryTreeBuilder.period(.month, containing: today, calendar: calendar)
        let earliest = calendar.date(byAdding: .month, value: 1 - maximumMonths, to: thisMonth.start)
            .map { HistoryTreeBuilder.period(.month, containing: $0, calendar: calendar).start } ?? thisMonth.start
        let first = max(calendar.startOfDay(for: top.firstDay), earliest)
        let spansYears = calendar.component(.year, from: first) != calendar.component(.year, from: today)
        var blocks: [HistoryGridBlock] = []
        var month = HistoryTreeBuilder.period(.month, containing: first, calendar: calendar)
        while month.start <= thisMonth.start {
            let start = max(first, month.start)
            var cells: [HistoryGridCell] = []
            var day = start
            while day < month.end {
                cells.append(cell(day, focused: byDate[day]?.focused ?? 0, today: today))
                day = HistoryTreeBuilder.dayAfter(day, calendar: calendar)
            }
            blocks.append(HistoryGridBlock(
                month: month,
                // Weekday 1 is Sunday, so Monday is 2 and maps to 0.
                leadingBlanks: (calendar.component(.weekday, from: start) + 5) % 7,
                cells: cells,
                showsYear: spansYears && (blocks.isEmpty || calendar.component(.month, from: month.start) == 1)))
            month = HistoryTreeBuilder.period(.month, containing: month.end, calendar: calendar)
        }
        return HistoryDayGrid(blocks: blocks)
    }

    /// The same grid as it stands on `today`: today's cell rebuilt from
    /// `live` (or left as indexed when `live` is nil), `isToday` cleared on
    /// every other cell, and any cell on or before `today` that was still
    /// `.toCome` made `.recorded`. Needs no earlier value: cells are
    /// replaced, not adjusted. A live day that is not today is ignored.
    static func patching(_ grid: HistoryDayGrid, live: HistoryDay?, today: Date, calendar: Calendar) -> HistoryDayGrid {
        let today = calendar.startOfDay(for: today)
        let live = live.flatMap { calendar.startOfDay(for: $0.date) == today ? $0 : nil }
        func patched(_ old: HistoryGridCell) -> HistoryGridCell {
            cell(old.day, focused: old.day == today ? (live?.focused ?? old.focused) : old.focused, today: today)
        }
        return HistoryDayGrid(blocks: grid.blocks.map {
            HistoryGridBlock(month: $0.month, leadingBlanks: $0.leadingBlanks, cells: $0.cells.map(patched),
                             showsYear: $0.showsYear)
        })
    }

    /// A day's cell on `today`: recorded up to today, to come after it.
    private static func cell(_ day: Date, focused: TimeInterval, today: Date) -> HistoryGridCell {
        guard day <= today else { return HistoryGridCell(day: day, focused: 0, kind: .toCome, isToday: false) }
        return HistoryGridCell(day: day, focused: focused, kind: .recorded(.step(for: focused)), isToday: day == today)
    }
}
