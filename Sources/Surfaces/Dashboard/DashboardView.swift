import SwiftUI

/// Two columns: the narrative on the left, live state on the right. The right
/// column is fixed width so opening or quitting an app never reflows the left.
///
/// No stat-tile grid and no per-row cards — each figure sits beside the evidence
/// for it, and lists use hairline separators.
struct DashboardView: View {
    @ObservedObject var store: SessionStore
    @StateObject private var calendarShown = BoolBox()

    /// `ScrollView` has no intrinsic content under `ImageRenderer`, so the
    /// snapshot harness renders the columns unscrolled. Same views either way.
    var scrolls: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            wrap { leftColumn }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            wrap { rightColumn }
                .frame(width: 280, alignment: .topLeading)
        }
        .background(Tokens.Surface.ground)
        .onAppear {
            // Reopening the window is a fresh question, and the question is
            // almost always about today. The selection outlived a window close
            // before, so the dashboard reopened on whatever day was last browsed.
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

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            titleBand
            if !store.isIdle { activeSession }
            StatBand(figures: store.statFigures,
                     goal: store.period == .day && store.isToday ? store.goal : nil)
            sessionLogSection
            periodChart
            FocusQualityBar(quality: store.focusQuality, dayScopeLabel: dayScopeLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            RunningNowList(apps: store.runningApps)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: Tokens.Space.m)
            if !store.earlierToday.isEmpty {
                EarlierTodayList(apps: store.earlierToday, store: store,
                                 title: store.isToday ? "Earlier today" : "Earlier that day",
                                 expandedApps: store.expandedApps)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: Tokens.Space.m)
            }
            if !store.insights.isEmpty {
                InsightsList(insights: store.insights)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: Tokens.Space.m)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.l)
    }

    // MARK: - Active session

    /// The session in flight, as a slim card. Absent when idle — the popover
    /// owns starting.
    @ViewBuilder private var activeSession: some View {
        HStack(alignment: .center, spacing: Tokens.Space.l) {
            if let away = store.pendingAway {
                ResolveCard(away: away,
                            onMerge: { store.resolve(.mergeTime) },
                            onBreak: { store.resolve(.continueSession) },
                            onDiscard: { store.resolve(.resetTimer) },
                            onRest: { store.resolve(.tookBreak) },
                            framed: false)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tokens.clock(store.elapsed))
                        .font(Tokens.Typography.heroTimer)
                        .contentTransition(.numericText())
                        .foregroundStyle(store.isPaused ? AnyShapeStyle(.secondary)
                                                        : AnyShapeStyle(.primary))
                    Text(store.activeSessionSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Tokens.Space.s) {
                    if store.isAway {
                        Button("I'm back") { store.endAway() }
                            .buttonStyle(.borderedProminent)
                        Button("Stop") { store.stop() }
                    } else {
                        IconButton(systemImage: store.isPaused ? "play.fill" : "pause.fill",
                                   help: store.isPaused ? "Resume" : "Pause") {
                            store.togglePause()
                        }
                        IconButton(systemImage: "door.right.hand.open",
                                   help: "Away — stop the session and recording until you return") {
                            store.markAway()
                        }
                        Button("Stop") { store.stop() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Day

    /// Scope for everything beneath it, so it stays above the log it governs.
    private var periodControls: some View {
        HStack(alignment: .center) {
            Picker("Period", selection: periodBinding) {
                ForEach(TrackingPeriod.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Spacer()
            dayStepper
        }
    }

    @ViewBuilder private var periodChart: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: store.period == .day ? "Timeline" : "By day")
            if store.period == .day {
                DayTimelineView(store: store)
            } else {
                PeriodChart(days: store.periodDays,
                            average: store.periodSummary.averagePerActiveDay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Nil on Day, where every section shares one scope and a label is noise.
    private var dayScopeLabel: String? {
        store.period == .day ? nil : store.dayLabel
    }

    private var groupingBinding: Binding<LogGrouping> {
        Binding(get: { store.logGrouping }, set: { store.logGrouping = $0 })
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { store.selectedDay },
                set: { store.selectDate($0); calendarShown.value = false })
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
                DatePicker("", selection: dateBinding,
                           in: (store.earliestSelectableDay ?? Date())...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(Tokens.Space.m)
                    .frame(width: 260)
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
