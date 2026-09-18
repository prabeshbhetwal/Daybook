import SwiftUI

/// One bar per period on one scale, oldest at the leading edge. The marks are
/// the week chart's: solid logged focus over pale recorded app use, a flat
/// tick for a period that holds nothing.
struct InsightTrendChart: View {
    /// Oldest first.
    let periods: [StoryPeriodProjection]
    let scope: InsightRange
    let selectedID: String?
    let onPick: (StoryPeriodProjection) -> Void
    @StateObject private var hovered = HoverBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var peak: TimeInterval {
        max(periods.map { max($0.focused, $0.tracked) }.max() ?? 0, 1)
    }

    private var unit: String {
        switch scope {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        }
    }

    /// Every bar carries its figure while there is room for one.
    private var labelsEveryBar: Bool { periods.count <= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Focus by \(unit)")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: periods.count > 20 ? 3 : Tokens.Space.s) {
                ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                    column(for: period, index: index)
                }
            }
            .frame(height: 208)
            Text(caption)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus by \(unit)")
    }

    private var caption: String {
        if let period = periods.first(where: { $0.id == hovered.id }) {
            return spoken(period)
        }
        return "Solid bars are logged focus; the pale bar behind is recorded app use. "
            + "Pick a bar to read that \(unit)."
    }

    private func column(for period: StoryPeriodProjection, index: Int) -> some View {
        let isSelected = period.id == selectedID
        let isHovered = period.id == hovered.id
        let showsFigure = labelsEveryBar || isSelected || isHovered
        return Button { onPick(period) } label: {
            VStack(spacing: Tokens.Space.xs) {
                // The figure never widens its column: forty-two days must
                // still fit the measure, so a label wider than its bar is
                // drawn over the neighbours rather than pushing them.
                Color.clear
                    .frame(height: 16)
                    .overlay {
                        Text(period.focused > 0 ? Tokens.duration(period.focused) : "—")
                            .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                            .foregroundStyle(period.focused > 0 ? .primary : .tertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .opacity(showsFigure ? 1 : 0)
                    }
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        if period.tracked > 0 {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                                .fill(Tokens.Colour.focus.opacity(0.16))
                                .frame(height: height(period.tracked, in: geometry.size.height))
                        }
                        if period.focused > 0 {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                                .fill(isSelected || period.isCurrent && selectedID == nil
                                      ? Tokens.Colour.focus : Tokens.Colour.focus.opacity(0.72))
                                .frame(height: height(period.focused, in: geometry.size.height))
                        } else {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                                .fill(Tokens.Colour.elevated)
                                .frame(height: 3)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(Tokens.Motion.animation(Tokens.Motion.settle, reduceMotion: reduceMotion),
                               value: period.focused)
                }
                Color.clear
                    .frame(height: 14)
                    .overlay {
                        Text(axisLabel(period, index: index))
                            .font(Tokens.Typography.microLabel.weight(isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                                                        : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .fixedSize()
                    }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true))
        .onHover { inside in
            if inside { hovered.id = period.id } else if hovered.id == period.id { hovered.id = nil }
        }
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                   value: isSelected)
        .accessibilityLabel(spoken(period))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Show this \(unit)")
    }

    private func height(_ value: TimeInterval, in available: CGFloat) -> CGFloat {
        max(5, available * CGFloat(min(1, max(0, value / peak))))
    }

    /// Dense ranges label only where a reader needs an anchor: each Monday
    /// for days, every bar otherwise.
    private func axisLabel(_ period: StoryPeriodProjection, index: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        switch scope {
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: period.start)
        case .month:
            formatter.dateFormat = "MMM"
            return formatter.string(from: period.start).uppercased()
        case .week:
            formatter.dateFormat = periods.count > 8 ? "d/M" : "d MMM"
            return formatter.string(from: period.start).uppercased()
        case .day:
            if periods.count > 14 {
                let calendar = Calendar.current
                guard calendar.component(.weekday, from: period.start) == calendar.firstWeekday
                        || index == periods.count - 1 else { return " " }
                formatter.dateFormat = "d/M"
                return formatter.string(from: period.start)
            }
            formatter.dateFormat = "EEE d"
            return formatter.string(from: period.start).uppercased()
        }
    }

    private func spoken(_ period: StoryPeriodProjection) -> String {
        let name = InsightRangeReading.label(period)
        guard period.focused > 0 || period.tracked > 0 else { return "\(name): nothing recorded." }
        var parts = [period.focused > 0 ? "\(Tokens.preciseDuration(period.focused)) focused" : "no logged focus"]
        if period.tracked > 0 { parts.append("\(Tokens.duration(period.tracked)) recorded app use") }
        if period.isCurrent { parts.append("so far") }
        return "\(name): " + parts.joined(separator: ", ") + "."
    }
}

/// When focus happens: a cell per clock hour, in rows that follow the span
/// being read (each day, each weekday, each month), one hue whose strength is
/// the focused time in that cell. Only the hours that hold focus
/// are drawn, so a nine-to-five reader is not shown sixteen empty columns.
struct InsightHourGrid: View {
    let facts: InsightRangeFacts
    @StateObject private var hovered = HoverBox()

    private let labelWidth: CGFloat = 46

    /// Many rows (six weeks of days) draw shorter, so the grid stays a glance.
    private var dense: Bool { facts.grid.count > 14 }
    private var cellHeight: CGFloat { dense ? 7 : 18 }
    private var rowGap: CGFloat { dense ? 2 : 3 }

    var body: some View {
        let hours = Array(facts.visibleHours)
        return VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("When you focus")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: rowGap) {
                ForEach(Array(facts.rowLabels.enumerated()), id: \.offset) { row, label in
                    HStack(spacing: 3) {
                        Text(dense && row % 7 != 0 ? " " : label)
                            .font(Tokens.Typography.microLabel)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, alignment: .leading)
                        ForEach(hours, id: \.self) { hour in
                            cell(row: row, hour: hour)
                        }
                    }
                }
                // Labels sit at their column's edge by position, so a narrow
                // column never widens the grid past its measure.
                GeometryReader { geometry in
                    let column = (geometry.size.width - labelWidth - 3) / CGFloat(max(1, hours.count))
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        if hour % 3 == 0 {
                            Text(Self.hourLabel(hour))
                                .font(Tokens.Typography.microLabel)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                                .offset(x: labelWidth + 3 + column * CGFloat(index))
                        }
                    }
                }
                .frame(height: 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            Text(caption)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cell(row: Int, hour: Int) -> some View {
        let seconds = facts.grid[row][hour]
        let key = "\(row)-\(hour)"
        let strength = facts.gridPeak > 0 ? seconds / facts.gridPeak : 0
        return RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous)
            .fill(seconds > 0 ? AnyShapeStyle(Tokens.Colour.focus.opacity(0.18 + 0.82 * strength))
                              : AnyShapeStyle(Tokens.Colour.elevated))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous)
                .strokeBorder(Tokens.Colour.focus, lineWidth: hovered.id == key ? 1.5 : 0))
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .onHover { inside in
                if inside { hovered.id = key } else if hovered.id == key { hovered.id = nil }
            }
    }

    private var caption: String {
        if let key = hovered.id {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2, facts.grid.indices.contains(parts[0]) {
                let seconds = facts.grid[parts[0]][parts[1]]
                let place = facts.rowPhrases.indices.contains(parts[0]) ? facts.rowPhrases[parts[0]] : ""
                let when = "\(Self.hourLabel(parts[1])) – \(Self.hourLabel(parts[1] + 1)) \(place)"
                return seconds > 0 ? "\(Tokens.preciseDuration(seconds)) focused, \(when)."
                                   : "No focus, \(when)."
            }
        }
        return summary
    }

    private var summary: String {
        guard let window = facts.bestWindow else {
            return "A stronger cell means more focused time in that hour, across the whole range."
        }
        return "Most focus lands between \(Self.hourLabel(window.startHour)) and "
            + "\(Self.hourLabel(window.startHour + 2)). A stronger cell means more focused time in that hour."
    }

    static func hourLabel(_ hour: Int) -> String {
        let wrapped = ((hour % 24) + 24) % 24
        let twelve = wrapped % 12 == 0 ? 12 : wrapped % 12
        return "\(twelve) \(wrapped < 12 ? "am" : "pm")"
    }
}

/// Months side by side as small calendars. Three tall bars compare three
/// totals and nothing else; a calendar per month shows the total, how many
/// days carried it, and where in the month they fell, in the grid the app
/// already uses for a month.
struct InsightMonthCalendars: View {
    /// Oldest first.
    let periods: [StoryPeriodProjection]
    let goal: TimeInterval
    let selectedID: String?
    let onPick: (StoryPeriodProjection) -> Void
    @StateObject private var hovered = HoverBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let calendar = Calendar.current
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Focus by month")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                ForEach(periods) { period in month(period) }
            }
            Text(caption)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus by month")
    }

    private var caption: String {
        if let key = hovered.id, let day = periods.flatMap(\.days).first(where: { $0.id == key }) {
            guard day.focused > 0 || day.tracked > 0 else {
                return "\(Tokens.longDate(day.date)): nothing recorded."
            }
            var parts = [day.focused > 0 ? "\(Tokens.preciseDuration(day.focused)) focused" : "no logged focus"]
            if day.tracked > 0 { parts.append("\(Tokens.duration(day.tracked)) recorded app use") }
            return "\(Tokens.longDate(day.date)): " + parts.joined(separator: ", ") + "."
        }
        let scale = goal > 0 ? "a stronger square is more of your \(Tokens.duration(goal)) daily goal"
                             : "a stronger square is more focus"
        return "Each square is a day; \(scale). Pick a month to read it."
    }

    private func month(_ period: StoryPeriodProjection) -> some View {
        let isSelected = period.id == selectedID
        let focusedDays = period.days.filter { $0.focused > 0 }.count
        return Button { onPick(period) } label: {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(period))
                        .font(Tokens.Typography.microLabel.weight(isSelected ? .bold : .semibold))
                        .kerning(0.6)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                                                    : AnyShapeStyle(.secondary))
                    Text(period.focused > 0 ? Tokens.duration(period.focused) : "—")
                        .font(Tokens.Typography.sectionTitle.monospacedDigit())
                        .foregroundStyle(period.focused > 0 ? .primary : .tertiary)
                    Text(focusedDays == 0 ? "no focused days"
                         : focusedDays == 1 ? "1 focused day" : "\(focusedDays) focused days")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: gap) {
                    ForEach(Array(weeks(period).enumerated()), id: \.offset) { _, week in
                        HStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                cell(day, in: period)
                            }
                        }
                    }
                }
            }
            .padding(Tokens.Space.s)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.focus.opacity(isSelected ? 0.45 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                   value: isSelected)
        .accessibilityLabel("\(InsightRangeReading.label(period)): \(Tokens.spent(period.focused)) focused "
                            + "on \(focusedDays) days")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Show this month")
    }

    private func title(_ period: StoryPeriodProjection) -> String {
        InsightRangeReading.label(period).uppercased() + (period.isCurrent ? " · SO FAR" : "")
    }

    /// The month's dates in six week rows, nil for blanks, so every month
    /// stands the same height beside its neighbours.
    private func weeks(_ period: StoryPeriodProjection) -> [[Date?]] {
        guard let count = calendar.range(of: .day, in: .month, for: period.start)?.count else { return [] }
        let lead = (calendar.component(.weekday, from: period.start) - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<count {
            days.append(calendar.date(byAdding: .day, value: offset, to: period.start))
        }
        while days.count < 42 { days.append(nil) }
        return stride(from: 0, to: 42, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    @ViewBuilder private func cell(_ date: Date?, in period: StoryPeriodProjection) -> some View {
        if let date {
            let day = period.days.first { calendar.isDate($0.date, inSameDayAs: date) }
            let focused = day?.focused ?? 0
            let isHovered = day != nil && hovered.id == day?.id
            RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous)
                .fill(focused > 0 ? AnyShapeStyle(Tokens.Colour.focus.opacity(strength(day)))
                                  : AnyShapeStyle(Tokens.Colour.elevated.opacity(day == nil ? 0.45 : 1)))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.mark, style: .continuous)
                    .strokeBorder(Tokens.Colour.focus, lineWidth: isHovered ? 1.5 : 0))
                .overlay {
                    Text("\(calendar.component(.day, from: date))")
                        .font(Tokens.Typography.micro.monospacedDigit())
                        .foregroundStyle(focused > 0 && strength(day) > 0.6
                                         ? AnyShapeStyle(Tokens.Colour.onFocus)
                                         : AnyShapeStyle(.tertiary))
                }
                .aspectRatio(1.25, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .onHover { inside in
                    guard let id = day?.id else { return }
                    if inside { hovered.id = id } else if hovered.id == id { hovered.id = nil }
                }
        } else {
            Color.clear.aspectRatio(1.25, contentMode: .fit).frame(maxWidth: .infinity)
        }
    }

    /// Share of the daily goal where there is one, else of the range's best day.
    private func strength(_ day: StoryDayProjection?) -> Double {
        guard let day, day.focused > 0 else { return 0 }
        let reference = goal > 0 ? goal
            : max(periods.flatMap(\.days).map(\.focused).max() ?? 1, 1)
        return 0.22 + 0.78 * min(1, day.focused / reference)
    }
}

/// Days as the strips the story and History already draw: one row per day,
/// newest at the top, sessions in their category's colour on a shared clock.
/// Weeks are separated by a breath of space, so a fortnight reads as two rows
/// of a calendar rather than fourteen lines.
struct InsightDayStrips: View {
    /// Newest first.
    let periods: [StoryPeriodProjection]
    @StateObject private var hovered = HoverBox()
    private let calendar = Calendar.current
    private let labelWidth: CGFloat = 46

    private var days: [StoryDayProjection] { periods.compactMap { $0.days.first } }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("When you focus")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            HistoryStripAxis(leading: labelWidth + Tokens.Space.s, trailing: 0)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    if index > 0, calendar.component(.weekday, from: day.date) == lastWeekday {
                        Color.clear.frame(height: Tokens.Space.s)
                    }
                    row(day)
                }
            }
            .accessibilityElement(children: .contain)
            Text(caption)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The last day of the week in the calendar's order, where a gap goes.
    private var lastWeekday: Int { (calendar.firstWeekday + 5) % 7 + 1 }

    private func row(_ day: StoryDayProjection) -> some View {
        let isHovered = hovered.id == day.id
        let isWeekend = calendar.isDateInWeekend(day.date)
        return HStack(spacing: Tokens.Space.s) {
            Text(dayLabel(day.date))
                .font(Tokens.Typography.microLabel)
                .foregroundStyle(isHovered ? AnyShapeStyle(Tokens.Colour.focus)
                                 : isWeekend ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            HistoryDayStrip(date: day.date, entries: day.sessions, height: 10)
            Text(day.focused > 0 ? Tokens.duration(day.focused) : "")
                .font(Tokens.Typography.microValue.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered.id = day.id } else if hovered.id == day.id { hovered.id = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(day))
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date).uppercased()
    }

    private var caption: String {
        if let day = days.first(where: { $0.id == hovered.id }) { return spoken(day) }
        return "Each row is a day; each mark is a session, in its category's colour. Grey marks are recorded breaks."
    }

    private func spoken(_ day: StoryDayProjection) -> String {
        guard day.focused > 0 || day.tracked > 0 else { return "\(Tokens.longDate(day.date)): nothing recorded." }
        var parts = [day.focused > 0 ? "\(Tokens.preciseDuration(day.focused)) focused" : "no logged focus"]
        let count = day.focusSessionCount
        if count > 0 { parts.append(count == 1 ? "1 session" : "\(count) sessions") }
        if day.tracked > 0 { parts.append("\(Tokens.duration(day.tracked)) recorded app use") }
        return "\(Tokens.longDate(day.date)): " + parts.joined(separator: ", ") + "."
    }
}
