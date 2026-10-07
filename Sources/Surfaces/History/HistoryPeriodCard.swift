import SwiftUI

/// A top row of History drawn as a card on the spine: the period's figure,
/// how many days held focus and the best of them, a bar for every day (or a
/// year's every month) across the whole period, and where its focus went.
/// It is the row's button label, so it opens and folds as a plain row does.
struct HistoryPeriodCard: View {
    @ObservedObject var store: SessionStore
    let row: HistoryRow
    let isOpen: Bool
    let isFocused: Bool
    @Environment(\.focusInterfaceDensity) private var density

    static var barHeight: CGFloat { 40.zoomed }

    var body: some View {
        let calendar = SessionStore.historyCalendar
        let top = store.historyTop()
        let colour = row.mainWorkType.map(Tokens.Palette.workType) ?? Tokens.Colour.focus
        let shares = row.focused > 0 ? store.historyCategories(for: row.place) : []
        return HStack(alignment: .top, spacing: Tokens.Space.s) {
            // Centred where the plain rows' dot is, so the spine of the rows
            // it opens runs from it.
            Circle()
                .fill(row.focused > 0 ? colour : StoryStyle.line)
                .frame(width: 12.zoomed, height: 12.zoomed)
                .background(Circle().fill(StoryStyle.canvas).frame(width: 18.zoomed, height: 18.zoomed))
                .frame(width: HistoryTreeRow.dotSize)
                .padding(.top, 22.zoomed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(HistoryRowText.title(row.place, today: top.today, calendar: calendar))
                        .font(Tokens.Typography.rowTitle)
                        .lineLimit(1)
                    if row.place.span.contains(top.today) {
                        Text("So far")
                            .font(Tokens.Typography.caption)
                            .padding(.horizontal, 7.zoomed)
                            .padding(.vertical, 2.zoomed)
                            .background(StoryStyle.focus.opacity(0.14), in: RoundedRectangle(cornerRadius: Tokens.Radius.swatch))
                            .foregroundStyle(StoryStyle.focus)
                    }
                    Spacer(minLength: Tokens.Space.s)
                    Text(durations: Self.figure(row))
                        .font(Tokens.Typography.rowTitle.monospacedDigit())
                    Image(systemName: "chevron.right")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                Text(durations: Self.detail(row, summary: store.historySummary(for: row.place), today: top.today,
                                            calendar: calendar))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                bars(Self.slots(row, top: top, calendar: calendar), colour: colour)
                    .padding(.top, Tokens.Space.s)
                if !shares.isEmpty {
                    CategoryShareBar(shares: shares)
                        .padding(.top, Tokens.Space.xs)
                }
            }
            .padding(StoryStyle.entryInsets(for: density))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isFocused ? AnyShapeStyle(Tokens.Colour.focus.opacity(0.12)) : AnyShapeStyle(StoryStyle.card),
                        in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous)
                .strokeBorder(isOpen ? Tokens.Colour.focus.opacity(0.55) : Tokens.Colour.line,
                              lineWidth: isOpen ? 1.5.zoomed : 1))
            .shadow(color: .black.opacity(0.025), radius: 2.zoomed, y: 1)
        }
        .padding(.horizontal, HistoryRowLayout.inset)
        .padding(.bottom, Tokens.Space.s)
        .contentShape(Rectangle())
    }

    private func bars(_ slots: [TimeInterval?], colour: Color) -> some View {
        let peak = max(slots.compactMap { $0 }.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: slots.count > 40 ? 2.zoomed : 3.zoomed) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, seconds in
                RoundedRectangle(cornerRadius: 2.zoomed, style: .continuous)
                    .fill(Self.barFill(seconds, colour: colour))
                    .frame(maxWidth: .infinity)
                    .frame(height: (seconds ?? 0) > 0 ? max(3.zoomed, Self.barHeight * (seconds ?? 0) / peak) : 2.zoomed)
            }
        }
        .frame(height: Self.barHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private static func barFill(_ seconds: TimeInterval?, colour: Color) -> AnyShapeStyle {
        guard let seconds else { return AnyShapeStyle(StoryStyle.line.opacity(0.5)) }
        return seconds > 0 ? AnyShapeStyle(colour) : AnyShapeStyle(StoryStyle.line)
    }

    /// The card's big figure: its focus, or what was recorded without any.
    static func figure(_ row: HistoryRow) -> String {
        if row.isAppUseOnly { return Tokens.duration(row.tracked) }
        return row.isEmpty ? "—" : Tokens.duration(row.focused)
    }

    /// `18 days · best Mon 7 Sep, 9h 47m`; `Recorded app use only`.
    static func detail(_ row: HistoryRow, summary: HistorySummary, today: Date, calendar: Calendar) -> String {
        if row.isAppUseOnly { return "Recorded app use only" }
        if row.isEmpty || row.focused <= 0 { return "nothing recorded" }
        var parts = [row.focusedDays == 1 ? "1 day" : "\(row.focusedDays) days"]
        if let best = summary.best, row.focusedDays > 1 {
            parts.append("best \(HistoryRowText.title(best.place, today: today, calendar: calendar)), "
                         + Tokens.duration(best.focused))
        }
        return parts.joined(separator: " · ")
    }

    /// One slot per day of the whole calendar month or week, or per month of
    /// the whole year: nil before the record began or after today, so a
    /// month in progress shows how much of it is still to come.
    static func slots(_ row: HistoryRow, top: HistoryTop, calendar: Calendar) -> [TimeInterval?] {
        let byStart = Dictionary(row.bars.map { (calendar.startOfDay(for: $0.start), $0.focused) },
                                 uniquingKeysWith: +)
        let whole = HistoryTreeBuilder.period(row.place.level, containing: row.place.start, calendar: calendar)
        let first = calendar.startOfDay(for: top.firstDay)
        let today = calendar.startOfDay(for: top.today)
        var result: [TimeInterval?] = []
        var cursor = whole.start
        while cursor < whole.end, result.count < 400 {
            let unit: Calendar.Component = row.place.level == .year ? .month : .day
            let slot = calendar.dateInterval(of: unit, for: cursor) ?? DateInterval(start: cursor, duration: 86_400)
            if slot.end <= first || slot.start > today {
                result.append(nil)
            } else {
                let key = calendar.startOfDay(for: max(slot.start, first))
                result.append(byStart[key] ?? 0)
            }
            cursor = slot.end
        }
        return result
    }
}
