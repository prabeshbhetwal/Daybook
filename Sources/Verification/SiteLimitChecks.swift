import Foundation

/// A limit on a kind of site: named by its kind, shown as not available, and
/// never judged, so it can neither keep nor break a day.
enum SiteLimitChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A site limit is named by its kind and listed for the card as not available",
         namedAndListed),
        ("A site limit is never judged, so a day is perfect or not on its other goals",
         neverJudged),
    ]

    private static func namedAndListed() -> [String] {
        var problems: [String] = []
        let video = DailyGoalItem(target: .site("video"), kind: .limit, seconds: 2 * 3_600)
        let newer = DailyGoalItem(target: .site("podcast"), kind: .limit, seconds: 3_600)
        let paused = DailyGoalItem(target: .site("social"), kind: .limit, seconds: 3_600, isPaused: true)
        let wrongKind = DailyGoalItem(target: .site("shopping"), kind: .target, seconds: 3_600)
        let listed = DailyGoalList.siteLimits([video, newer, paused, wrongKind])
        if listed.map(\.name) != ["Video sites", "podcast"] {
            problems.append("listed \(listed.map(\.name)), expected Video sites then podcast")
        }
        if listed.first?.id != video.id || listed.first?.limit != 2 * 3_600 {
            problems.append("the video limit lost its id or amount")
        }
        if DailyGoalList.siteLimitUnavailable != "Not available yet" {
            problems.append("the card reads \(DailyGoalList.siteLimitUnavailable)")
        }
        return problems
    }

    private static func neverJudged() -> [String] {
        var problems: [String] = []
        let site = DailyGoalItem(target: .site("video"), kind: .limit, seconds: 60)
        let focus = DailyGoalItem(target: .category(WorkType.deepWork.rawValue), kind: .target, seconds: 3_600)
        let credit = [WorkType.deepWork.rawValue: TimeInterval(2 * 3_600)]
        let appUse = ["com.example.browser": TimeInterval(5 * 3_600)]
        let results = GoalDayResults.close(goals: [site, focus], credit: credit, appUse: appUse) ?? []
        if results.contains(where: { $0.target == site.target }) { problems.append("the site limit was judged") }
        if !GoalDayResults.isPerfect(results) { problems.append("a met target with a site limit was not perfect") }
        if GoalDayResults.close(goals: [site], credit: credit, appUse: appUse) != nil {
            problems.append("a day with only a site limit was recorded")
        }
        return problems
    }
}
