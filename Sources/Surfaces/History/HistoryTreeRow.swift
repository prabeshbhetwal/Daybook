import SwiftUI

/// One row on the spine, and under it, when open, its children one step in.
struct HistoryTreeRow: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let row: HistoryRow
    let depth: Int
    /// Not observed: a row only writes what it points at, for the grid to read.
    let link: HistoryGridLink
    /// What stands out about a first-view period row; nested rows have none.
    var facts: HistoryRowFacts = .none
    /// The span this row put on the link, so it releases that one even if the
    /// row's own span has grown since (the period holding today, at a refresh).
    @State private var pointedSpan: DateInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var indent: CGFloat { Tokens.Space.l }
    static var dotSize: CGFloat { 8.zoomed }

    private var isOpen: Bool { navigation.historyOpen.indices.contains(depth) && navigation.historyOpen[depth] == row.place }
    private var isFocused: Bool { navigation.historyFocus == .row(row.place) }
    private var today: Date { store.now() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if isPeriod {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(HistoryRowText.gutter(row.place, calendar: SessionStore.historyCalendar))
                            .font(Tokens.Typography.body.monospacedDigit())
                            .foregroundStyle(StoryStyle.supportingInk)
                            .lineLimit(1)
                            .frame(width: gutter, alignment: .trailing)
                            // The row's own label names the period.
                            .accessibilityHidden(true)
                        header
                    }
                } else {
                    header
                }
            }
            // The grid keeps this row's days at full strength while it is pointed at.
            // Each clears only its own span, so the next row's arrival is not undone.
            .onHover { inside in
                if inside {
                    pointedSpan = row.place.span
                    link.span = row.place.span
                } else { releaseLink() }
            }
            .onDisappear(perform: releaseLink)
            if isOpen {
                children
                    .padding(.leading, Self.indent)
                    .overlay(alignment: .leading) { spine }
                    // Under the row's dot, which the gutter moved along.
                    .padding(.leading, gutter)
                    .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            }
        }
        .id(row.id)
    }

    /// The periods the record is first divided into: a timeline of weeks,
    /// months or years. A day stays a row, since it opens the day's own story.
    private var isPeriod: Bool { depth == 0 && row.place.level != .day }
    private var gutter: CGFloat { isPeriod ? HistoryPeriodRow.gutterWidth(for: row.place.level) : 0 }

    /// Whether the whole button tints under the pointer. A period row tints
    /// its own card instead (`HistoryPeriodRow`): its button also holds the
    /// dot and the padding around the card, and a tint there overhangs it.
    static func buttonTints(isEmpty: Bool, isPeriod: Bool) -> Bool { !isEmpty && !isPeriod }

    private func releaseLink() {
        if let pointed = pointedSpan, link.span == pointed { link.span = nil }
        pointedSpan = nil
    }

    private var header: some View {
        Button { navigation.toggleHistory(row.place) } label: {
            if isPeriod {
                HistoryPeriodRow(store: store, row: row, facts: facts,
                                 isCurrent: row.place.span.holds(store.historyTop().today),
                                 isOpen: isOpen, isFocused: isFocused)
            } else {
                plainHeader
            }
        }
        .buttonStyle(StoryPressStyle(hovers: Self.buttonTints(isEmpty: row.isEmpty, isPeriod: isPeriod),
                                     cornerRadius: isPeriod ? StoryStyle.entryRadius : Tokens.Radius.nested))
        .disabled(row.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryRowText.spoken(row, today: today, isOpen: isOpen, depth: depth,
                                                  calendar: SessionStore.historyCalendar, facts: facts))
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(row.isEmpty ? "" : HistoryTree.keyboardHint)
        // The header's own click, for a reader who looks for it in a menu.
        .contextMenu {
            RowContextMenu(items: HistoryRowMenu.items(isEmpty: row.isEmpty, isOpen: isOpen)) { _ in
                navigation.toggleHistory(row.place)
            }
        }
    }

    private var plainHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Self.dot(row)
            Text(HistoryRowText.title(row.place, today: today, calendar: SessionStore.historyCalendar))
                .font(row.place.level == .day ? Tokens.Typography.label
                                              : Tokens.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: Tokens.Space.s)
            if showsFacts {
                Text(durations: HistoryRowText.facts(row, today: today))
                    .font(Tokens.Typography.body.monospacedDigit())
                    .foregroundStyle(StoryStyle.supportingInk)
                    .lineLimit(1)
            }
            bars
            // The same chevron the period and session cards end on, so a row
            // that opens says so. An empty row has nothing to open.
            if !row.isEmpty {
                Image(systemName: "chevron.right")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .padding(.vertical, Tokens.Space.xs)
        .padding(.horizontal, HistoryRowLayout.inset)
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .background(isFocused ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .keyboardFocusRing(isFocused, cornerRadius: Tokens.Radius.nested)
        .contentShape(Rectangle())
    }

    /// A day of one finished session shows its figure on the session row.
    private var showsFacts: Bool {
        guard row.place.level == .day, isOpen, row.focused > 0 else { return true }
        let rows = HistoryJournalBuilder.rows(store.storyDayProjection(on: row.place.start), only: nil)
        return HistoryDayHeader.showsTotal(day: JournalDay(date: row.place.start, focused: row.focused,
                                                           tracked: row.tracked, sessions: row.sessions), rows: rows)
    }

    /// A row's mark on the spine, shared with the first view's period rows.
    static func dot(_ row: HistoryRow) -> some View {
        let colour = dotColour(row)
        return Circle()
            .strokeBorder(colour, lineWidth: row.focused > 0 ? 0 : 1.5.zoomed)
            .background(Circle().fill(row.focused > 0 ? colour : Color.clear))
            .frame(width: dotSize, height: dotSize)
            .accessibilityHidden(true)
    }

    private static func dotColour(_ row: HistoryRow) -> Color {
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

    /// The period's review note, above what is under it. A year has none, nor
    /// has a period with no session; that is read off the row, since this
    /// redraws every second and the facts a note is written from are not
    /// cheap. A period still running is written on request, as its figures
    /// are still moving.
    @ViewBuilder private var note: some View {
        if row.place.level != .year, row.sessions > 0, let writer = navigation.notes {
            PeriodNote(writer: writer, place: row.place, evidence: store.noteEvidence,
                       trigger: store.noteIsCurrent(row.place) ? .onRequest(label: "Write a Note") : .automatic,
                       insets: EdgeInsets(top: Tokens.Space.m, leading: Tokens.Space.s, bottom: Tokens.Space.s,
                                          trailing: HistoryRowLayout.inset))
        }
    }

    @ViewBuilder private var children: some View {
        if row.place.level == .day {
            VStack(alignment: .leading, spacing: 0) {
                note
                // The dashboard's own day, for this date: the same headline, the
                // same timeline, the same cards.
                ProjectedDayStoryColumn(store: store, projection: store.storyDayProjection(on: row.place.start),
                                        context: .main, isHistory: true)
                    .padding(.vertical, Tokens.Space.m)
                    .padding(.leading, Tokens.Space.s)
                    // Every row and card keeps this inset from the column's edge;
                    // without it the day's cards ran past the week card above.
                    .padding(.trailing, HistoryRowLayout.inset)
            }
        } else {
            let rows = store.historyRows(under: row.place)
            // AnyView breaks the recursion in the opaque type; the tree is at
            // most four rows deep, so it costs nothing worth measuring.
            AnyView(Group {
                note
                ForEach(rows) { child in
                    HistoryTreeRow(store: store, navigation: navigation, row: child, depth: depth + 1, link: link)
                }
            })
        }
    }
}
