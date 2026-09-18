import SwiftUI

/// One year of days: a column per week, a row per weekday, every day on
/// record as a square tinted by its share of the daily goal. The whole year
/// is one glance; a day is one hover; a story is one click.
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
    private let gutter: CGFloat = 30
    private let gap: CGFloat = 2

    /// The first day of the week holding 1 January, and the week count.
    private var origin: Date {
        let jan = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today
        return calendar.dateInterval(of: .weekOfYear, for: jan)?.start ?? jan
    }

    private var weeks: Int {
        let dec = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? today
        let days = calendar.dateComponents([.day], from: origin, to: dec).day ?? 364
        return days / 7 + 1
    }

    var body: some View {
        GeometryReader { geometry in
            let cell = max(4, (geometry.size.width - gutter - CGFloat(weeks - 1) * gap) / CGFloat(weeks))
            VStack(alignment: .leading, spacing: gap) {
                monthLabels(cell: cell)
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: gap) {
                        Text(row % 2 == 0 ? weekdayLabel(row) : " ")
                            .font(Tokens.Typography.micro)
                            .foregroundStyle(.tertiary)
                            .frame(width: gutter - gap, alignment: .leading)
                        ForEach(0..<weeks, id: \.self) { column in
                            square(row: row, column: column, size: cell)
                        }
                    }
                }
            }
        }
        .frame(height: 14 + 7 * 12 + 7 * gap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(year): \(Tokens.spent(facts.focused(inYear: year))) focused")
    }

    private func date(row: Int, column: Int) -> Date? {
        calendar.date(byAdding: .day, value: column * 7 + row, to: origin)
    }

    private func weekdayLabel(_ row: Int) -> String {
        let weekday = (calendar.firstWeekday - 1 + row) % 7 + 1
        return String(calendar.shortWeekdaySymbols[weekday - 1].prefix(1))
    }

    private func monthLabels(cell: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ZStack(alignment: .topLeading) {
                ForEach(1...12, id: \.self) { month in
                    if let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                       let days = calendar.dateComponents([.day], from: origin, to: first).day, days >= 0 {
                        Text(shortMonth(first))
                            .font(Tokens.Typography.micro)
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .offset(x: CGFloat(days / 7) * (cell + gap))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 12)
    }

    private func shortMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    @ViewBuilder private func square(row: Int, column: Int, size: CGFloat) -> some View {
        if let day = date(row: row, column: column),
           calendar.component(.year, from: day) == year, day <= today,
           facts.firstDay.map({ day >= calendar.startOfDay(for: $0) }) ?? true {
            let key = calendar.startOfDay(for: day)
            let focused = facts.focusByDay[key] ?? 0
            let tracked = facts.trackedByDay[key] ?? 0
            let inSelection = selected?.contains(key) ?? false
            let isHovered = hovered.id == key.description
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(fill(focused: focused, tracked: tracked))
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Tokens.Colour.focus, lineWidth: inSelection || isHovered ? 1.5 : 0))
                .frame(width: size, height: 12)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered.id = key.description; onHover(key) }
                    else if hovered.id == key.description { hovered.id = nil; onHover(nil) }
                }
                .onTapGesture { onPick(key, NSEvent.modifierFlags.contains(.shift)) }
                .help(help(day: key, focused: focused, tracked: tracked))
        } else {
            Color.clear.frame(width: size, height: 12)
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
