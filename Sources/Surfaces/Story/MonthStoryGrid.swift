import SwiftUI

enum MonthStoryLayout {
    static let cellHeight: CGFloat = 54

    static func durationLabel(for seconds: TimeInterval) -> String {
        guard seconds != 0 else { return "—" }
        return DurationText.precise(seconds)
    }
}

/// The month as a calendar of real days: each cell carries its own focused
/// figure and is tinted by its focused duration relative to this month's
/// busiest day. Selection previews a day; its named action opens the story.
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
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            let table = facts
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: Tokens.Space.s) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            MonthDayCell(day: day,
                                         facts: table[calendar.startOfDay(for: day)],
                                         maximumFocus: table.values.map(\.focused).max() ?? 0,
                                         isSelected: isSelected(day),
                                         isToday: calendar.isDateInToday(day),
                                         isFuture: day > calendar.startOfDay(for: store.now())) {
                                navigation.selectStoryDay(day)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(StoryStyle.well.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .frame(height: MonthStoryLayout.cellHeight)
                                .accessibilityHidden(true)
                        }
                    }
                    weekTotal(week, table: table)
                }
            }
            legend
        }
        .padding(18)
        .background(StoryStyle.card,
                    in: RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous)
            .strokeBorder(StoryStyle.line))
        .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
        .animation(Tokens.Motion.animation(Tokens.Motion.rise, reduceMotion: reduceMotion),
                   value: navigation.storySelectedDay)
    }

    private var headerRow: some View {
        HStack(spacing: Tokens.Space.s) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                Text(name.uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("WEEK")
                .font(.caption2.weight(.bold))
                .kerning(0.6)
                .foregroundStyle(.secondary)
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
            Text(store.storyFocusSummary.activeDays > 0
                 ? "\(store.storyFocusSummary.activeDays) of \(store.reviewSummary.totalDays) "
                   + "days had focus. Select a day to inspect it."
                 : "No focus recorded in this month yet.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.m)
            HStack(spacing: 3) {
                Text("Less").font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                ForEach([0.16, 0.44, 0.72, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Tokens.Palette.workType(.deepWork).opacity(level))
                        .frame(width: 12, height: 12)
                }
                Text("More").font(Tokens.Typography.metadata).foregroundStyle(.secondary)
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

/// One square calendar cell. Goal achievement is not encoded here: it has a
/// different denominator from focused duration and belongs in the daily ring.
struct MonthDayCell: View {
    let day: Date
    let facts: DayFacts?
    let maximumFocus: TimeInterval
    let isSelected: Bool
    let isToday: Bool
    var isFuture = false
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var focused: TimeInterval { facts?.focused ?? 0 }

    private var paint: StoryHeatmap.Paint {
        StoryHeatmap.paint(seconds: focused, peak: maximumFocus, dark: scheme == .dark)
    }

    var body: some View {
        Button(action: onSelect) {
            face
        }
        .buttonStyle(StoryPressStyle())
        .disabled(isFuture)
        .opacity(isFuture ? 0.45 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Preview this day below the calendar")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    private var face: some View {
        shape.fill(Color(NSColor(hex: paint.background)))
            .frame(maxWidth: .infinity)
            .frame(height: MonthStoryLayout.cellHeight)
            .overlay(alignment: .topLeading) {
              VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Text(dayNumber)
                    .font(.caption.weight(.bold).monospacedDigit())
                Spacer(minLength: 0)
                if isToday {
                    Circle().fill(Color(NSColor(hex: paint.foreground)))
                        .frame(width: 4, height: 4)
                }
            }
            Spacer(minLength: 0)
            Text(MonthStoryLayout.durationLabel(for: focused))
                .font(.system(size: 10).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              }
        .foregroundStyle(Color(NSColor(hex: paint.foreground)))
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        .overlay(shape.strokeBorder(StoryStyle.action, lineWidth: isSelected ? 2 : 0))
        .contentShape(shape)
    }

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    private var accessibilityLabel: String {
        var parts = [Tokens.longDate(day)]
        parts.append(focused > 0 ? "\(Tokens.spent(focused)) focused" : "no focus recorded")
        if isToday { parts.append("today") }
        return parts.joined(separator: ", ")
    }
}
