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
    /// The day under the pointer, for previewing a range being drawn.
    @Published var hovered: Date?
    init(month: Date) { self.month = month }
}

/// The first day of a range being picked, until the second click lands.
private final class RangeAnchorBox: ObservableObject {
    @Published var day: Date?
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
    /// Range mode, for History: the span currently chosen. The same grid, the
    /// same figures; two clicks pick a first and a last day instead of one.
    let range: ClosedRange<Date>?
    let onPickRange: ((Date, Date) -> Void)?

    @StateObject private var shown: MonthBox
    @StateObject private var hover = HoverBox()
    @StateObject private var anchor = RangeAnchorBox()
    private let calendar = Calendar.current

    init(selected: Date, earliest: Date?, goal: TimeInterval,
         facts: @escaping (Date) -> [Date: DayFacts],
         onPick: @escaping (Date) -> Void) {
        self.selected = selected
        self.earliest = earliest
        self.goal = goal
        self.facts = facts
        self.onPick = onPick
        self.range = nil
        self.onPickRange = nil
        _shown = StateObject(wrappedValue: MonthBox(month: Calendar.current.startOfDay(for: selected)))
    }

    /// The calendar as a range picker. It opens on the month the range ends in.
    init(range: ClosedRange<Date>, earliest: Date?, goal: TimeInterval,
         facts: @escaping (Date) -> [Date: DayFacts],
         onPickRange: @escaping (Date, Date) -> Void) {
        self.selected = range.upperBound
        self.earliest = earliest
        self.goal = goal
        self.facts = facts
        self.onPick = { _ in }
        self.range = range
        self.onPickRange = onPickRange
        _shown = StateObject(wrappedValue: MonthBox(month: Calendar.current.startOfDay(for: range.upperBound)))
    }

    /// What the grid paints as chosen: the stored range, or while a first day
    /// is held, the span from it to the day under the pointer.
    private var paintedRange: ClosedRange<Date>? {
        guard range != nil else { return nil }
        if let start = anchor.day {
            let other = shown.hovered ?? start
            return min(start, other)...max(start, other)
        }
        return range.map { calendar.startOfDay(for: $0.lowerBound)...calendar.startOfDay(for: $0.upperBound) }
    }

    private func pick(_ day: Date) {
        guard let onPickRange else { onPick(day); return }
        let key = calendar.startOfDay(for: day)
        if let start = anchor.day {
            anchor.day = nil
            onPickRange(min(start, key), max(start, key))
        } else {
            anchor.day = key
            onPickRange(key, key)
        }
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
                    // Three facts in a 364pt popover: one line cut the goal
                    // count, which is the one worth reading.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
        DateFormats.local("LLLL yyyy").string(from: shown.month)
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
        let painted = paintedRange
        let isSelected = painted.map { key == $0.lowerBound || key == $0.upperBound }
            ?? calendar.isDate(day, inSameDayAs: selected)
        let inRange = painted.map { $0.contains(key) } ?? false
        let isToday = calendar.isDateInToday(day)
        let tooLate = key > calendar.startOfDay(for: Date())
        let tooEarly = earliest.map { key < calendar.startOfDay(for: $0) } ?? false
        let pickable = !tooLate && !tooEarly
        let hovered = hover.id == key.description
        let share = goal > 0 ? (facts.goalAchieved ?? facts.focused) / goal : 0

        return Button { if pickable { pick(day) } } label: {
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
                        : inRange ? AnyShapeStyle(Tokens.Colour.focus.opacity(0.30))
                        : AnyShapeStyle(Tokens.Colour.focus.opacity(
                            pickable ? tint(share) * (range == nil ? 1 : 0.5) : 0)),
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
        .onHover { inside in
            hover.id = inside ? key.description : nil
            if range != nil { shown.hovered = inside && pickable ? key : (shown.hovered == key ? nil : shown.hovered) }
        }
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
        if let credit = goalCredit(facts) {
            parts.append("\(Tokens.duration(credit)) towards the goal")
        }
        return parts.joined(separator: " · ")
    }

    /// Goal credit, but only when it differs from the figure on the cell. The
    /// tint is drawn from focused-active time while the number under the date
    /// is focused time, so a day can be tinted further along than it reads;
    /// saying so here is what makes the tint explainable rather than arbitrary.
    private func goalCredit(_ facts: DayFacts) -> TimeInterval? {
        guard goal > 0, let credit = facts.goalAchieved,
              abs(credit - facts.focused) >= 60 else { return nil }
        return credit
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
            if let credit = goalCredit(facts) {
                parts.append("\(Tokens.spent(credit)) counted towards the goal")
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

    @ViewBuilder private var legend: some View {
        if range != nil {
            Text(anchor.day == nil
                 ? "Click the first day, then the last."
                 : "Now click the last day of the range.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(anchor.day == nil ? AnyShapeStyle(.tertiary)
                                                   : AnyShapeStyle(Tokens.Colour.focus))
        } else {
            goalLegend
        }
    }

    /// A key for a grid that speaks in tint. It draws the same four states the
    /// cells draw — including the dot — rather than standing in for them with
    /// symbols that appear nowhere on the month.
    private var goalLegend: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tokens.Space.m) { legendKeys }
                VStack(alignment: .leading, spacing: Tokens.Space.xs) { legendKeys }
            }
            Text("Tint is the share of your \(Tokens.duration(goal)) goal. "
                 + "Figures are focused time.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Tokens.Typography.metadata)
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Key. A day's tint is its share of your "
                            + "\(Tokens.spent(goal)) goal: untinted below a tenth, "
                            + "light under half, stronger from half, strongest with a "
                            + "tick once the goal is met. A dot marks a day at the Mac "
                            + "with no focus session. Figures are focused time.")
    }

    @ViewBuilder private var legendKeys: some View {
        tintKey(tint(0.25), "Under half")
        tintKey(tint(0.75), "Half or more")
        tintKey(tint(1), "Goal met", ticked: true)
        dotKey
    }

    /// One swatch at a tint the grid really uses, so the key can be held up
    /// against a cell and matched.
    private func tintKey(_ opacity: Double, _ label: String, ticked: Bool = false) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            swatch(fill: Tokens.Colour.focus.opacity(opacity)) {
                if ticked {
                    Image(systemName: "checkmark")
                        .font(Tokens.Typography.micro.weight(.heavy))
                        .foregroundStyle(Tokens.Colour.focus)
                }
            }
            Text(label)
        }
        .accessibilityHidden(true)
    }

    /// The fourth state the old key omitted: time at the Mac, no session.
    private var dotKey: some View {
        HStack(spacing: Tokens.Space.xs) {
            swatch(fill: Color.clear) {
                Text("·")
                    .font(Tokens.Typography.microValue)
                    .foregroundStyle(.tertiary)
            }
            Text("At the Mac, no session")
        }
        .accessibilityHidden(true)
    }

    private func swatch<Mark: View>(fill: Color,
                                    @ViewBuilder mark: () -> Mark) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous)
            .fill(fill)
            .frame(width: 18, height: 18)
            .overlay { mark() }
            // The faintest step is all but invisible on its own ground; a
            // hairline says "this square is the sample" without restating it
            // as a colour the cells do not have.
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
    }

    private func load() {
        shown.facts = facts(shown.month)
    }
}
