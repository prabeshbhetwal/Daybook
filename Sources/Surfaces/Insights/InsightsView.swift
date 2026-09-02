import SwiftUI

/// A deliberately sparse canvas. Every section corresponds to one optional in
/// `InsightSurface`; missing facts do not leave empty cards or zero labels.
struct InsightsView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scrolls = true

    private var surface: InsightSurface {
        store.insightSurface(for: navigation.insightRange)
    }

    private var periods: [StoryPeriodProjection] {
        store.insightPeriodProjections(scope: navigation.insightRange,
                                       anchoredAt: navigation.insightAnchor,
                                       limit: navigation.insightPageCount)
    }

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
            store.setInsightsVisible(true)
        }
        .onDisappear { store.setInsightsVisible(false) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            header
            periodPages
            if navigation.insightCanShowEarlier {
                Button("Show earlier periods") { navigation.showEarlierInsights() }
                    .buttonStyle(.borderless)
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            }
            if showsCurrentPatterns, surface.hasEvidence {
                Text("Evidence-backed patterns")
                    .font(Tokens.Typography.sectionTitle)
                sections
            } else if showsCurrentPatterns {
                SurfacePanel(showsHeader: false) {
                    EmptyState(InsightSurface.insufficientEvidenceCopy,
                               icon: "sparkles")
                }
                .frame(maxWidth: 620)
            }
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights")
                    .font(Tokens.Typography.pageTitle)
                Text("\(navigation.insightRange.title) summaries, newest first · anchored at \(navigation.insightAnchorLabel).")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.l)
            ScopePillRow(titles: InsightRange.allCases.map(\.title),
                         selectedIndex: Binding(
                            get: { InsightRange.allCases.firstIndex(of: navigation.insightRange) ?? 0 },
                            set: { navigation.selectInsightRange(InsightRange.allCases[$0]) }),
                         controlLabel: "Insights range")
        }
    }

    private var showsCurrentPatterns: Bool {
        navigation.insightRange != .day
            && Calendar.current.isDate(navigation.insightAnchor,
                                       inSameDayAs: store.now())
    }

    private var periodPages: some View {
        LazyVStack(alignment: .leading, spacing: Tokens.Space.m) {
            ForEach(periods) { period in
                SurfacePanel(showsHeader: false) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(periodLabel(period))
                            .font(Tokens.Typography.sectionTitle)
                        if period.isCurrent {
                            Text("so far")
                                .font(Tokens.Typography.metadata.weight(.semibold))
                                .foregroundStyle(StoryStyle.action)
                        }
                        Spacer()
                        Text(period.activeDays == 1 ? "1 active day"
                             : "\(period.activeDays) active days")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: Tokens.Space.xl) {
                        periodMetric("Logged focus", period.focused)
                        periodMetric("Recorded app use", period.tracked)
                        periodMetric("Goal credit", period.goalCredit)
                    }
                    if period.focused == 0 && period.tracked == 0 && period.goalCredit == 0 {
                        Text("No logged focus or recorded app use in this period.")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(
                                "insights-empty-period-content-\(period.id)")
                            .storyRenderEvidence(.insightEmptyPeriod)
                    }
                    if let best = period.days.filter({ $0.focused > 0 })
                        .max(by: { $0.focused < $1.focused }) {
                        Text("Strongest logged-focus day: \(Tokens.longDate(best.date)), \(Tokens.preciseDuration(best.focused)).")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(
                                "insights-strongest-day-content-\(period.id)")
                            .storyRenderEvidence(.insightStrongestDay)
                    }
                }
                .id(period.id)
                .accessibilityIdentifier("insights-period-content-\(period.id)")
                .storyRenderEvidence(.insightPeriod)
            }
        }
    }

    private func periodMetric(_ label: String, _ value: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Tokens.Typography.metadata).foregroundStyle(.secondary)
            Text(Tokens.preciseDuration(value))
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func periodLabel(_ period: StoryPeriodProjection) -> String {
        switch period.scope {
        case .day:
            return Tokens.longDate(period.start)
        case .month:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: period.start)
        case .week:
            let calendar = Calendar.current
            let end = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = "d MMM yyyy"
            return "\(formatter.string(from: period.start))–\(formatter.string(from: end))"
        }
    }

    private var sections: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380),
                                      spacing: Tokens.Space.l,
                                      alignment: .top)],
                  alignment: .leading,
                  spacing: Tokens.Space.l) {
            if let pace = surface.pace {
                InsightSection(title: "Pace", insight: pace)
            }
            if let rhythm = surface.rhythm {
                InsightSection(title: "Rhythm", insight: rhythm)
            }
            if let quality = surface.quality {
                InsightSection(title: "Focus quality", insight: quality)
            }
            if let continuity = surface.continuity {
                InsightSection(title: "Continuity", insight: continuity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                   value: navigation.insightRange)
    }
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
