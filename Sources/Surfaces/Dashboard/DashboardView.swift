import SwiftUI

/// One column of cards on the ground, top to bottom: the title band, the hero
/// (ring + session + today's headline figures), the apps running now as
/// chips, four KPI cards with a week of shape under each number, the day's
/// rhythm beside the goal ring, then app share · work type · insights, then
/// the session log. No right rail — everything it held is a card or a chip.
struct DashboardView: View {
    @ObservedObject var store: SessionStore
    @StateObject private var calendarShown = BoolBox()

    /// `ScrollView` has no intrinsic content under `ImageRenderer`, so the
    /// snapshot harness renders the column unscrolled. Same views either way.
    var scrolls: Bool = true

    var body: some View {
        wrap { column }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Tokens.Surface.ground)
            .onAppear {
                // Reopening the window is a fresh question, and the question is
                // almost always about today.
                store.goToToday()
                store.refresh()
            }
    }

    @ViewBuilder private func wrap<Content: View>(
        @ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content()
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            titleBand
            DashboardHero(store: store)
            // The timeline is the day's spine, so it comes first — full width,
            // straight under the hero.
            if store.period == .day {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    SectionHeader(title: "Timeline",
                                  trailing: store.framedSession == nil
                                      ? "hover a session to light it up" : nil)
                    DayTimelineView(store: store)
                }
                .card()
            }
            // What is running now belongs to today; a past day shows only itself.
            if store.isToday && !store.runningApps.isEmpty {
                RunningNowChips(apps: store.runningApps)
            }
            if !store.summarySentences.isEmpty {
                SummaryCard(sentences: store.summarySentences)
            }
            kpiRow
            chartRow
            SessionsCard(entries: store.daySessions, selected: store.selectedSession,
                         onHover: { store.hoverSession($0) },
                         onSelect: { store.selectSession($0) })
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .card(padding: Tokens.Space.m)
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                appShareCard
                workTypeCard
                insightsCard
            }
            .fixedSize(horizontal: false, vertical: true)
            sessionLogSection
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onExitCommand { store.clearSession() }
        .animation(.easeInOut(duration: 0.25), value: store.dayOffset)
        .animation(.easeInOut(duration: 0.2), value: store.selectedSession?.id)
    }

    // MARK: - Title band

    /// The day, the date, the streak and the goal in one line; the scope
    /// controls beside them because they govern everything beneath.
    private var titleBand: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.dayLabel)
                    .font(Tokens.Typography.title)
                Text(subtitle)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            periodControls
        }
    }

    private var subtitle: String {
        if !store.isToday { return store.selectedDaySummary }
        var parts = [Tokens.longDate(store.selectedDay)]
        if store.streak > 0 {
            parts.append(store.streak == 1 ? "1-day streak" : "\(store.streak)-day streak")
        }
        if store.isToday {
            parts.append(store.goal.isMet
                         ? "Goal met"
                         : "\(Tokens.duration(store.goal.achieved)) of "
                           + "\(Tokens.duration(store.goal.goal))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - KPI row and charts

    private var kpiRow: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            ForEach(store.statFigures) { figure in
                StatCard(label: figure.label, value: figure.value,
                         context: figure.detail, contextTint: figure.tint,
                         spark: figure.spark, sparkTint: figure.sparkTint ?? .accentColor,
                         symbol: figure.symbol, badge: figure.badge, badgeTint: figure.badgeTint)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var chartRow: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                if store.period == .day {
                    SectionHeader(title: "Rhythm · minutes at the Mac per hour",
                                  trailing: store.rhythmPeak.map { "peak \($0)" })
                    RhythmChart(hours: store.rhythm, onHourTap: { store.selectHour($0) })
                } else {
                    SectionHeader(title: "By day")
                    PeriodChart(days: store.periodDays,
                                average: store.periodSummary.averagePerActiveDay,
                                onPickDay: { day in
                                    store.selectDate(day)
                                    store.period = .day
                                })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            if store.period == .day {
                goalCard
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The goal as a ring on its own, with the figures spelled out beneath —
    /// the selected day's goal, live on today.
    private var goalCard: some View {
        let goal = store.selectedDayGoal
        return VStack(spacing: Tokens.Space.s) {
            GoalRing(progress: goal.share, diameter: 104, lineWidth: 10,
                     label: "\(Int((min(goal.share, 9.99) * 100).rounded()))%",
                     isMet: goal.isMet,
                     labelFont: Font.system(size: 20, weight: .semibold, design: .rounded)
                         .monospacedDigit())
            VStack(spacing: 2) {
                HStack(spacing: Tokens.Space.xs) {
                    Text(Tokens.duration(goal.achieved))
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text("of \(Tokens.duration(goal.goal))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(goalContext)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 228)
        .frame(maxHeight: .infinity)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var goalContext: String {
        let goal = store.selectedDayGoal
        if goal.isMet { return "Goal met" }
        // "to go" is a promise about the rest of the day; a finished day fell short.
        var text = "\(Tokens.duration(max(0, goal.goal - goal.achieved))) "
            + (store.isToday ? "to go" : "short")
        if let ahead = goal.aheadBy {
            if ahead >= 60 { text += " · \(Tokens.duration(ahead)) ahead" }
            else if ahead <= -60 { text += " · \(Tokens.duration(-ahead)) behind" }
            else { text += " · on pace" }
        }
        return text
    }

    // MARK: - Row three

    private var appShareCard: some View {
        Group {
            if store.appShareRanks.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    SectionHeader(title: "App share")
                    Text("Tracking starts when you switch apps.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    if let session = store.selectedSession {
                        HStack {
                            Spacer()
                            Button { store.clearSession() } label: {
                                HStack(spacing: Tokens.Space.xs) {
                                    Text("Session · \(Tokens.timeRange(session.start, session.end))")
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, Tokens.Space.s).padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            .help("Show the whole day again (Esc)")
                        }
                    }
                    TopAppsList(apps: Array(store.appShareRanks.prefix(6)),
                                sessionsToday: store.sessionsToday,
                                store: store.period == .day ? store : nil,
                                compact: true,
                                title: store.selectedSession == nil ? "App share" : "Apps in this session",
                                trailingOverride: store.appShareRanks.count == 1
                                    ? "1 app" : "\(store.appShareRanks.count) apps",
                                expandedApps: store.expandedApps)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private var workTypeCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            SectionHeader(title: "Work type")
            WorkTypeDonut(shares: store.workTypeShares)
            if store.period == .day, store.focusQuality.sessionCount > 0 {
                Text("\(Int((store.focusQuality.insideSessionShare * 100).rounded()))% of tracked "
                     + "time in a session · "
                     + String(format: "%.1f switches / stretch",
                              store.focusQuality.switchesPerSession))
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private var insightsCard: some View {
        Group {
            if store.insights.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    SectionHeader(title: "Insights")
                    Text("Nothing to remark on yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                InsightsList(insights: store.insights)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    // MARK: - Session log

    private var sessionLogSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Picker("Grouping", selection: groupingBinding) {
                    ForEach(LogGrouping.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .quietFocus()
                .frame(width: 160)
                Spacer()
            }
            SessionLogList(entries: store.periodLog,
                           dayTotals: store.periodDayTotals,
                           groups: store.periodAppGroups,
                           grouping: store.logGrouping,
                           store: store,
                           showsHourly: store.period == .day,
                           periodBounds: store.periodBounds,
                           expandedApps: store.expandedApps,
                           showsMinorApps: store.showsMinorApps)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Scope controls

    private var periodControls: some View {
        HStack(alignment: .center) {
            Picker("Period", selection: periodBinding) {
                ForEach(TrackingPeriod.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .quietFocus()
            .frame(width: 220)
            dayStepper
        }
    }

    private var groupingBinding: Binding<LogGrouping> {
        Binding(get: { store.logGrouping }, set: { store.logGrouping = $0 })
    }

    private var periodBinding: Binding<TrackingPeriod> {
        Binding(get: { store.period }, set: { store.period = $0 })
    }

    /// One control that reaches any date. Bounded so it can never land on a day
    /// with no data behind it, or in the future.
    private var dayStepper: some View {
        HStack(spacing: Tokens.Space.xs) {
            Button { store.stepDay(by: -1) } label: { Image(systemName: "chevron.left") }
                .disabled(!store.canStepBack)
            Button { calendarShown.value.toggle() } label: {
                Text(store.dayLabel)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.plain)
            .help("Pick a date")
            .popover(isPresented: Binding(get: { calendarShown.value },
                                          set: { calendarShown.value = $0 })) {
                DayPickerCalendar(selected: store.selectedDay,
                                  earliest: store.earliestSelectableDay,
                                  goal: store.goal.goal,
                                  facts: { store.dayFacts(inMonthOf: $0) }) { day in
                    store.selectDate(day)
                    calendarShown.value = false
                }
            }
            Button { store.stepDay(by: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(!store.canStepForward)
            if !store.isToday {
                Button("Today") { store.goToToday() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.caption)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.borderless)
    }
}
