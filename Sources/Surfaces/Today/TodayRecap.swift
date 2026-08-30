import SwiftUI

/// A quiet reconciliation line, not a KPI grid. Focused displays raw canonical
/// focus-session time; its note separately names focused-active goal credit.
/// At the Mac remains observed app-use time.
struct TodayRecap: View {
    @ObservedObject var store: SessionStore

    private var goal: GoalProgress { store.selectedDayGoal }
    private var sessions: Int {
        store.isToday ? store.sessionsToday : store.sessionsForSelectedDay
    }
    private var focused: TimeInterval {
        store.isToday ? store.todayTotal : store.focusedForSelectedDay
    }
    private var longest: TimeInterval {
        store.isToday ? store.longestToday : store.longestForSelectedDay
    }

    var body: some View {
        SurfacePanel(title: "Day recap", layout: .compact) {
            HStack(alignment: .top, spacing: Tokens.Space.xxl) {
                recapMetric("Focused", Tokens.duration(focused), note: goalNote)
                recapMetric("At the Mac", Tokens.duration(store.trackedForSelectedDay),
                            note: "observed app use")
                recapMetric("Sessions", "\(sessions)",
                            note: sessions == 1 ? "focus session" : "focus sessions")
                recapMetric("Longest", longest > 0 ? Tokens.preciseDuration(longest) : "—",
                            note: store.isToday ? store.longestNameToday
                                              : store.longestNameForSelectedDay)
            }
            if let insight = store.insights.first {
                Divider()
                HStack(alignment: .top, spacing: Tokens.Space.s) {
                    Image(systemName: insight.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Tokens.Colour.focus)
                    Text("\(insight.headline) · \(insight.detail)")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 820, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var goalNote: String {
        let counted = "goal credit " + Tokens.duration(goal.achieved)
        if goal.isMet { return counted + " · met" }
        let remainder = Tokens.duration(max(0, goal.goal - goal.achieved))
        return counted + (store.isToday ? " · \(remainder) to go" : " · \(remainder) short")
    }

    private func recapMetric(_ label: String, _ value: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            if let note {
                Text(note)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
