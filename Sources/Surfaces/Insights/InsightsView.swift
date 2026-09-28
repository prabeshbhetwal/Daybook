import SwiftUI

/// The story of many periods at once, laid out the way a week's story is: a
/// sentence and its charts in the column, the figures behind them in the rail.
/// The chrome owns the span (days, weeks or months) and where the range ends.
struct InsightsView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.focusInterfaceDensity) private var density
    @StateObject private var selection = HoverBox()
    /// The picked period whose story is unfolded in place.
    @StateObject private var unfolded = HoverBox()
    var scrolls = true

    private var surface: InsightSurface {
        store.insightSurface(for: navigation.insightRange)
    }

    /// Newest first, as the store lists them: as many as the column can show.
    /// Cached in the store until its evidence changes: `body` runs once a
    /// second while a session ticks, and must not rebuild a page of History
    /// each time it does.
    private var reading: InsightReading {
        store.insightReading(scope: navigation.insightRange,
                             anchoredAt: navigation.insightAnchor,
                             limit: navigation.insightShownCount)
    }

    /// How many periods a column this wide can draw legibly. The chrome pages
    /// by this count, so the chart never grows past its measure.
    static func visibleCount(for width: CGFloat, scope: InsightRange) -> Int {
        let measure = max(0, width - StoryStyle.columnInsets.leading - StoryStyle.columnInsets.trailing)
        switch scope {
        case .day: return min(42, max(7, Int(measure / 50)))
        case .week: return min(14, max(4, Int(measure / 80)))
        // A year. The month grids wrap, so this is no longer what fits across
        // the column — it is how far back the span reaches, and a page of it
        // is a year.
        case .month: return 12
        }
    }

    var body: some View {
        let current = reading
        let listed = current.periods
        let facts = current.facts
        return HStack(alignment: .top, spacing: 0) {
            pane { column(listed, facts) }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(StoryStyle.canvas)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: InsightWidthKey.self, value: geometry.size.width)
                })
                .onPreferenceChange(InsightWidthKey.self) { width in
                    for scope in InsightRange.allCases {
                        navigation.setInsightVisibleCount(Self.visibleCount(for: width, scope: scope), for: scope)
                    }
                }
            Divider()
            pane { rail(listed, facts) }
                .frame(width: StoryLayout.railWidth)
                .background(StoryStyle.rail)
        }
        .background(Tokens.Colour.ground)
        .onAppear { store.setInsightsVisible(true) }
        .onDisappear { store.setInsightsVisible(false) }
        .onChange(of: navigation.insightRange) { _ in
            selection.id = nil
            unfolded.id = nil
            navigation.clearReviewDay()
            navigation.historySelectedPeriod = nil
        }
    }

    @ViewBuilder private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Column

    private var searchOpen: Bool { navigation.historySearchShown || store.historyFilter.isActive }

    private func column(_ listed: [StoryPeriodProjection], _ facts: InsightRangeFacts) -> some View {
        let reading = InsightRangeReading(periods: listed, scope: navigation.insightRange)
        return VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            if searchOpen {
                HistoryFindBar(store: store) { navigation.historySearchShown = false }
                    .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            }
            if store.historyFilter.isActive {
                HistoryFindResults(store: store, navigation: navigation)
            } else if reading.isEmpty {
                StoryHeadline(eyebrow: reading.eyebrow,
                              sentence: "Nothing was recorded in \(reading.spanPhrase).",
                              facts: [], highlight: nil)
                emptyRange
            } else {
                headline(reading)
                let pick: (StoryPeriodProjection) -> Void = { picked in
                    selection.id = selection.id == picked.id ? nil : picked.id
                    unfolded.id = nil
                }
                if navigation.insightRange == .month {
                    InsightMonthCalendars(periods: listed.reversed(),
                                          goal: store.goal.goal,
                                          selectedID: selection.id,
                                          onPick: pick)
                        .storyRenderEvidence(.insightPeriod)
                } else {
                    InsightTrendChart(periods: listed.reversed(),
                                      scope: navigation.insightRange,
                                      selectedID: selection.id,
                                      onPick: pick)
                        .storyRenderEvidence(.insightPeriod)
                }
                if let picked = listed.first(where: { $0.id == selection.id }) {
                    // The story unfolds here, as a picked day does under the
                    // week chart. Reading a period never leaves Insights.
                    InsightPickedPeriodCard(period: picked, isExpanded: unfolded.id == picked.id) {
                        unfolded.id = unfolded.id == picked.id ? nil : picked.id
                    }
                    .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
                    if unfolded.id == picked.id {
                        InsightPeriodStory(store: store, period: picked)
                            .id(picked.id)
                            .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
                    }
                }
                // A day already has a shape: the strip the story and History
                // draw. Rows of those read as a stack of days; the hour grid
                // is for the spans that sum many days into one row.
                if navigation.insightRange == .day {
                    InsightDayStrips(periods: listed)
                } else if facts.gridPeak > 0 {
                    InsightHourGrid(facts: facts)
                }
                if !facts.categories.isEmpty {
                    categories(facts)
                }
            }
        }
        .padding(StoryStyle.columnInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .id("\(navigation.insightRange)-\(navigation.insightAnchorLabel)-\(navigation.insightShownCount)")
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: selection.id)
        .animation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion),
                   value: unfolded.id)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: searchOpen)
    }

    private var archive: HistoryArchiveFacts { store.historyArchiveFacts() }

    /// What the rail shows for a picked day: its preview, then the archive's
    /// totals. It used to be reachable only inside the Year span, which made a
    /// picked day's preview disappear with it.
    @ViewBuilder private var pickedPreview: some View {
        if let date = navigation.reviewSelectedDate {
            let projection = store.storyDayProjection(on: date)
            HistoryDayPreview(store: store, projection: projection) {
                navigation.openDay(date)
            }
            .id(projection.id)
            .accessibilityIdentifier("history-story-detail-content-\(projection.id)")
            .storyRenderEvidence(.historyDetail)
            .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder private func headline(_ reading: InsightRangeReading) -> some View {
        let block = StoryHeadline(eyebrow: reading.eyebrow,
                                  sentence: reading.sentence,
                                  facts: reading.facts,
                                  highlight: Tokens.duration(reading.focused))
        if reading.strongestDay != nil {
            block.storyRenderEvidence(.insightStrongestDay)
        } else {
            block
        }
    }

    private func categories(_ facts: InsightRangeFacts) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Focus by category")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            CategoryShareBar(shares: facts.categories)
            if showsCurrentPatterns, let placed = surface.categories {
                Text("Where each lands in the day: \(placed.headline).")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyRange: some View {
        StoryTile(title: "Nothing recorded yet", trailing: nil) {
            Text("History fills in as you work. Each \(navigation.insightRange.title.lowercased()) "
                 + "you record appears here, with its story one click away.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StartButton(title: "Start focus", fills: false) {
                navigation.performSessionControlsAction(.commandOrMenu)
            }
            .fixedSize()
            .accessibilityLabel("Start a focus session")
        }
        .frame(maxWidth: 520, alignment: .leading)
        .accessibilityIdentifier("insights-empty-range")
        .storyRenderEvidence(.insightEmptyPeriod)
    }

    // MARK: - Rail

    private var showsCurrentPatterns: Bool {
        navigation.insightRange != .day
            && Calendar.current.isDate(navigation.insightAnchor, inSameDayAs: store.now())
    }

    private func rail(_ listed: [StoryPeriodProjection], _ facts: InsightRangeFacts) -> some View {
        let reading = InsightRangeReading(periods: listed, scope: navigation.insightRange)
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if store.historyFilter.isActive || navigation.reviewSelectedDate != nil {
                pickedPreview
                if !store.historyDays.isEmpty {
                    HistoryArchiveTiles(facts: archive, now: store.now(), appLimit: store.engine.store.menuAppCount)
                }
            } else if !reading.isEmpty {
                // The headline gives the range's total, focused days, average
                // and recorded app use; the hour grid's caption gives the best
                // two hours whenever the grid is drawn, which a day span is not.
                if navigation.insightRange == .day, let window = facts.bestWindow {
                    bestHoursTile(window, facts)
                }
                if !facts.goalRates.isEmpty { goalsTile(facts.goalRates) }
                if !facts.apps.isEmpty { appsTile(facts.apps) }
            }
            if showsCurrentPatterns, surface.hasEvidence {
                Text("This \(navigation.insightRange.title.lowercased()) so far")
                    .font(Tokens.Typography.metadata.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, Tokens.Space.s)
                if let pace = surface.pace { InsightSection(title: "Pace", insight: pace) }
                if let quality = surface.quality {
                    InsightSection(title: "Focus quality", insight: quality)
                }
                if let continuity = surface.continuity {
                    InsightSection(title: "Continuity", insight: continuity)
                }
            } else if showsCurrentPatterns {
                Text(InsightSurface.insufficientEvidenceCopy)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bestHoursTile(_ window: (startHour: Int, seconds: TimeInterval),
                               _ facts: InsightRangeFacts) -> some View {
        StoryTile(title: "Best two hours", trailing: nil) {
            Text("\(InsightHourGrid.hourLabel(window.startHour)) – \(InsightHourGrid.hourLabel(window.startHour + 2))")
                .font(Tokens.Typography.sectionTitle)
            Text(bestHoursNote(window, facts))
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bestHoursNote(_ window: (startHour: Int, seconds: TimeInterval),
                               _ facts: InsightRangeFacts) -> String {
        var note = "\(Tokens.duration(window.seconds)) of focus fell here"
        if let phrase = facts.bestWindowPhrase { note += ", most of it \(phrase)" }
        return note + "."
    }

    private func goalsTile(_ rates: [InsightGoalRate]) -> some View {
        StoryTile(title: "Category goals", trailing: "days met") {
            ForEach(rates) { rate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: rate.workType.symbolName)
                            .font(Tokens.Typography.microLabel)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Tokens.Palette.workType(rate.workType))
                            .frame(width: 14)
                        Text(rate.workType.displayName)
                            .font(Tokens.Typography.metadata)
                        Spacer(minLength: Tokens.Space.s)
                        Text("\(rate.metDays) of \(rate.focusedDays)")
                            .font(Tokens.Typography.metadata.monospacedDigit())
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
                .accessibilityLabel("\(rate.workType.displayName): \(Tokens.duration(rate.goal)) goal met on "
                                    + "\(rate.metDays) of \(rate.focusedDays) focused days")
            }
        }
    }

    private func appsTile(_ apps: [AppRank]) -> some View {
        let limit = store.engine.store.menuAppCount
        return StoryTile(title: apps.count > limit ? "Your top \(limit) apps" : "Your apps",
                  trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
            ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: index)
            }
        }
    }
}

/// The words and figures for a whole range, derived from its periods only.
struct InsightRangeReading {
    let periods: [StoryPeriodProjection]
    let scope: InsightRange
    private let calendar = Calendar.current

    var focused: TimeInterval { periods.reduce(0) { $0 + $1.focused } }
    var tracked: TimeInterval { periods.reduce(0) { $0 + $1.tracked } }
    var isEmpty: Bool {
        periods.allSatisfy { $0.focused == 0 && $0.tracked == 0 && $0.goalCredit == 0 }
    }

    private var days: [StoryDayProjection] { periods.flatMap(\.days) }
    var focusedDays: Int { days.filter { $0.focused > 0 }.count }

    var strongestDay: StoryDayProjection? {
        days.filter { $0.focused > 0 }.max { $0.focused < $1.focused }
    }

    private var strongestPeriod: StoryPeriodProjection? {
        periods.filter { $0.focused > 0 }.max { $0.focused < $1.focused }
    }

    private var unit: String {
        switch scope {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        }
    }

    var spanPhrase: String {
        periods.count == 1 ? "this \(unit)" : "these \(periods.count) \(unit)s"
    }

    var rangeLabel: String {
        guard let first = periods.last?.start, let lastEnd = periods.first?.end,
              let last = calendar.date(byAdding: .day, value: -1, to: lastEnd) else { return "" }
        return Tokens.dateRange(first, last)
    }

    var eyebrow: String {
        let count = periods.count == 1 ? "1 \(unit)" : "\(periods.count) \(unit)s"
        return rangeLabel.isEmpty ? count : "\(count) · \(rangeLabel)"
    }

    var sentence: String {
        guard focused > 0 else {
            return "You recorded \(Tokens.preciseDuration(tracked)) of app use across \(spanPhrase), with no focus session."
        }
        let dayWord = focusedDays == 1 ? "day" : "days"
        let spread = scope == .day && periods.count > 1 && focusedDays == periods.count
            ? "on every one of them" : "on \(focusedDays) \(dayWord)"
        var text = "Across \(spanPhrase) you focused \(Tokens.duration(focused)) \(spread)"
        if scope != .day, periods.count > 1, let best = strongestPeriod {
            text += "; the strongest \(unit) was \(Self.label(best, calendar: calendar)) "
                + "with \(Tokens.duration(best.focused))"
        }
        return text + "."
    }

    var facts: [String] {
        var parts: [String] = []
        if focusedDays > 0 {
            parts.append("\(Tokens.duration(focused / Double(focusedDays))) per focused day")
        }
        // With no focus the sentence itself names the app use.
        if focused > 0, tracked > 0 {
            parts.append("\(Tokens.preciseDuration(tracked)) recorded app use")
        }
        if let best = strongestDay {
            parts.append("strongest day \(Tokens.longDate(best.date)), \(Tokens.preciseDuration(best.focused))")
        }
        return parts
    }

    static func label(_ period: StoryPeriodProjection, calendar: Calendar = .current) -> String {
        switch period.scope {
        case .day:
            return Tokens.longDate(period.start)
        case .month:
            return DateFormats.australian("MMMM yyyy").string(from: period.start)
        case .week:
            let end = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
            return Tokens.dateRange(period.start, end)
        }
    }
}

/// The period picked from a bar, with the one action that opens it as a story.
struct InsightPickedPeriodCard: View {
    let period: StoryPeriodProjection
    let isExpanded: Bool
    let onOpen: () -> Void

    var body: some View {
        SurfacePanel(showsHeader: false) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                Text(InsightRangeReading.label(period))
                    .font(Tokens.Typography.sectionTitle)
                Text(Tokens.duration(period.focused))
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                    .foregroundStyle(Tokens.Colour.focus)
                Spacer(minLength: Tokens.Space.m)
                Button(action: onOpen) {
                    Text(isExpanded ? "Hide story" : "Open as a story ›")
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .foregroundStyle(StoryStyle.action)
                }
                .buttonStyle(StoryPressStyle())
                .accessibilityLabel(isExpanded
                    ? "Hide \(InsightRangeReading.label(period)) story"
                    : "Open \(InsightRangeReading.label(period)) as a story")
            }
            Text(note)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var note: String {
        guard period.focused > 0 || period.tracked > 0 else { return "Nothing was recorded in this period." }
        var parts: [String] = []
        if period.scope != .day {
            parts.append(period.activeDays == 1 ? "1 active day" : "\(period.activeDays) active days")
        } else if let day = period.days.first, day.focusSessionCount > 0 {
            // The day's story below opens without its headline, so the card
            // carries the session count that sentence used to give.
            parts.append(day.focusSessionCount == 1 ? "1 session" : "\(day.focusSessionCount) sessions")
        }
        if period.tracked > 0 {
            parts.append("\(Tokens.duration(period.tracked)) recorded app use")
        }
        if period.scope != .day,
           let best = period.days.filter({ $0.focused > 0 }).max(by: { $0.focused < $1.focused }) {
            parts.append("strongest day \(Tokens.longDate(best.date)), \(Tokens.preciseDuration(best.focused))")
        }
        return parts.joined(separator: " · ")
    }
}

/// A picked period told in place. A day is its own story; a week or a month
/// is its recorded days, each of which unfolds into that day's story.
struct InsightPeriodStory: View {
    @ObservedObject var store: SessionStore
    let period: StoryPeriodProjection
    @StateObject private var openDay = HoverBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recordedDays: [StoryDayProjection] {
        period.days.filter { $0.focused > 0 || $0.tracked > 0 || !$0.sessions.isEmpty }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        if period.scope == .day, let day = period.days.first {
            ProjectedDayStoryColumn(store: store, projection: day, context: .underCard)
        } else if recordedDays.isEmpty {
            Text("Nothing was recorded in this period.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HistoryStripAxis()
                ForEach(recordedDays) { day in
                    HistoryDayRow(day: historyDay(day), projection: day,
                                  context: context(day),
                                  isSelected: openDay.id == day.id) {
                        withAnimation(Tokens.Motion.animation(Tokens.Motion.reveal,
                                                              reduceMotion: reduceMotion)) {
                            openDay.id = openDay.id == day.id ? nil : day.id
                        }
                    } onOpen: {}
                    if openDay.id == day.id {
                        ProjectedDayStoryColumn(store: store, projection: day, context: .underRow)
                            .id(day.id)
                            .padding(.vertical, Tokens.Space.l)
                            .padding(.leading, HistoryRowLayout.inset)
                            .transition(Tokens.Motion.transition(Tokens.Motion.unfold,
                                                                 reduceMotion: reduceMotion))
                    }
                }
            }
        }
    }

    private func historyDay(_ day: StoryDayProjection) -> HistoryDay {
        HistoryDay(date: day.date, tracked: day.tracked, focused: day.focused,
                   sessions: day.focusSessionCount,
                   appBundleIDs: Set(day.apps.map(\.bundleID)),
                   workTypes: Set(workTypes(day)))
    }

    private func workTypes(_ day: StoryDayProjection) -> [WorkType] {
        day.sessions.compactMap { entry -> WorkType? in
            if case .session(let session) = entry { return session.workType }
            return nil
        }
    }

    private func context(_ day: StoryDayProjection) -> String {
        let types = WorkType.ordered(Array(Set(workTypes(day)))).map(\.displayName)
        let apps = day.apps.prefix(3).map(\.appName)
        let typeText = types.isEmpty ? nil : types.joined(separator: ", ")
        let appText = apps.isEmpty ? nil : apps.joined(separator: ", ")
            + (day.apps.count > 3 ? " +\(day.apps.count - 3)" : "")
        return [typeText, appText].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct InsightWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension InsightRange {
    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}
