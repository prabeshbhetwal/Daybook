import SwiftUI

/// One year of days: a row per month, a column per day of the month, every
/// day on record as a cell tinted by its share of the daily goal. The year
/// is one glance, each month one line, and a cell is wide enough to click.
struct HistoryYearMap: View {
    let year: Int
    let facts: HistoryArchiveFacts
    let goal: TimeInterval
    let today: Date
    let selected: ClosedRange<Date>?
    let onHover: (Date?) -> Void
    let onPick: (Date, Bool) -> Void
    @StateObject private var hovered = HoverBox()
    private let calendar = Calendar.current
    private let gutter: CGFloat = 36
    private let gap: CGFloat = 3
    private let rowHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            dayNumbers
            ForEach(1...12, id: \.self) { month in
                HStack(spacing: gap) {
                    Text(monthLabel(month))
                        .font(Tokens.Typography.microLabel)
                        .foregroundStyle(.secondary)
                        .frame(width: gutter - gap, alignment: .leading)
                    ForEach(1...31, id: \.self) { day in
                        cell(month: month, day: day)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(year): \(Tokens.spent(facts.focused(inYear: year))) focused")
    }

    private var dayNumbers: some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: gutter - gap, height: 1)
            ForEach(1...31, id: \.self) { day in
                Text(day == 1 || day % 5 == 0 ? "\(day)" : " ")
                    .font(Tokens.Typography.micro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 12)
    }

    private func monthLabel(_ month: Int) -> String {
        String(calendar.shortMonthSymbols[month - 1].prefix(3)).uppercased()
    }

    private func date(month: Int, day: Int) -> Date? {
        guard let count = calendar.range(of: .day, in: .month,
                                         for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? today)?.count,
              day <= count else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    @ViewBuilder private func cell(month: Int, day: Int) -> some View {
        if let date = date(month: month, day: day) {
            let key = calendar.startOfDay(for: date)
            // Days before the first record still draw, faintly, so each
            // month keeps its shape; days after today do not exist yet.
            let past = key <= today
            let onRecord = past && (facts.firstDay.map { key >= calendar.startOfDay(for: $0) } ?? true)
            let focused = facts.focusByDay[key] ?? 0
            let tracked = facts.trackedByDay[key] ?? 0
            let inSelection = selected?.contains(key) ?? false
            let isHovered = hovered.id == key.description
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(onRecord ? fill(focused: focused, tracked: tracked)
                      : past ? Tokens.Colour.elevated.opacity(0.45) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Tokens.Colour.focus, lineWidth: inSelection || isHovered ? 1.5 : 0))
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .contentShape(Rectangle())
                .onHover { inside in
                    guard onRecord else { return }
                    if inside { hovered.id = key.description; onHover(key) }
                    else if hovered.id == key.description { hovered.id = nil; onHover(nil) }
                }
                .onTapGesture { if onRecord { onPick(key, NSEvent.modifierFlags.contains(.shift)) } }
                .help(onRecord ? help(day: key, focused: focused, tracked: tracked) : "")
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: rowHeight)
        }
    }

    private func fill(focused: TimeInterval, tracked: TimeInterval) -> Color {
        guard focused > 0 else {
            return tracked > 0 ? Tokens.Colour.focus.opacity(0.10) : Tokens.Colour.elevated
        }
        let reference = goal > 0 ? goal : max(facts.focusByDay.values.max() ?? 1, 1)
        return Tokens.Colour.focus.opacity(0.28 + 0.72 * min(1, focused / reference))
    }

    private func help(day: Date, focused: TimeInterval, tracked: TimeInterval) -> String {
        guard focused > 0 || tracked > 0 else { return "\(Tokens.dayLabel(day)) · nothing recorded" }
        var parts = [Tokens.dayLabel(day)]
        if focused > 0 { parts.append("\(Tokens.duration(focused)) focused") }
        if tracked > 0 { parts.append("\(Tokens.duration(tracked)) at the Mac") }
        return parts.joined(separator: " · ")
    }
}
