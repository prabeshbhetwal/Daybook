import Foundation

/// The words History's day grid shows and speaks.
enum HistoryGridWords {
    /// `Thu 12 Nov · 9h 20m`, `Sun 15 Nov (today) · 1h 5m so far`, `Mon 16 Nov · still to come`.
    static func readout(_ cell: HistoryGridCell, calendar: Calendar) -> String {
        let date = DateFormats.australian("EEE d MMM", in: calendar.timeZone).string(from: cell.day)
        return "\(date)\(cell.isToday ? " (today)" : "") · \(figure(cell, duration: Tokens.duration))"
    }

    /// `Thursday 12 November, 9 hours 20 minutes`: a day's button under its month.
    static func spokenDay(_ cell: HistoryGridCell, calendar: Calendar) -> String {
        let date = DateFormats.australian("EEEE d MMMM", in: calendar.timeZone).string(from: cell.day)
        return "\(date), \(figure(cell, duration: Tokens.spent))"
    }

    /// A block's VoiceOver value, from its own cells: "61 hours 10 minutes across 9 days".
    static func blockValue(_ block: HistoryGridBlock) -> String {
        let focused = block.cells.reduce(0) { $0 + $1.focused }
        let days = block.cells.filter { $0.focused > 0 }.count
        guard focused > 0 else { return "no focus recorded" }
        return "\(Tokens.spent(focused)) across \(days == 1 ? "1 day" : "\(days) days")"
    }

    static func blockLabel(_ block: HistoryGridBlock, calendar: Calendar) -> String {
        DateFormats.australian("MMMM yyyy", in: calendar.timeZone).string(from: block.month.start)
    }

    /// The month above a block, with its year where the block shows one.
    static func monthLabel(_ block: HistoryGridBlock, calendar: Calendar) -> String {
        DateFormats.australian(block.showsYear ? "MMM yyyy" : "MMM", in: calendar.timeZone).string(from: block.month.start)
    }

    /// nil is "still to come".
    static let legend: [(HistoryFocusStep?, String)] = [
        (HistoryFocusStep.none, "none"), (.under2h, "under 2h"), (.under5h, "2 to 5h"),
        (.under8h, "5 to 8h"), (.over8h, "8h or more"), (nil, "still to come")
    ]

    private static func figure(_ cell: HistoryGridCell, duration: (TimeInterval) -> String) -> String {
        guard cell.kind != .toCome else { return "still to come" }
        if cell.focused > 0 { return duration(cell.focused) + (cell.isToday ? " so far" : "") }
        return cell.isToday ? "no focus yet" : "no focus"
    }
}
