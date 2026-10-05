import SwiftUI

/// The days a search matched, newest first, with the month named between
/// months. Each day lists its matching sessions as cards on the spine; a
/// picked app also lists its use outside every session where it fell.
struct HistorySearchList: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let entries: [JournalEntry]
    let lens: HistoryAppLens?
    let appName: String?

    private enum Row: Identifiable {
        case month(Date)
        case day(Date, facts: String, items: [Item])
        var id: String {
            switch self {
            // Not the scroll ids: those go on the headers themselves.
            case .month(let start): return "row-" + JournalEntry.monthID(start)
            case .day(let date, _, _): return "row-" + JournalEntry.dayID(date)
            }
        }
    }

    private enum Item: Identifiable {
        case session(DaySession, use: HistoryAppLens.SessionUse?)
        case outside(HistoryAppLens.OutsideUse)
        case rest(RestEntry)
        var id: String {
            switch self {
            case .session(let session, _): return "item-session-\(session.threadID.uuidString)"
            case .outside(let use): return "outside-\(use.span.start.timeIntervalSinceReferenceDate)"
            case .rest(let rest): return "rest-\(rest.id.uuidString)"
            }
        }
        var start: Date {
            switch self {
            case .session(let session, _): return session.start
            case .outside(let use): return use.span.start
            case .rest(let rest): return rest.start
            }
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .month(let start):
                    Text(HistoryMonthHeader.title(start))
                        .font(Tokens.Typography.metadata.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, Tokens.Space.l)
                        .accessibilityAddTraits(.isHeader)
                case .day(let date, let facts, let items):
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text(HistoryDayHeader.title(date, isToday: Calendar.current.isDate(date, inSameDayAs: store.now())))
                            .font(Tokens.Typography.rowTitle.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: Tokens.Space.s)
                        Text(durations: facts)
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, Tokens.Space.m)
                    .padding(.bottom, Tokens.Space.s)
                    .id(JournalEntry.dayID(date))
                    ForEach(items) { item in self.item(item, on: date) }
                }
            }
        }
    }

    @ViewBuilder private func item(_ item: Item, on day: Date) -> some View {
        switch item {
        case .session(let session, let use):
            HistorySessionRow(session: session,
                              apps: store.storyDayProjection(on: day).sessionDetails[session.id]?.apps ?? [],
                              note: use == nil ? store.journalNoteLine(for: session) : nil,
                              use: use, appName: appName, bundleID: store.historyFilter.appBundleID,
                              isSelected: navigation.historySession == HistorySessionPick(thread: session.threadID, day: day)
                                  || navigation.historyFocus == .session(thread: session.threadID, day: day),
                              onSelect: { navigation.selectHistory(session: session.threadID, on: day) })
        case .outside(let use):
            HistorySpineItem(time: Tokens.timeOfDayOnly(use.span.start), dot: .hollow(Tokens.Palette.app(rank: 1))) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    if let bundleID = store.historyFilter.appBundleID {
                        AppIcon(bundleID: bundleID, size: 16, appName: appName ?? "").alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    }
                    Text(durations: HistorySessionRow.figure(use.seconds))
                        .font(Tokens.Typography.metadata.weight(.semibold))
                    Text("in \(appName ?? "the app") outside a session · \(Tokens.timeRange(use.span.start, use.span.end))")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Tokens.Space.s)
            }
            .accessibilityElement(children: .combine)
        case .rest(let rest):
            HistorySpineItem(time: Tokens.timeOfDayOnly(rest.start), dot: .hollow(Tokens.Palette.warmGrey)) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(rest.name.isEmpty ? "Break" : rest.name).font(Tokens.Typography.metadata)
                    Spacer(minLength: Tokens.Space.s)
                    Text(durations: Tokens.duration(rest.length))
                        .font(Tokens.Typography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Tokens.Space.s)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Tokens.timeRange(rest.start, rest.end)), \(StoryBreakRow.label(rest.name)), "
                                + Tokens.spent(rest.length))
        }
    }

    private var rows: [Row] {
        var result: [Row] = []
        let calendar = Calendar.current
        var month: Date?
        func open(_ date: Date) {
            let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
            if start != month { result.append(.month(start)); month = start }
        }
        if let lens {
            for (day, items, figure) in lensDays(lens) {
                open(day)
                result.append(.day(day, facts: lensFacts(day: day, figure: figure, items: items), items: items))
            }
            return result
        }
        for case .day(let day) in entries {
            open(day.date)
            let items: [Item] = store.journalRows(on: day.date, only: day.threads).map { entry in
                switch entry {
                case .session(let session): return .session(session, use: nil)
                case .rest(let rest): return .rest(rest)
                }
            }
            result.append(.day(day.date, facts: Self.searchFacts(day), items: items))
        }
        return result
    }

    private func lensDays(_ lens: HistoryAppLens) -> [(Date, [Item], TimeInterval)] {
        var byDay: [Date: [Item]] = [:]
        for use in lens.sessions {
            guard let session = store.journalSession(thread: use.threadID, on: use.day) else { continue }
            byDay[use.day, default: []].append(.session(session, use: use))
        }
        for use in lens.outside { byDay[use.day, default: []].append(.outside(use)) }
        let figures = Dictionary(lens.days.map { ($0.day, $0.inSession + $0.outside) }, uniquingKeysWith: +)
        return byDay.keys.sorted(by: >).map { day in
            (day, (byDay[day] ?? []).sorted { $0.start > $1.start }, figures[day] ?? 0)
        }
    }

    /// `3m of Qwen · 1 of 8 sessions used it`.
    private func lensFacts(day: Date, figure: TimeInterval, items: [Item]) -> String {
        let used = items.filter { if case .session = $0 { return true } else { return false } }.count
        let all = HistoryJournalBuilder.rows(store.storyDayProjection(on: day), only: nil)
            .filter { if case .session = $0 { return true } else { return false } }.count
        let head = "\(HistorySessionRow.figure(figure)) of \(appName ?? "the app")"
        if all == 0 { return head + " · outside sessions" }
        if used == 0 { return head + " · none of \(all == 1 ? "1 session" : "\(all) sessions") used it" }
        return head + " · \(used) of \(all == 1 ? "1 session" : "\(all) sessions") used it"
    }

    /// `28m · 1 session`, then `· 2 breaks` when breaks matched.
    static func searchFacts(_ day: JournalDay) -> String {
        var parts: [String] = []
        if day.focused > 0 { parts.append(Tokens.duration(day.focused)) }
        if day.sessions > 0 { parts.append(day.sessions == 1 ? "1 session" : "\(day.sessions) sessions") }
        if day.breaks > 0 { parts.append(day.breaks == 1 ? "1 break" : "\(day.breaks) breaks") }
        return parts.joined(separator: " · ")
    }
}

/// A line on the search's spine: its time in the gutter, its dot on the
/// line, and its content beside them.
struct HistorySpineItem<Content: View>: View {
    enum Dot { case filled(Color), hollow(Color) }

    let time: String
    let dot: Dot
    @ViewBuilder let content: Content

    static var gutter: CGFloat { 64 }
    static var spine: CGFloat { 24 }
    /// Where the dot's centre sits below the item's top.
    static var dotCentre: CGFloat { 21 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(time)
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.gutter, alignment: .trailing)
                .padding(.top, Self.dotCentre - 9)
                .accessibilityHidden(true)
            ZStack(alignment: .top) {
                Rectangle().fill(Tokens.Colour.line).frame(width: 2)
                marker.padding(.top, Self.dotCentre - 6)
            }
            .frame(width: Self.spine)
            .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Tokens.Space.s)
        }
    }

    @ViewBuilder private var marker: some View {
        switch dot {
        case .filled(let colour):
            Circle().fill(colour).frame(width: 12, height: 12)
                .background(Circle().fill(StoryStyle.canvas).frame(width: 18, height: 18))
        case .hollow(let colour):
            Circle().strokeBorder(colour, lineWidth: 2).frame(width: 10, height: 10)
                .background(Circle().fill(StoryStyle.canvas).frame(width: 16, height: 16))
                .padding(.top, 1)
        }
    }
}
