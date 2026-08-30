import SwiftUI

/// The exact callback supplied to period bars and History day rows. Selecting
/// evidence explains that day inside Review; it never changes the tab and never
/// moves Today's own selected day. Opening the day in Today is a separate,
/// visibly named action on the selected-day detail.
@MainActor
enum ReviewDayRoute {
    static func select(store: SessionStore,
                       navigation: MainWindowModel) -> (Date) -> Void {
        { date in
            navigation.selectReviewDay(date)
        }
    }
}

/// Review's invariant reading sequence. Naming it makes the hierarchy testable
/// and stops a later edit from letting a breakdown drift above the answer it is
/// meant to support.
enum ReviewContentOrder: CaseIterable {
    case periodNavigation, summary, trend, selectedDetail, breakdowns, evidenceLists

    static func visible(selectedDay: Date?) -> [ReviewContentOrder] {
        allCases.filter { $0 != .selectedDetail || selectedDay != nil }
    }
}

/// Period comparison and searchable History. Week and Month share one exact
/// tracked-time read model; History is a separate chronological record rather
/// than a third chart.
struct ReviewView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The repository renderer cannot infer a `ScrollView`'s intrinsic height.
    var scrolls = true

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Tokens.Colour.ground)
        .onAppear {
            store.selectReviewSection(navigation.reviewSection)
            store.setReviewVisible(true)
        }
        .onDisappear { store.setReviewVisible(false) }
        .onChange(of: navigation.reviewSection) { section in
            store.selectReviewSection(section)
            clearSelectedDayIfUnavailable()
        }
        .onChange(of: store.reviewPeriod) { _ in clearSelectedDayIfUnavailable() }
        .onChange(of: store.reviewDays) { _ in clearSelectedDayIfUnavailable() }
        .onChange(of: store.historyFilter) { _ in clearSelectedDayIfUnavailable() }
        .onChange(of: store.historyRangeStart) { _ in clearSelectedDayIfUnavailable() }
        .onChange(of: store.historyRangeEnd) { _ in clearSelectedDayIfUnavailable() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            header
            if navigation.reviewSection == .history {
                HistoryView(store: store, navigation: navigation)
            } else {
                periodContent
            }
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                   value: navigation.reviewSection)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review")
                    .font(Tokens.Typography.pageTitle)
                Text(navigation.reviewSection == .history
                     ? "Search the local record, select a day for detail, then open it in Today when needed."
                     : store.reviewSummaryLine)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.l)
            ReviewSectionPills(selection: sectionBinding)
        }
    }

    /// Nil unless Review still has canonical evidence for the selected day in
    /// the section being shown. Availability is checked here as well as in the
    /// clearing handlers, so a stale date can never render against a period it
    /// no longer belongs to.
    private var selectedDayDetail: ReviewDayDetail? {
        guard let date = navigation.reviewSelectedDate,
              store.reviewDayIsAvailable(date, section: navigation.reviewSection) else {
            return nil
        }
        return store.reviewDayDetail(for: date)
    }

    /// Clears a selection the user can no longer see. A refresh that leaves the
    /// day inside the shown evidence deliberately keeps it selected.
    private func clearSelectedDayIfUnavailable() {
        guard let date = navigation.reviewSelectedDate else { return }
        if !store.reviewDayIsAvailable(date, section: navigation.reviewSection) {
            navigation.clearReviewDay()
        }
    }

    private var sectionBinding: Binding<ReviewSection> {
        Binding(get: { navigation.reviewSection },
                set: { navigation.reviewSection = $0 })
    }

    @ViewBuilder private var periodContent: some View {
        periodNavigation

        if let note = store.reviewIntegrityNote {
            IntegrityNotice(note)
        }

        if !store.reviewHasRelevantEvidence {
            SurfacePanel(showsHeader: false) {
                EmptyState("No comparable days yet",
                           detail: "Week and month history builds locally as app usage is recorded.",
                           icon: "chart.bar")
            }
        } else {
            // The period answer, then the trend that supports it, then the day
            // the user selected from that trend. Breakdowns and raw evidence
            // follow interpretation rather than competing with it.
            periodSummary

            SurfacePanel(showsHeader: false) {
                SectionHeader(title: "Tracked by day",
                              trailing: "bars and average use exact tracked time")
                PeriodChart(days: store.reviewDays,
                            average: store.reviewSummary.averagePerActiveDay,
                            height: 190,
                            selectedDay: navigation.reviewSelectedDate,
                            onPickDay: ReviewDayRoute.select(
                                store: store, navigation: navigation))
            }

            if let detail = selectedDayDetail {
                ReviewDayDetailPanel(
                    detail: detail,
                    onOpenInToday: { navigation.openSelectedReviewDayInToday() },
                    onClose: { navigation.clearReviewDay() })
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Tokens.Space.l) {
                    topApps
                    workTypeComposition
                }
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    topApps
                    workTypeComposition
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if !store.reviewFocusSessions.isEmpty {
                focusSessions
            }

            if !store.reviewLog.isEmpty {
                SurfacePanel(showsHeader: false) {
                    if store.reviewLogRowsOmitted > 0 {
                        Label(store.reviewLogRowsQualification,
                              systemImage: "line.3.horizontal.decrease")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(store.reviewLogRowsQualification)
                    }
                    SessionLogList(entries: store.reviewLog,
                                   dayTotals: store.reviewDayTotals,
                                   grouping: .byTime)
                }
            }
        }
    }

    private var periodNavigation: some View {
        HStack(spacing: Tokens.Space.s) {
            IconButton(systemImage: "chevron.left",
                       help: store.reviewPeriod == .week ? "Previous week" : "Previous month") {
                store.moveReviewPeriod(by: -1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.reviewPeriodLabel)
                    .font(Tokens.Typography.sectionTitle)
                Text(store.reviewPeriod == .week ? "Calendar week" : "Calendar month")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(store.reviewPeriodLabel), selected period")
            .accessibilityAddTraits(.isSelected)
            IconButton(systemImage: "chevron.right",
                       help: store.reviewPeriod == .week ? "Next week" : "Next month") {
                store.moveReviewPeriod(by: 1)
            }
            .disabled(!store.reviewCanMoveForward)
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review period, \(store.reviewPeriodLabel), selected")
    }

    private var periodSummary: some View {
        SurfacePanel(title: "Period summary", layout: .compact) {
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                ReviewMetric(label: "Tracked", value: Tokens.duration(store.reviewSummary.tracked),
                             note: store.reviewSummary.tracked > 0
                                ? "exact app usage" : "No tracked time recorded")
                ReviewMetric(label: "Active days",
                             value: "\(store.reviewSummary.activeDays) of "
                                + "\(store.reviewSummary.totalDays)",
                             note: "days with tracked time")
                ReviewMetric(label: "Average / active day",
                             value: store.reviewSummary.activeDays > 0
                                ? Tokens.duration(store.reviewSummary.averagePerActiveDay) : "—",
                             note: store.reviewSummary.activeDays > 0
                                ? "same tracked series" : "No tracked-day average")
                ReviewMetric(label: "Longest focus stretch",
                             value: store.reviewLongestFocusSeconds > 0
                                ? Tokens.preciseDuration(store.reviewLongestFocusSeconds) : "—",
                             note: store.reviewLongestFocusName)
            }
        }
    }

    private var focusSessions: some View {
        SurfacePanel(showsHeader: false) {
            SectionHeader(title: "Focus sessions",
                          trailing: focusSessionCountLabel)
            if store.reviewFocusRowsOmitted > 0 {
                Label(store.reviewFocusRowsQualification,
                      systemImage: "line.3.horizontal.decrease")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(store.reviewFocusRowsQualification)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(store.reviewFocusSessionRows.enumerated()),
                        id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    HStack(spacing: Tokens.Space.m) {
                        Image(systemName: entry.workType.symbolName)
                            .foregroundStyle(Tokens.Palette.workType(entry.workType))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(Tokens.Typography.rowTitle)
                            Text(entry.workType.displayName + " · "
                                 + Tokens.timeRange(entry.start, entry.end))
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Tokens.preciseDuration(entry.seconds))
                            .font(.callout.monospacedDigit())
                    }
                    .padding(.vertical, Tokens.Space.xs)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var focusSessionCountLabel: String {
        let sessions = store.reviewFocusSessionCount == 1
            ? "1 session" : "\(store.reviewFocusSessionCount) sessions"
        let stretches = store.reviewFocusSessions.count == 1
            ? "1 stretch" : "\(store.reviewFocusSessions.count) stretches"
        return sessions + (store.reviewFocusSessionCount == store.reviewFocusSessions.count
                           ? "" : " · \(stretches)")
    }

    private var topApps: some View {
        SurfacePanel(showsHeader: false) {
            SectionHeader(title: "Top apps",
                          trailing: store.reviewAppAggregateQualification)
            if store.reviewAppGroups.isEmpty {
                Text("No app usage in this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.reviewAppGroups.prefix(5).enumerated()),
                        id: \.element.id) { index, group in
                    if index > 0 { Divider() }
                    AppUsageRow(appName: group.appName, bundleID: group.bundleID,
                                rank: index, seconds: group.total, share: group.share,
                                layout: .compact)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var workTypeComposition: some View {
        SurfacePanel(title: "Work type") {
            if store.reviewWorkTypeShares.isEmpty {
                Text("No focus sessions in this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                WorkTypeDonut(shares: store.reviewWorkTypeShares,
                              diameter: 96, lineWidth: 14)
            }
            Text("Composition is shown separately from tracked-time comparison.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

}

private struct ReviewSectionPills: View {
    @Binding var selection: ReviewSection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ReviewSection.allCases, id: \.rawValue) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.title)
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .padding(.horizontal, Tokens.Space.m)
                        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                        .background(selection == section
                                    ? Tokens.Colour.focus
                                    : Color.clear,
                                    in: Capsule())
                        .foregroundStyle(selection == section
                                         ? Tokens.Colour.onFocus
                                         : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.title), "
                                    + (selection == section ? "selected" : "not selected"))
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Tokens.Colour.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Colour.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review section")
    }
}

private struct ReviewMetric: View {
    let label: String
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(label)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Tokens.Typography.metricValue.monospacedDigit())
            if let note {
                Text(note)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private extension ReviewSection {
    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .history: return "History"
        }
    }
}
