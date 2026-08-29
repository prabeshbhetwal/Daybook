import SwiftUI

/// Period comparison and searchable History. Week and Month share one exact
/// tracked-time read model; History is a separate chronological record rather
/// than a third chart.
struct ReviewView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
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
        }
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
        .animation(.easeInOut(duration: 0.18), value: navigation.reviewSection)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review")
                    .font(Tokens.Typography.title)
                Text(navigation.reviewSection == .history
                     ? "Search the local record and open any day in Today."
                     : store.reviewSummaryLine)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.l)
            ReviewSectionPills(selection: sectionBinding)
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

        if store.reviewSummary.activeDays == 0 {
            SurfacePanel(showsHeader: false) {
                EmptyState("No comparable days yet",
                           detail: "Week and month history builds locally as app usage is recorded.",
                           icon: "chart.bar")
            }
        } else {
            SurfacePanel(showsHeader: false) {
                SectionHeader(title: "Tracked by day",
                              trailing: "bars and average use exact tracked time")
                PeriodChart(days: store.reviewDays,
                            average: store.reviewSummary.averagePerActiveDay,
                            height: 190,
                            onPickDay: openDay)
            }

            periodSummary

            HStack(alignment: .top, spacing: Tokens.Space.l) {
                topApps
                workTypeComposition
            }
            .fixedSize(horizontal: false, vertical: true)

            SurfacePanel(showsHeader: false) {
                SessionLogList(entries: store.reviewLog,
                               dayTotals: store.reviewDayTotals,
                               grouping: .byTime)
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
            IconButton(systemImage: "chevron.right",
                       help: store.reviewPeriod == .week ? "Next week" : "Next month") {
                store.moveReviewPeriod(by: 1)
            }
            .disabled(!store.reviewCanMoveForward)
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review period, \(store.reviewPeriodLabel)")
    }

    private var periodSummary: some View {
        SurfacePanel(title: "Period summary", layout: .compact) {
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                ReviewMetric(label: "Tracked", value: Tokens.duration(store.reviewSummary.tracked),
                             note: "exact app usage")
                ReviewMetric(label: "Active days",
                             value: "\(store.reviewSummary.activeDays) of "
                                + "\(store.reviewSummary.totalDays)",
                             note: "days with tracked time")
                ReviewMetric(label: "Average / active day",
                             value: Tokens.duration(store.reviewSummary.averagePerActiveDay),
                             note: "same tracked series")
                ReviewMetric(label: "Longest focus stretch",
                             value: store.reviewLongestFocusSeconds > 0
                                ? Tokens.preciseDuration(store.reviewLongestFocusSeconds) : "—",
                             note: store.reviewLongestFocusName)
            }
        }
    }

    private var topApps: some View {
        SurfacePanel(title: "Top apps") {
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

    private func openDay(_ date: Date) {
        // Select the exact day before the tab changes. Today owns this route;
        // Review never mutates its day for ordinary period navigation.
        store.selectDate(date)
        navigation.openToday(date: date)
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
                        .frame(minHeight: 28)
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
            }
        }
        .padding(3)
        .background(Tokens.Colour.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Colour.line))
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
                    .font(Tokens.Typography.detail)
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
