import SwiftUI

/// What a day amounted to, for the calendar to show under its number — the way
/// a flight calendar shows a fare under each date.
struct DayFacts: Equatable {
    var tracked: TimeInterval = 0
    var focused: TimeInterval = 0
    var sessions: Int = 0
    /// Nil lets gallery fixtures retain their declared focused tint; live store
    /// facts provide the stricter focused-active goal credit explicitly.
    var goalAchieved: TimeInterval? = nil
}

/// The month that is showing, and its facts. `@State` is unavailable here.
private final class MonthBox: ObservableObject {
    @Published var month: Date
    @Published var facts: [Date: DayFacts] = [:]
    init(month: Date) { self.month = month }
}

/// A month grid in the app's own vocabulary, for jumping the dashboard to a
/// day — and a map of the month while it is open. Under each date sits that
/// day's focused time; the cell's tint is how far the day got towards the
/// daily goal; the header sums the month. Hover a day for the rest. Days in
/// the future, or before anything was recorded, cannot be picked.
struct DayPickerCalendar: View {
    let selected: Date
    let earliest: Date?
    let goal: TimeInterval
    /// Facts per day for the month containing the date, keyed by start of
    /// day. Called when the shown month changes, never per cell.
    let facts: (Date) -> [Date: DayFacts]
    let onPick: (Date) -> Void

    @StateObject private var shown: MonthBox
    @StateObject private var hover = HoverBox()
    private let calendar = Calendar.current

    init(selected: Date, earliest: Date?, goal: TimeInterval,
         facts: @escaping (Date) -> [Date: DayFacts],
         onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.earliest = earliest
        self.goal = goal
        self.facts = facts
        self.onPick = onPick
        _shown = StateObject(wrappedValue: MonthBox(month: Calendar.current.startOfDay(for: selected)))
    }

    private let cellWidth: CGFloat = 44
    private let cellHeight: CGFloat = 46
    private let gap: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            header
            weekdays
            grid
            legend
        }
        .padding(Tokens.Space.l)
        .frame(width: cellWidth * 7 + gap * 6 + Tokens.Space.l * 2)
        .onAppear { load() }
        .onChange(of: shown.month) { _ in load() }
    }

    // MARK: - Header: the month, summed

    private var header: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthTitle)
                    .font(Tokens.Typography.rowTitle.weight(.semibold))
                    .contentTransition(.numericText())
                Text(monthSummary)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.s)
            if !calendar.isDate(shown.month, equalTo: Date(), toGranularity: .month) {
                Button("Today") { shown.month = calendar.startOfDay(for: Date()) }
                    .buttonStyle(StoryPressStyle())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Tokens.Colour.focus)
                    .padding(.horizontal, Tokens.Space.s)
                    .padding(.vertical, 3)
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                    .background(Tokens.Colour.focus.opacity(0.12), in: Capsule())
            }
            IconButton(systemImage: "chevron.left", help: "Previous month") { step(-1) }
                .opacity(canStep(-1) ? 1 : 0.35)
                .disabled(!canStep(-1))
            IconButton(systemImage: "chevron.right", help: "Next month") { step(1) }
                .opacity(canStep(1) ? 1 : 0.35)
                .disabled(!canStep(1))
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: shown.month)
    }

    /// `11 active days · 38h 56m focused · goal met 4×`, or a plain empty line.
    private var monthSummary: String {
        let days = shown.facts.values
        let active = days.filter { $0.tracked > 0 }.count
        guard active > 0 else { return "Nothing recorded this month" }
        let focused = days.reduce(0) { $0 + $1.focused }
        let met = days.filter { goal > 0 && ($0.goalAchieved ?? $0.focused) >= goal }.count
        var parts = [active == 1 ? "1 active day" : "\(active) active days",
                     "\(Tokens.duration(focused)) focused"]
        if met > 0 { parts.append("goal met \(met)×") }
        return parts.joined(separator: " · ")
    }

    private func step(_ months: Int) {
        guard canStep(months),
              let next = calendar.date(byAdding: .month, value: months, to: shown.month) else { return }
        shown.month = next
    }

    /// Back only as far as the first recorded month; forward only to this one.
    private func canStep(_ months: Int) -> Bool {
        guard let next = calendar.date(byAdding: .month, value: months, to: shown.month) else { return false }
        if months > 0 {
            return calendar.compare(next, to: Date(), toGranularity: .month) != .orderedDescending
        }
        guard let earliest else { return true }
        return calendar.compare(next, to: earliest, toGranularity: .month) != .orderedAscending
    }

    // MARK: - Grid

    /// Two letters each — "Mo Tu We" — so the columns read evenly.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map { String($0.prefix(2)) }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weekdays: some View {
        HStack(spacing: gap) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(Tokens.Typography.tabLabel)
                    .foregroundStyle(.tertiary)
                    .frame(width: cellWidth)
            }
        }
    }

    /// The month's days laid into six weeks, nil for blanks, so the popover
    /// keeps one height from month to month.
    private var weeks: [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: shown.month),
              let dayCount = calendar.range(of: .day, in: .month, for: shown.month)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while days.count < 42 { days.append(nil) }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    private var grid: some View {
        VStack(spacing: gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: gap) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let key = calendar.startOfDay(for: day)
        let facts = shown.facts[key] ?? DayFacts()
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let tooLate = key > calendar.startOfDay(for: Date())
        let tooEarly = earliest.map { key < calendar.startOfDay(for: $0) } ?? false
        let pickable = !tooLate && !tooEarly
        let hovered = hover.id == key.description
        let share = goal > 0 ? (facts.goalAchieved ?? facts.focused) / goal : 0

        return Button { if pickable { onPick(day) } } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(Tokens.Typography.tabLabel
                        .weight(isToday || isSelected ? .semibold : .regular)
                        .monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.onFocus)
                                     : !pickable ? AnyShapeStyle(.quaternary)
                                     : isToday ? AnyShapeStyle(Tokens.Colour.focus)
                                     : AnyShapeStyle(.primary))
                // The fare: focused time, or a quiet dash for a day at the Mac
                // with no session, or nothing at all.
                Text(facts.focused > 0 ? Tokens.duration(facts.focused)
                     : facts.tracked > 0 ? "·" : " ")
                    .font(Tokens.Typography.microValue.monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.onFocus.opacity(0.82))
                                     : facts.focused > 0 ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: cellWidth, height: cellHeight)
            .background(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                        : AnyShapeStyle(Tokens.Colour.focus.opacity(pickable ? tint(share) : 0)),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                    .fill(hovered && pickable && !isSelected ? Tokens.Colour.hover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                    .strokeBorder(Tokens.Colour.focus.opacity(isToday && !isSelected ? 0.7 : 0),
                                  lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if share >= 1 && !isSelected {
                    Image(systemName: "checkmark")
                        .font(Tokens.Typography.micro.weight(.heavy))
                        .foregroundStyle(Tokens.Colour.focus)
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.nested))
        }
        .buttonStyle(StoryPressStyle())
        .disabled(!pickable)
        .onHover { hover.id = $0 ? key.description : nil }
        .help(helpText(day, facts, pickable: pickable))
        .accessibilityLabel(dateAccessibilityLabel(day, facts, pickable: pickable,
                                                   selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// `Tue 19 Aug · 3h 20m focused · 5h 10m at the Mac · 2 sessions`.
    private func helpText(_ day: Date, _ facts: DayFacts, pickable: Bool) -> String {
        guard pickable else { return "" }
        var parts = [Tokens.dayLabel(day)]
        if facts.tracked == 0 { parts.append("nothing recorded"); return parts.joined(separator: " · ") }
        if facts.focused > 0 { parts.append("\(Tokens.duration(facts.focused)) focused") }
        parts.append("\(Tokens.duration(facts.tracked)) at the Mac")
        if facts.sessions > 0 {
            parts.append(facts.sessions == 1 ? "1 session" : "\(facts.sessions) sessions")
        }
        return parts.joined(separator: " · ")
    }

    private func dateAccessibilityLabel(_ day: Date, _ facts: DayFacts,
                                        pickable: Bool, selected: Bool) -> String {
        guard pickable else { return "\(Tokens.longDate(day)), unavailable" }
        var parts = [Tokens.longDate(day), selected ? "selected date" : "not selected"]
        if facts.tracked == 0 {
            parts.append("nothing recorded")
        } else {
            if facts.focused > 0 { parts.append("\(Tokens.spent(facts.focused)) focused") }
            parts.append("\(Tokens.spent(facts.tracked)) at the Mac")
            if facts.sessions > 0 {
                parts.append(facts.sessions == 1 ? "1 session" : "\(facts.sessions) sessions")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Four tint steps by share of the goal — enough to read the month's shape
    /// without turning the grid into a heat map.
    private func tint(_ share: Double) -> Double {
        switch share {
        case ..<0.001: return 0
        case ..<0.5: return 0.10
        case ..<1: return 0.20
        default: return 0.32
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.m) {
                Label("Below half", systemImage: "circle")
                Label("Half or more", systemImage: "circle.lefthalf.filled")
                Label("Goal met", systemImage: "checkmark.circle.fill")
            }
            Text("Share of your \(Tokens.duration(goal)) goal · figure is focused time")
        }
        .font(Tokens.Typography.metadata)
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .combine)
    }

    private func load() {
        shown.facts = facts(shown.month)
    }
}
