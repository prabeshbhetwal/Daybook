import Foundation

/// A limit on an activity (communication, research, media, utility): only an
/// unfocused purpose can be limited, it counts the whole day's app totals by
/// purpose, a browser only with a purpose the person set, and it is kept or
/// broken like an app limit.
enum ActivityLimitChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Only an unfocused activity can be limited; a focused one stays a target",
         onlyUnfocusedLimits),
        ("An activity limit counts each app's day under its purpose, a browser only with a purpose set",
         countsByPurpose),
        ("An activity limit is kept at or under its amount and broken past it",
         keptOrBroken),
    ]

    private static func onlyUnfocusedLimits() -> [String] {
        var problems: [String] = []
        for purpose in AppPurpose.allCases {
            let expected: DailyGoalKind = purpose.isFocused ? .target : .limit
            let kind = DailyGoalTarget.activity(purpose.rawValue).requiredKind
            if kind != expected { problems.append("\(purpose.rawValue) needs \(String(describing: kind))") }
        }
        if DailyGoalTarget.activity("Gaming").requiredKind != .target {
            problems.append("a kept label (not a purpose) is no longer a target")
        }
        let media = DailyGoalItem(target: .activity("media"), kind: .limit, seconds: 3_600)
        let coding = DailyGoalItem(target: .activity("coding"), kind: .limit, seconds: 3_600)
        if DailyGoalList.activityLimits([media, coding]).map(\.purpose) != [.media] {
            problems.append("a coding limit was listed, or the media limit was not")
        }
        if !DailyGoalList.canAdd(media, to: []) || DailyGoalList.canAdd(coding, to: []) {
            problems.append("the editor may add a coding limit, or may not add a media limit")
        }
        return problems
    }

    private static func countsByPurpose() -> [String] {
        var problems: [String] = []
        let apps: [(bundleID: String, total: TimeInterval)] = [
            ("com.apple.Music", 1_800), ("com.netflix.Netflix", 1_200),
            ("com.tinyspeck.slackmacgap", 600), ("com.apple.dt.Xcode", 3_600),
            ("com.apple.Safari", 5_400),
        ]
        let unset = DailyGoalList.purposeUse(apps: apps, overrides: [:])
        if unset["media"] != 3_000 { problems.append("media read \(unset["media"] ?? 0), expected 3000") }
        if unset["communication"] != 600 { problems.append("communication read \(unset["communication"] ?? 0)") }
        if unset.values.reduce(0, +) != 3_000 + 600 + 3_600 {
            problems.append("a browser with no purpose set was counted: \(unset)")
        }
        let set = DailyGoalList.purposeUse(apps: apps, overrides: ["com.apple.Safari": "media"])
        if set["media"] != 8_400 { problems.append("a browser set to media did not count: \(set["media"] ?? 0)") }
        return problems
    }

    private static func keptOrBroken() -> [String] {
        var problems: [String] = []
        let limit = DailyGoalItem(target: .activity("media"), kind: .limit, seconds: 3_600)
        let appUse = ["com.apple.Music": TimeInterval(3_630)]
        let edge = GoalDayResults.close(goals: [limit], credit: [:], appUse: appUse,
                                        purposeUse: ["media": 3_630]) ?? []
        if edge.first?.met != true || edge.first?.counted != 3_630 {
            problems.append("30 seconds past the limit, printed as the same minute, was not kept")
        }
        let over = GoalDayResults.close(goals: [limit], credit: [:], appUse: appUse,
                                        purposeUse: ["media": 3_700]) ?? []
        if over.first?.met != false { problems.append("a minute over the limit was kept") }
        let none = GoalDayResults.close(goals: [limit], credit: [:], appUse: appUse, purposeUse: [:]) ?? []
        if none.first?.met != true || none.first?.counted != 0 {
            problems.append("a day with no media was not kept")
        }
        // A day only in a browser with no purpose set says nothing about media: not judged.
        let browser = ["com.apple.Safari": TimeInterval(5 * 3_600)]
        if GoalDayResults.close(goals: [limit], credit: [:], appUse: browser, purposeUse: [:],
                                unreadUse: 5 * 3_600) != nil {
            problems.append("a browser-only day judged the media limit")
        }
        // Kept even were all 20 unread minutes media; over is over whatever was unread.
        let small = GoalDayResults.close(goals: [limit], credit: [:], appUse: appUse,
                                         purposeUse: ["media": 1_800], unreadUse: 1_200) ?? []
        if small.first?.met != true { problems.append("a limit that holds with every unread minute was not kept") }
        let broken = GoalDayResults.close(goals: [limit], credit: [:], appUse: appUse,
                                          purposeUse: ["media": 3_700], unreadUse: 5 * 3_600) ?? []
        if broken.first?.met != false { problems.append("a limit already over was not broken beside unread time") }
        let unread = DailyGoalList.unreadUse(apps: [("com.apple.Safari", 600), ("com.apple.Music", 900)], overrides: [:])
        if unread != 600 { problems.append("unread use read \(unread), expected the browser's 600") }
        return problems
    }
}
