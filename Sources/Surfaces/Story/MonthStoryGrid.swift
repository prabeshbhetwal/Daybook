import SwiftUI

/// The month as a calendar of real days: each cell carries its own focused
/// figure and is tinted by how much of the goal it reached, with the week's
/// total on the trailing edge. Clicking a day opens that day's story — the
/// route the month exists to offer.
struct MonthStoryGrid: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { Calendar.current }

    /// The weeks of the shown month, each padded to seven days so the grid
    /// keeps its columns. Nil marks a cell outside the month.
    private var weeks: [[Date?]] {
        let month = store.reviewPeriodStart
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard let first = days.first else { return [] }
        // Monday-first, matching the rest of the app's week.
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    private var facts: [Date: DayFacts] { store.dayFacts(inMonthOf: store.reviewPeriodStart) }

    var body: some View {
        SurfacePanel(showsHeader: false) {
            headerRow
            let table = facts
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: Tokens.Space.s) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            MonthDayCell(day: day,
                                         facts: table[calendar.startOfDay(for: day)],
                                         goal: store.goal.goal,
                                         isSelected: isSelected(day),
                                         isToday: calendar.isDateInToday(day)) {
                                navigation.selectStoryDay(day)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Tokens.Colour.elevated.opacity(0.4))
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                    weekTotal(week, table: table)
                }
            }
            legend
        }
        .animation(Tokens.Motion.animation(Tokens.Motion.rise, reduceMotion: reduceMotion),
                   value: navigation.storySelectedDay)
    }

    private var headerRow: some View {
        HStack(spacing: Tokens.Space.s) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                Text(name.uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("WEEK")
                .font(.caption2.weight(.bold))
                .kerning(0.6)
                .foregroundStyle(.quaternary)
                .frame(width: 62, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }

    private func weekTotal(_ week: [Date?], table: [Date: DayFacts]) -> some View {
        let total = week.compactMap { $0 }
            .compactMap { table[calendar.startOfDay(for: $0)]?.focused }
            .reduce(0, +)
        return Text(total > 0 ? Tokens.duration(total) : "—")
            .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
            .foregroundStyle(total > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            .frame(width: 62, alignment: .trailing)
            .accessibilityLabel(total > 0 ? "Week total \(Tokens.spent(total))" : "No focus this week")
    }

    private var legend: some View {
        HStack {
            Text(store.reviewSummary.activeDays > 0
                 ? "\(store.reviewSummary.activeDays) of \(store.reviewSummary.totalDays) "
                   + "days had focus. Click a day to open its story."
                 : "No focus recorded in this month yet.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.m)
            HStack(spacing: Tokens.Space.xs) {
                Text("Less").font(Tokens.Typography.metadata).foregroundStyle(.tertiary)
                ForEach([0.16, 0.44, 0.72, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Tokens.Palette.workType(.deepWork).opacity(level))
                        .frame(width: 12, height: 12)
                }
                Text("More").font(Tokens.Typography.metadata).foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Darker cells mean more focused time")
        }
        .padding(.top, Tokens.Space.xs)
    }

    private func isSelected(_ day: Date) -> Bool {
        guard let selected = navigation.storySelectedDay else { return false }
        return calendar.isDate(day, inSameDayAs: selected)
    }
}

/// One day in the month grid. The tint is the day's share of the goal, so the
/// month reads as a heat map of real progress rather than of raw presence.
struct MonthDayCell: View {
    let day: Date
    let facts: DayFacts?
    let goal: TimeInterval
    let isSelected: Bool
    let isToday: Bool
    let onSelect: () -> Void

    private var focused: TimeInterval { facts?.focused ?? 0 }

    /// Nil when the day recorded nothing at all, which is drawn as a quiet well
    /// rather than as the palest step of the ramp — absence is not a low score.
    private var level: Double? {
        guard focused > 0 else { return nil }
        guard goal > 0 else { return 0.6 }
        return min(1, max(0.16, focused / goal))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.caption.weight(.bold).monospacedDigit())
                    Spacer(minLength: 0)
                    if isToday {
                        Text("TODAY")
                            .font(.system(size: 8, weight: .bold))
                            .kerning(0.4)
                    }
                }
                Spacer(minLength: 0)
                Text(focused > 0 ? Tokens.duration(focused) : "—")
                    .font(.system(size: 10).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(readableForeground)
            .padding(7)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(background)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Tokens.Colour.focus, lineWidth: isSelected ? 2 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Open this day as a story")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var background: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(level.map { Tokens.Palette.workType(.deepWork).opacity($0) }
                  ?? Tokens.Colour.elevated)
    }

    /// White only where the fill is dark enough to carry it.
    private var readableForeground: Color {
        guard let level, level >= 0.55 else { return .primary }
        return .white
    }

    private var accessibilityLabel: String {
        var parts = [Tokens.longDate(day)]
        parts.append(focused > 0 ? "\(Tokens.spent(focused)) focused" : "no focus recorded")
        if isToday { parts.append("today") }
        return parts.joined(separator: ", ")
    }
}
