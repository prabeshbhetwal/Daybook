import SwiftUI

/// The words on and about a row. Kept apart from the view so the checks can
/// read them without rendering.
enum HistoryRowText {
    static func title(_ place: HistoryPlace, today: Date, calendar: Calendar) -> String {
        switch place.level {
        case .year:
            return DateFormats.australian("yyyy", in: calendar.timeZone).string(from: place.start)
        case .month:
            return DateFormats.australian("MMMM", in: calendar.timeZone).string(from: place.start)
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: place.span.end) ?? place.start
            if calendar.isDate(place.start, inSameDayAs: last) {
                return DateFormats.australian("EEE d MMM", in: calendar.timeZone).string(from: place.start)
            }
            let sameMonth = calendar.isDate(place.start, equalTo: last, toGranularity: .month)
            let first = DateFormats.australian(sameMonth ? "d" : "d MMM", in: calendar.timeZone).string(from: place.start)
            return "\(first) – \(DateFormats.australian("d MMM", in: calendar.timeZone).string(from: last))"
        case .day:
            return calendar.isDate(place.start, inSameDayAs: today) ? "Today"
                : DateFormats.australian("EEE d MMM", in: calendar.timeZone).string(from: place.start)
        }
    }

    /// `20h 40m · 14 days`, `2h 10m · 3 sessions`, or why there is no figure.
    static func facts(_ row: HistoryRow, today: Date) -> String {
        if row.isAppUseOnly { return "Recorded app use only · \(Tokens.duration(row.tracked))" }
        if row.isEmpty {
            return row.place.level == .day && Calendar.current.isDate(row.place.start, inSameDayAs: today)
                ? "nothing recorded yet today" : "nothing recorded"
        }
        if row.place.level == .day {
            let noun = row.sessions == 1 ? "1 session" : "\(row.sessions) sessions"
            return row.focused > 0 ? "\(Tokens.duration(row.focused)) · \(noun)" : noun
        }
        let days = row.focusedDays == 1 ? "1 day" : "\(row.focusedDays) days"
        return row.focused > 0 ? "\(Tokens.duration(row.focused)) · \(days)" : "no focus recorded"
    }

    /// `September 2026, 1 hour 45 minutes across 3 days, month, level 2, collapsed`.
    static func spoken(_ row: HistoryRow, today: Date, isOpen: Bool, depth: Int, calendar: Calendar) -> String {
        var name = title(row.place, today: today, calendar: calendar)
        if row.place.level == .month { name += " " + DateFormats.australian("yyyy", in: calendar.timeZone).string(from: row.place.start) }
        let figure: String
        if row.isAppUseOnly {
            figure = "recorded app use only, \(Tokens.spent(row.tracked))"
        } else if row.isEmpty {
            figure = facts(row, today: today)
        } else if row.place.level == .day {
            let noun = row.sessions == 1 ? "1 session" : "\(row.sessions) sessions"
            figure = row.focused > 0 ? "\(Tokens.spent(row.focused)), \(noun)" : noun
        } else {
            let days = row.focusedDays == 1 ? "1 day" : "\(row.focusedDays) days"
            figure = row.focused > 0 ? "\(Tokens.spent(row.focused)) across \(days)" : "no focus recorded"
        }
        var parts = [name, figure, row.place.level.spokenName, "level \(depth + 1)"]
        if !row.isEmpty { parts.append(isOpen ? "expanded" : "collapsed") }
        return parts.joined(separator: ", ")
    }

    static func headline(top: HistoryTop, summary: HistorySummary, calendar: Calendar)
        -> (eyebrow: String, sentence: String, facts: [String]) {
        let eyebrow: String
        switch top.place?.level {
        case .year: eyebrow = DateFormats.australian("yyyy", in: calendar.timeZone).string(from: top.span.start)
        case .month: eyebrow = DateFormats.australian("MMMM yyyy", in: calendar.timeZone).string(from: top.span.start)
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: top.span.end) ?? top.span.start
            // A week of one recorded day is that day; a week across two months names both.
            let sameMonth = calendar.isDate(top.span.start, equalTo: last, toGranularity: .month)
            eyebrow = calendar.isDate(top.span.start, inSameDayAs: last)
                ? DateFormats.australian("EEEE d MMMM", in: calendar.timeZone).string(from: top.span.start)
                : "\(DateFormats.australian(sameMonth ? "d" : "d MMMM", in: calendar.timeZone).string(from: top.span.start)) – "
                    + DateFormats.australian("d MMMM", in: calendar.timeZone).string(from: last)
        case .day, .none:
            eyebrow = "On record since \(DateFormats.australian("d MMMM yyyy", in: calendar.timeZone).string(from: top.firstDay))"
        }
        let days = summary.focusedDays == 1 ? "1 day" : "\(summary.focusedDays) days"
        let sentence = summary.focused > 0
            ? "You focused \(Tokens.duration(summary.focused)) across \(days)."
            : "Nothing focused here yet."
        var facts: [String] = []
        if summary.focusedDays > 1 {
            facts.append("\(Tokens.duration(summary.focused / Double(summary.focusedDays))) per focused day")
        }
        // The best month or day is the rail's to say; the headline says how
        // steady the record has been. The top period holds the whole record.
        let elapsed = (calendar.dateComponents([.day], from: calendar.startOfDay(for: top.firstDay),
                                               to: calendar.startOfDay(for: top.today)).day ?? 0) + 1
        if summary.focusedDays > 0, elapsed > 1 {
            facts.append(summary.focusedDays >= elapsed ? "focus on every day since you started"
                         : "focus on \(summary.focusedDays) of the \(elapsed) days since you started")
        }
        return (eyebrow, sentence, facts)
    }
}

/// One row on the spine, and under it, when open, its children one step in.
struct HistoryTreeRow: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let row: HistoryRow
    let depth: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var indent: CGFloat { Tokens.Space.l }
    static var dotSize: CGFloat { 8.zoomed }

    private var isOpen: Bool { navigation.historyOpen.indices.contains(depth) && navigation.historyOpen[depth] == row.place }
    private var isFocused: Bool { navigation.historyFocus == .row(row.place) }
    private var today: Date { store.now() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                children
                    .padding(.leading, Self.indent)
                    .overlay(alignment: .leading) { spine }
                    .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            }
        }
        .id(row.id)
    }

    /// The top rows are cards: the periods the record is first divided into.
    /// A day stays a row, since it opens the day's own story.
    private var isCard: Bool { depth == 0 && row.place.level != .day }

    private var header: some View {
        Button { navigation.toggleHistory(row.place) } label: {
            if isCard {
                HistoryPeriodCard(store: store, row: row, isOpen: isOpen, isFocused: isFocused)
            } else {
                plainHeader
            }
        }
        .buttonStyle(StoryPressStyle(hovers: !row.isEmpty,
                                     cornerRadius: isCard ? StoryStyle.entryRadius : Tokens.Radius.nested))
        .disabled(row.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryRowText.spoken(row, today: today, isOpen: isOpen, depth: depth,
                                                  calendar: SessionStore.historyCalendar))
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(row.isEmpty ? "" : HistoryTree.keyboardHint)
    }

    private var plainHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            dot
            Text(HistoryRowText.title(row.place, today: today, calendar: SessionStore.historyCalendar))
                .font(row.place.level == .day ? Tokens.Typography.label
                                              : Tokens.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: Tokens.Space.s)
            if showsFacts {
                Text(durations: HistoryRowText.facts(row, today: today))
                    .font(Tokens.Typography.body.monospacedDigit())
                    .foregroundStyle(row.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            bars
        }
        .padding(.vertical, Tokens.Space.xs)
        .padding(.horizontal, HistoryRowLayout.inset)
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .background(isFocused ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .contentShape(Rectangle())
    }

    /// A day of one finished session shows its figure on the session row.
    private var showsFacts: Bool {
        guard row.place.level == .day, isOpen, row.focused > 0 else { return true }
        let rows = HistoryJournalBuilder.rows(store.storyDayProjection(on: row.place.start), only: nil)
        return HistoryDayHeader.showsTotal(day: JournalDay(date: row.place.start, focused: row.focused,
                                                           tracked: row.tracked, sessions: row.sessions), rows: rows)
    }

    private var dot: some View {
        Circle()
            .strokeBorder(dotColour, lineWidth: row.focused > 0 ? 0 : 1.5.zoomed)
            .background(Circle().fill(row.focused > 0 ? dotColour : Color.clear))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .accessibilityHidden(true)
    }

    private var dotColour: Color {
        if let type = row.mainWorkType { return Tokens.Palette.workType(type) }
        return row.isEmpty ? StoryStyle.line : Tokens.Palette.warmGrey.opacity(0.7)
    }

    @ViewBuilder private var bars: some View {
        if row.place.level == .day {
            HistoryDayStrip(date: row.place.start, entries: store.storyDayProjection(on: row.place.start).sessions, height: 6.zoomed)
                .frame(width: 120.zoomed)
        } else if !row.bars.isEmpty {
            HistoryMonthBars(daily: row.bars.map(\.focused))
                .frame(width: 120.zoomed)
        }
    }

    /// The line the children hang from, under this row's dot.
    private var spine: some View {
        Rectangle()
            .fill(StoryStyle.line)
            .frame(width: 1)
            .padding(.leading, HistoryRowLayout.inset + Self.dotSize / 2)
            .padding(.vertical, Tokens.Space.xs)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var children: some View {
        if row.place.level == .day {
            // The dashboard's own day, for this date: the same headline, the
            // same timeline, the same cards.
            ProjectedDayStoryColumn(store: store, projection: store.storyDayProjection(on: row.place.start),
                                    context: .main, isHistory: true)
                .padding(.vertical, Tokens.Space.m)
                .padding(.leading, Tokens.Space.s)
        } else {
            let rows = store.historyRows(under: row.place)
            // AnyView breaks the recursion in the opaque type; the tree is at
            // most four rows deep, so it costs nothing worth measuring.
            AnyView(ForEach(rows) { child in
                HistoryTreeRow(store: store, navigation: navigation, row: child, depth: depth + 1)
            })
        }
    }
}
