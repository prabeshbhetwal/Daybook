import SwiftUI

/// The day's canonical summary sentences, ready to render. `SummaryText` marks
/// its figures with `**` for a Markdown renderer; the recap is plain secondary
/// text, so every sentence is stripped here rather than showing the markers.
struct DayRecapNarrative: Equatable {
    let lead: String?
    let details: [String]

    init(sentences: [String]) {
        let plain = sentences.map { SummaryText.plain([$0]) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        lead = plain.first
        details = Array(plain.dropFirst())
    }
}

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
            narrative
        }
    }

    /// One summary fact, with the rest of the day's sentences behind a literal
    /// disclosure. Nothing is rendered when the day has produced no sentences.
    @ViewBuilder private var narrative: some View {
        let recap = DayRecapNarrative(sentences: store.summarySentences)
        if let lead = recap.lead {
            Divider()
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(lead)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 820, alignment: .leading)
                    .textSelection(.enabled)
                if !recap.details.isEmpty {
                    DisclosureGroup("More about this day") {
                        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                            ForEach(recap.details, id: \.self) { sentence in
                                Text(sentence)
                                    .font(Tokens.Typography.metadata)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 820, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, Tokens.Space.xs)
                    }
                    .font(Tokens.Typography.metadata)
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
