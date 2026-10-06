import SwiftUI

/// Clock hours as History says them: "9 am", "9 am – 11 am".
enum HistoryHours {
    static func label(_ hour: Int) -> String {
        let wrapped = ((hour % 24) + 24) % 24
        let twelve = wrapped % 12 == 0 ? 12 : wrapped % 12
        return "\(twelve) \(wrapped < 12 ? "am" : "pm")"
    }

    static func span(from startHour: Int) -> String {
        "\(label(startHour)) – \(label(startHour + 2))"
    }

    /// The best two hours' figure, and where it mostly fell, said once.
    static func note(seconds: TimeInterval, phrase: String?) -> String {
        var note = "\(Tokens.duration(seconds)) of focus fell here"
        if let phrase { note += ", most of it \(phrase)" }
        return note + "."
    }
}

/// What the rail describes once the selection meets the archive: a session
/// that is gone, or a day or session hidden by a search, reads as the month
/// it was in.
/// What the rail describes: the deepest open row, or the picked session.
enum HistoryRailScope: Equatable {
    /// A year, month or week; nil is the top period itself.
    case period(HistoryPlace?)
    case day(Date)
    case session(DaySession, day: Date)

    var isSession: Bool { if case .session = self { return true } else { return false } }

    /// `session` is the picked session if its day still has it; a pick
    /// whose session is gone, or hidden by a search, reads as its day.
    static func resolve(open: [HistoryPlace], session: DaySession?, pick: HistorySessionPick?) -> HistoryRailScope {
        if let pick, let session, open.last?.level == .day, open.last?.start == pick.day {
            return .session(session, day: pick.day)
        }
        guard let deepest = open.last else { return .period(nil) }
        return deepest.level == .day ? .day(deepest.start) : .period(deepest)
    }
}

/// History's rail: the month, day or session picked in the journal, and
/// nothing from any other time frame.
struct HistoryJournalRail: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @ObservedObject var settings: SettingsModel
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        let scope = self.scope
        if store.historyFilter.isActive, !scope.isSession {
            // The tree's open day or period is hidden behind the results;
            // the rail describes what is on screen.
            padded(HistorySearchRail(store: store, entries: store.historyJournal(), lens: store.historyAppLens())
                .storyRenderEvidence(.historySearchRail))
        } else {
            scoped(scope)
        }
    }

    @ViewBuilder private func scoped(_ scope: HistoryRailScope) -> some View {
        switch scope {
        case .day(let day):
            // The dashboard's own rail, for this day. It sets its own insets.
            StoryRail(store: store, navigation: navigation, settings: settings, day: day)
                .storyRenderEvidence(.historyDayRail)
        case .period(let place):
            padded(HistoryPeriodRail(store: store, place: place)
                .storyRenderEvidence(.historyPeriodRail))
        case .session(let session, let day):
            padded(HistorySessionRail(store: store, session: session, day: day,
                                      apps: store.storyDayProjection(on: day).sessionDetails[session.id]?.apps ?? [],
                                      lens: store.historyAppLens())
                .storyRenderEvidence(.historySessionRail))
        }
    }

    private func padded(_ content: some View) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) { content }
            .padding(StoryStyle.railInsets(for: density))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scope: HistoryRailScope {
        var session: DaySession?
        if let pick = navigation.historySession {
            session = store.journalSession(thread: pick.thread, on: pick.day)
            // A search that hides the session hides it from the rail too.
            // The app's own story also lists the session still running, which
            // the search's journal does not hold yet.
            if store.historyFilter.isActive, let found = session,
               !store.historyJournal().contains(where: { entry in
                   if case .day(let row) = entry, row.date == pick.day { return row.threads?.contains(found.threadID) ?? true }
                   return false
               }),
               store.historyAppLens()?.sessions.contains(where: { $0.threadID == found.threadID && $0.day == pick.day })
                   != true { session = nil }
        }
        return HistoryRailScope.resolve(open: navigation.historyOpen, session: session, pick: navigation.historySession)
    }
}

/// The rail's title: which month, day or session it describes.
struct HistoryRailHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Tokens.Typography.heading)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(durations: detail)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A year, month, week or the whole record: where its focus went, when,
/// which goals it met, which apps; for this month, how it is going; for a
/// year or the record, its best month; for a month or week, its best day.
struct HistoryPeriodRail: View {
    @ObservedObject var store: SessionStore
    /// nil: the top period.
    let place: HistoryPlace?

    /// Which reading covers a place: a week is its own days (a week at the
    /// record's edge, or under one of the two months it straddles, is
    /// shorter than a calendar week), a month one month, a year its months
    /// on record, the record all its months.
    static func reading(for place: HistoryPlace?, top: HistoryTop,
                        calendar: Calendar) -> (scope: InsightRange, anchor: Date, limit: Int) {
        let span = place?.span ?? top.span
        let last = calendar.date(byAdding: .day, value: -1, to: span.end) ?? span.start
        let anchor = min(last, top.today)
        switch place?.level ?? top.place?.level {
        case .week:
            let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: span.start), to: anchor).day ?? 0) + 1
            return (.day, anchor, max(1, days))
        case .month: return (.month, anchor, 1)
        case .year, .day, .none:
            let first = calendar.dateInterval(of: .month, for: span.start)?.start ?? span.start
            let months = (calendar.dateComponents([.month], from: first, to: anchor).month ?? 0) + 1
            return (.month, anchor, max(1, months))
        }
    }

    /// This month's rail also says how the month is going, from the Insights
    /// surfaces. Those are built only while a rail shows them: every app
    /// switch used to rebuild both, for a week's rail that shows neither.
    static func showsThisMonth(place: HistoryPlace?, top: HistoryTop) -> Bool {
        let span = place?.span ?? top.span
        return (place?.level ?? top.place?.level) == .month && span.contains(top.today)
    }

    var body: some View {
        let calendar = SessionStore.historyCalendar
        let top = store.historyTop()
        let read = Self.reading(for: place, top: top, calendar: calendar)
        let facts = store.insightReading(scope: read.scope, anchoredAt: read.anchor, limit: read.limit,
                                         calendar: calendar).facts
        let tracked = store.historySummary(for: place).tracked
        let isCurrentMonth = Self.showsThisMonth(place: place, top: top)
        let surface = store.insightSurface(for: .month)
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: place.map { HistoryRowText.title($0, today: top.today, calendar: calendar) }
                                    ?? HistoryRowText.headline(top: top, summary: store.historySummary(), calendar: calendar).eyebrow)
            if !facts.categories.isEmpty {
                StoryTile(title: "Focus by category", trailing: nil) {
                    CategoryShareBar(shares: facts.categories)
                    if isCurrentMonth, let placed = surface.categories {
                        Text("Where each lands in the day: \(placed.headline).")
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let window = facts.bestWindow {
                StoryTile(title: "Best two hours", trailing: nil) {
                    Text(HistoryHours.span(from: window.startHour))
                        .font(Tokens.Typography.heading)
                    Text(durations: HistoryHours.note(seconds: window.seconds, phrase: facts.bestWindowPhrase))
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            bestTile(store.historySummary(for: place))
            if !facts.goalRates.isEmpty { goalsTile(facts.goalRates) }
            if !facts.apps.isEmpty { appsTile(facts.apps, tracked: tracked) }
            if isCurrentMonth { soFar(surface) }
        }
        .onAppear { store.setInsightsVisible(isCurrentMonth) }
        .onChange(of: isCurrentMonth) { store.setInsightsVisible($0) }
        .onDisappear { store.setInsightsVisible(false) }
    }

    /// The best month of a year or the record; the best day of a month or week.
    @ViewBuilder private func bestTile(_ summary: HistorySummary) -> some View {
        if let best = summary.best, summary.focusedDays > 1 {
            let isMonth = best.place.level == .month
            StoryTile(title: isMonth ? "Best month" : "Best day", trailing: nil) {
                Text(isMonth ? DateFormats.australian("MMMM yyyy").string(from: best.place.start)
                             : Tokens.longDate(best.place.start))
                    .font(Tokens.Typography.heading)
                Text(durations: "\(Tokens.duration(best.focused)) focused")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// `16h 25m recorded app use`: the period's app use, said once, here.
    static func appUseLine(tracked: TimeInterval) -> String {
        "\(Tokens.duration(tracked)) recorded app use"
    }

    private func goalsTile(_ rates: [InsightGoalRate]) -> some View {
        StoryTile(title: "Category goals", trailing: "days met") {
            ForEach(rates) { rate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: rate.workType.symbolName)
                            .font(Tokens.Typography.caption)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Tokens.Palette.workType(rate.workType))
                            .frame(width: 14)
                            .accessibilityHidden(true)
                        Text(rate.workType.displayName)
                            .font(Tokens.Typography.body)
                        Spacer(minLength: Tokens.Space.s)
                        Text("\(rate.metDays) of \(rate.focusedDays)")
                            .font(Tokens.Typography.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(StoryStyle.line)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Tokens.Palette.workType(rate.workType))
                                    .frame(width: geometry.size.width * rate.share)
                            }
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(rate.workType.displayName): \(Tokens.spent(rate.goal)) goal met on "
                                    + "\(rate.metDays) of \(rate.focusedDays) focused days")
            }
        }
    }

    private func appsTile(_ apps: [AppRank], tracked: TimeInterval) -> some View {
        let limit = store.engine.store.menuAppCount
        return StoryTile(title: apps.count > limit ? "Top \(limit) apps" : "Apps",
                         trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
            if tracked > 0 {
                Text(durations: Self.appUseLine(tracked: tracked))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: index)
            }
        }
    }

    @ViewBuilder private func soFar(_ surface: InsightSurface) -> some View {
        Text("This month so far")
            .font(Tokens.Typography.label)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Tokens.Space.s)
        if surface.hasEvidence {
            if let pace = surface.pace { InsightSection(title: "Pace", insight: pace) }
            if let quality = surface.quality { InsightSection(title: "Focus quality", insight: quality) }
            if let continuity = surface.continuity { InsightSection(title: "Continuity", insight: continuity) }
        } else {
            Text(InsightSurface.insufficientEvidenceCopy)
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A session: its length and time, each stretch when there were several,
/// its apps, its note in full, and the way into its day.
struct HistorySessionRail: View {
    @ObservedObject var store: SessionStore
    let session: DaySession
    let day: Date
    let apps: [AppRank]
    /// The picked app's story, when an app is the filter: the rail then
    /// says what the app was to this session first.
    var lens: HistoryAppLens?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: session.workType.sessionTitle(named: session.name),
                               detail: Tokens.longDate(day))
            if let lens, let use = lens.sessions.first(where: { $0.threadID == session.threadID && $0.day == day }) {
                HistoryAppSessionTile(use: use, lens: lens, appName: store.historyAppName(for: lens.bundleID))
            }
            // An unnamed session's heading is already its category.
            StoryTile(title: session.name.isEmpty ? "Session" : session.workType.displayName,
                      trailing: nil) {
                Text(durations: session.isRunning ? "In progress" : Tokens.preciseDuration(session.worked))
                    .font(Tokens.Typography.figure)
                Text(Tokens.timeRange(session.start, session.end))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                if session.spans.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.spans.count) stretches")
                            .font(Tokens.Typography.label)
                        ForEach(Array(session.spans.enumerated()), id: \.offset) { _, span in
                            Text(Tokens.timeRange(span.start, span.end))
                                .font(Tokens.Typography.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !apps.isEmpty {
                let limit = store.engine.store.menuAppCount
                StoryTile(title: apps.count > limit ? "Top \(limit) apps" : "Apps",
                          trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
                    ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
            if !notes.isEmpty {
                StoryTile(title: notes.count == 1 ? "Note" : "Notes", trailing: nil) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var notes: [String] {
        session.recordIDs.compactMap { id in
            let text = (store.metadataArchive.metadata(for: id)?.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
