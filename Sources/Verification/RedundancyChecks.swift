import Foundation

/// Each fact is said once where the reader sees it. These break if a figure or
/// sentence that already has a home on the page is written a second time.
enum RedundancyChecks {
    static let tests: [(String, () -> [String])] = [
        ("How this day was measured explains the measures instead of repeating figures", measuredExplains),
        ("A session's prose leaves the leading app to the app list beside it", proseLeavesTopApp),
        ("A session's caption adds only what its figures do not show", captionsAddOnly),
        ("An unnamed break is not called a break twice", breakNamedOnce),
        ("The best two hours are said once, with where they fell", bestHoursSaidOnce),
        ("History's month carries recorded app use in its rail, not its header", monthAppUseOnce),
        ("A break reminder's body gives the reason, not the title again", breakBodyAddsOnly),
        ("The strip hides today's goal only where the goal card shows it", stripGoalOnlyWhereCardIsNot)
    ]

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func segment(_ name: String, _ from: TimeInterval, _ to: TimeInterval) -> TimelineSegment {
        TimelineSegment(id: UUID(), bundleID: "test." + name.lowercased(), appName: name,
                        start: start.addingTimeInterval(from), end: start.addingTimeInterval(to),
                        colorIndex: 0)
    }

    private static func measuredExplains() -> [String] {
        let session = DaySession(id: UUID(), threadID: UUID(), name: "Parser", workType: .deepWork,
                                 start: start, end: start.addingTimeInterval(3_600), worked: 3_000,
                                 stretches: 3, spans: [], isRunning: false)
        let apps = [AppRank(bundleID: "test.xcode", appName: "Xcode", total: 3_000, share: 1, longest: 1_800)]
        let lunch = RestEntry(id: UUID(), name: "Lunch", start: start.addingTimeInterval(3_600),
                              end: start.addingTimeInterval(5_400))
        let facts = SessionStore.storyDaySummaryFacts(entries: [.session(session), .rest(lunch)], apps: apps)
        let text = facts.joined(separator: " ")
        var failures: [String] = []
        if text.contains("Xcode") { failures.append("the busiest app was repeated: \(text)") }
        if text.contains("50m") || text.contains("qualified") {
            failures.append("a figure already on the page was repeated: \(text)")
        }
        if !text.contains("3 separate stretches") { failures.append("the stretch count was lost: \(text)") }
        if !text.contains("Recorded break: Lunch") { failures.append("the break's name was lost: \(text)") }
        if !text.contains("pauses") || !text.contains("never counted as focus") {
            failures.append("the measures were not explained: \(text)")
        }
        let unnamed = RestEntry(id: UUID(), name: "Break", start: start, end: start.addingTimeInterval(600))
        if SessionStore.storyDaySummaryFacts(entries: [.rest(unnamed)], apps: [])
            != ["Recorded breaks are rest; they are never counted as focus."] {
            failures.append("an unnamed break was not explained as rest")
        }
        return failures
    }

    private static func proseLeavesTopApp() -> [String] {
        let segments = [segment("Xcode", 0, 1_200), segment("Safari", 1_200, 1_500),
                        segment("Xcode", 1_500, 1_800)]
        let activity = RecordedActivity(segments: segments,
                                        spans: [DateInterval(start: start, duration: 1_800)])
        let prose = SessionShape.storyProse(.init(segments: segments, activity: activity,
                                                  workType: .deepWork, stretches: 1, worked: 1_800)) ?? ""
        var failures: [String] = []
        if prose.contains("predominant") { failures.append("the leading app was named again: \(prose)") }
        if !prose.contains("moved between apps") { failures.append("the switch count was lost: \(prose)") }
        return failures
    }

    private static func captionsAddOnly() -> [String] {
        var failures: [String] = []
        let covered = SessionStore.sessionEvidenceNotes(coverage: 2_100, elapsed: 2_580, gap: 480,
                                                        isRunning: false, isTrackingEnabled: true,
                                                        conflicting: false)
        if covered.card != "Recorded app use: 35m across 43m elapsed. 8m of the session span has no app recording." {
            failures.append("the card caption repeats its clock or lost coverage: \(covered.card ?? "nil")")
        }
        if covered.report != "8m of the session span has no app recording." {
            failures.append("the report note repeats its figures: \(covered.report ?? "nil")")
        }
        let runningOff = SessionStore.sessionEvidenceNotes(coverage: 0, elapsed: 600, gap: 600,
                                                           isRunning: true, isTrackingEnabled: false,
                                                           conflicting: false)
        if runningOff.card != nil {
            failures.append("the card repeats the recording-off banner: \(runningOff.card ?? "")")
        }
        if runningOff.report?.contains("App recording is off") != true {
            failures.append("the report, which has no banner, lost the recording-off note")
        }
        let unrecorded = SessionStore.sessionEvidenceNotes(coverage: 0, elapsed: 600, gap: 600,
                                                           isRunning: false, isTrackingEnabled: true,
                                                           conflicting: true)
        if unrecorded.card?.contains("Logged focus") != false
            || unrecorded.card?.contains("Overlapping source app records") != true
            || unrecorded.card != unrecorded.report {
            failures.append("an unrecorded session's notes were wrong: \(unrecorded)")
        }
        return failures
    }

    private static func breakNamedOnce() -> [String] {
        var failures: [String] = []
        if RestEntryRow.label("Break") != "Recorded break, not counted as focus"
            || RestEntryRow.label("") != "Recorded break, not counted as focus" {
            failures.append("an unnamed break read as \(RestEntryRow.label("Break"))")
        }
        if RestEntryRow.label("Lunch") != "Lunch — recorded break, not counted as focus" {
            failures.append("a named break lost its name: \(RestEntryRow.label("Lunch"))")
        }
        return failures
    }

    private static func bestHoursSaidOnce() -> [String] {
        let note = HistoryHours.note(seconds: 12_000, phrase: "on Tuesdays")
        return note == "\(Tokens.duration(12_000)) of focus fell here, most of it on Tuesdays."
            ? [] : ["the best-hours note lost its figure or place: \(note)"]
    }

    private static func stripGoalOnlyWhereCardIsNot() -> [String] {
        var failures: [String] = []
        if SessionControlStrip.showsGoal(isToday: true, workspace: .story, sheet: nil) {
            failures.append("the strip repeated today's goal beside the goal card")
        }
        if !SessionControlStrip.showsGoal(isToday: true, workspace: .history, sheet: nil) {
            failures.append("History has no goal card, yet the strip hid today's goal there")
        }
        if !SessionControlStrip.showsGoal(isToday: true, workspace: .story, sheet: .settings) {
            failures.append("a sheet covers the goal card, yet the strip hid today's goal")
        }
        if !SessionControlStrip.showsGoal(isToday: false, workspace: .story, sheet: nil) {
            failures.append("a past day's card is not today's goal, yet the strip hid it")
        }
        return failures
    }

    private static func breakBodyAddsOnly() -> [String] {
        var failures: [String] = []
        for tier in BreakTier.allCases {
            let prompt = BreakPrompt(tier: tier, worked: 20 * 60, appName: nil)
            let body = prompt.body.lowercased()
            if ["look away", "five-minute", "step away", "take 5"].contains(where: body.contains) {
                failures.append("\(tier) repeats its title \"\(prompt.title)\": \(prompt.body)")
            }
            if !prompt.body.hasPrefix("You have been at the Mac for 20m") && tier != .ultradian {
                failures.append("\(tier) lost how long you have worked: \(prompt.body)")
            }
        }
        return failures
    }

    private static func monthAppUseOnce() -> [String] {
        let month = JournalMonth(start: Date(timeIntervalSince1970: 1_800_000_000), focused: 3_600,
                                 tracked: 7_200, focusedDays: 1, dailyFocus: [3_600])
        var failures: [String] = []
        let monthRow = HistoryRow(place: HistoryPlace(level: .month, span: DateInterval(start: month.start, duration: 86_400 * 30)),
                                  focused: month.focused, tracked: month.tracked, focusedDays: month.focusedDays,
                                  sessions: 3, mainWorkType: .deepWork, hasEvidence: true, bars: [])
        if HistoryRowText.facts(monthRow, today: Date()).contains("app use") {
            failures.append("the month header repeated recorded app use")
        }
        if HistoryPeriodRail.appUseLine(tracked: month.tracked) != "\(Tokens.duration(7_200)) recorded app use" {
            failures.append("the month rail lost recorded app use")
        }
        return failures
    }
}
