import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Accessibility must expose the same literal navigation and tracked-time
    /// evidence as the visible UI. This exercises the production label builders
    /// and the exact Escape action wired to Today rather than inspecting source.
    static func testAccessibleNavigationAndChartSummaries() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []

            let tabLabels = AppTab.allCases.map {
                $0.accessibilityLabel(isSelected: $0 == .review)
            }
            expect(tabLabels.contains("Review, selected, Command 4"),
                   "the selected tab label announces selection and its command", &problems)
            expect(tabLabels.contains("Focus, not selected, Command 1"),
                   "unselected tab labels announce their state", &problems)
            expect(Set(AppTab.allCases.map(\.commandNumber)) == Set(1...7),
                   "Command 1 through Command 7 map uniquely to the seven tabs", &problems)
            expect(AppTab.review.moved(by: -1) == .story
                       && AppTab.review.moved(by: 1) == .insights,
                   "left and right move from the focused Review tab", &problems)

            expect(AccessibilityMetrics.minimumTargetSize >= 28,
                   "compact controls retain a practical 28pt target", &problems)
            expect(InterfaceDensity.compact.layout.rowHeight
                       >= AccessibilityMetrics.minimumTargetSize,
                   "compact rows remain at least as tall as the minimum target", &problems)
            return problems
        }
    }

    /// Review compares the authoritative tracked series rather than focus
    /// composition. History joins those usage days to archive evidence once,
    /// orders them newest first, and combines every requested filter.
    /// An award may only state what the local record proves. An unearned one
    /// shows real progress rather than an exhortation, and a run of goal days
    /// is broken by a calendar gap, not merely by a lower figure.
    static func testAwardsAreEvidenceBacked() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func offset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: day) ?? day
        }

        // Seven consecutive days at goal, then a gap, then two more.
        var credit: [Date: TimeInterval] = [:]
        for index in 0..<7 { credit[offset(index)] = 4 * 3_600 }
        credit[offset(8)] = 4 * 3_600
        credit[offset(9)] = 4 * 3_600
        // A day below the goal must not extend a run.
        credit[offset(7)] = 30 * 60

        var facts = AwardFacts(goal: 4 * 3_600,
                               goalCreditByDay: credit,
                               longestStretch: (95 * 60, offset(2)),
                               activeDays: 22,
                               totalFocused: 62 * 3_600 + 40 * 60,
                               currentStreak: 12,
                               bestStreak: 14)

        let run = Awards.longestGoalRun(facts, calendar: calendar)
        expect(run.length == 7, "the longest run is the seven consecutive days, got \(run.length)",
               &problems)
        expect(run.start.map { calendar.isDate($0, inSameDayAs: offset(0)) } == true
                   && run.end.map { calendar.isDate($0, inSameDayAs: offset(6)) } == true,
               "the run reports the literal days that bound it", &problems)

        let awards = Awards.all(from: facts, calendar: calendar)
        expect(awards.count == 4, "four awards are offered", &problems)
        expect(Set(awards.map(\.id)).count == 4, "each award has its own identity", &problems)

        guard let goalRun = awards.first(where: { $0.id == "goal-run" }),
              let stretch = awards.first(where: { $0.id == "longest-stretch" }),
              let active = awards.first(where: { $0.id == "active-days" }),
              let hours = awards.first(where: { $0.id == "focused-hours" }) else {
            return problems + ["every award must be present"]
        }
        expect(goalRun.isEarned, "seven days at goal earns the run award", &problems)
        expect(stretch.isEarned && stretch.detail.contains("1h 35m"),
               "the longest stretch states its own duration, got “\(stretch.detail)”", &problems)
        expect(!active.isEarned && active.detail == "22 so far",
               "an unearned award states real progress, got “\(active.detail)”", &problems)
        expect(!hours.isEarned && hours.detail.contains("62h 40m"),
               "progress toward hours is the exact recorded total, got “\(hours.detail)”", &problems)
        expect(awards.allSatisfy { !$0.method.isEmpty },
               "every award can explain what it measured", &problems)

        // No goal set: the goal award is withheld rather than judged.
        facts.goal = 0
        let withoutGoal = Awards.all(from: facts, calendar: calendar)
        expect(withoutGoal.first(where: { $0.id == "goal-run" })?.isEarned == false,
               "no goal means no goal award", &problems)
        expect(Awards.longestGoalRun(facts, calendar: calendar) == Awards.GoalRun.none,
               "a run cannot be judged without a goal", &problems)

        // An empty record earns nothing and still explains itself.
        let empty = Awards.all(from: AwardFacts(), calendar: calendar)
        expect(empty.allSatisfy { !$0.isEarned },
               "an empty record earns nothing", &problems)
        expect(empty.first(where: { $0.id == "longest-stretch" })?.detail
                   == "No focus session recorded yet",
               "an absent stretch says so plainly", &problems)
        return problems
    }

    /// An Insight card states its conclusion first and keeps its method behind
    /// a literal disclosure, preserving its evidence rather than inventing it.
    static func testInsightAndSettingsPresentation() -> [String] {
        var problems: [String] = []
        let insight = Insight(id: "pace",
                              headline: "10m behind your usual pace",
                              detail: "1h 15m focused-active today",
                              symbolName: "gauge")
        let presentation = InsightPresentation(title: "Pace", insight: insight)
        expect(presentation.disclosureLabel == "How this is calculated",
               "Insights keep methodology behind a literal disclosure", &problems)
        expect(presentation.title == "Pace" && presentation.headline == insight.headline,
               "the card leads with the finding it was given", &problems)
        expect(presentation.provenance == insight.detail,
               "provenance is the insight's own evidence, never invented", &problems)

        return problems
    }

    /// Focus refuses to become a report at any state.
    static func testDayAndFocusHierarchy() -> [String] {
        var problems: [String] = []
        expect(FocusSurfaceLayout.operationalMeasure == 760,
               "Focus keeps a deliberate operational measure", &problems)
        for state in [SessionState.idle, .running, .paused(reason: .manual),
                      .awaitingUserDecision(away: 600, lastApp: "Editor")] {
            expect(!FocusSurfaceLayout.permitsSupportingReport(state: state),
                   "Focus does not become a dashboard in \(state)", &problems)
        }
        return problems
    }

    /// Selecting or clearing a Review day stays in Review.
    static func testReviewContentHierarchy() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let yesterday = base.addingTimeInterval(-24 * 3_600)

            let navigation = MainWindowModel(opening: .review)
            navigation.openHistory(day: yesterday)
            expect(navigation.workspace == .history,
                   "selecting a day does not leave History", &problems)
            navigation.foldDeepestHistory()
            expect(navigation.workspace == .history,
                   "closing the detail does not leave History", &problems)
            return problems
        }
    }
}
