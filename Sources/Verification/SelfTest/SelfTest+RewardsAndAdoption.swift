import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Reward engine: gating rules must skip fabricated comparisons and never nag.
    static func testRewardEngine() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)

        func neutralGoal(goal: TimeInterval = 4 * 3_600, achieved: TimeInterval = 0,
                         typicalByNow: TimeInterval? = nil) -> GoalProgress {
            GoalProgress(goal: goal, achieved: achieved, typical: typicalByNow)
        }

        func neutralContext(focusedToday: TimeInterval = 0,
                            sameWeekdayLastWeek: TimeInterval? = nil,
                            streak: Int = 0, bestStreak: Int = 0,
                            goal: GoalProgress = neutralGoal(),
                            endedMedia: (appName: String, seconds: TimeInterval)? = nil,
                            musicPairing: TimeInterval? = nil,
                            isSessionRunning: Bool = false) -> RewardContext {
            RewardContext(focusedToday: focusedToday, sameWeekdayLastWeek: sameWeekdayLastWeek,
                         streak: streak, bestStreak: bestStreak, goal: goal,
                         endedMedia: endedMedia, musicPairing: musicPairing,
                         isSessionRunning: isSessionRunning)
        }

        // No streakRecord when the streak merely equals the best.
        let tiedStreak = neutralContext(streak: 3, bestStreak: 3)
        let tiedEngine = RewardEngine(log: [:], now: { clock.value })
        expect(tiedEngine.next(for: tiedStreak) == nil,
               "a tied streak must not fire a record", &problems)

        // No goalPace when aheadBy is nil, even though achieved looks generous.
        let noAheadGoal = neutralGoal(achieved: 3_000, typicalByNow: nil)
        let noAheadContext = neutralContext(goal: noAheadGoal)
        let noAheadEngine = RewardEngine(log: [:], now: { clock.value })
        expect(noAheadEngine.next(for: noAheadContext) == nil,
               "goalPace must not fire without a real aheadBy figure", &problems)

        // Milestone: comparison omitted when there is no same-weekday figure...
        let milestoneNoCompare = neutralContext(focusedToday: 3_700, isSessionRunning: true)
        let milestoneEngine = RewardEngine(log: [:], now: { clock.value })
        if let reward = milestoneEngine.next(for: milestoneNoCompare) {
            expect(reward.kind == .milestone, "expected a milestone reward, got \(reward.kind)",
                   &problems)
            expect(!reward.detail.contains("last week"),
                   "detail must not claim a comparison it has no data for: \(reward.detail)",
                   &problems)
        } else {
            problems.append("an hour of running focus should fire a milestone")
        }

        // ...and included when it is present.
        let milestoneCompare = neutralContext(focusedToday: 3_700, sameWeekdayLastWeek: 2_000,
                                              isSessionRunning: true)
        let milestoneCompareEngine = RewardEngine(log: [:], now: { clock.value })
        if let reward = milestoneCompareEngine.next(for: milestoneCompare) {
            expect(reward.detail.contains("last week"),
                   "detail should carry the comparison once real data exists: \(reward.detail)",
                   &problems)
        } else {
            problems.append("an hour of running focus with a comparison should fire a milestone")
        }

        // A media stretch under the ten-minute floor produces nothing.
        let shortMedia = neutralContext(endedMedia: (appName: "Trailer", seconds: 300))
        let shortMediaEngine = RewardEngine(log: [:], now: { clock.value })
        expect(shortMediaEngine.next(for: shortMedia) == nil,
               "a sub-ten-minute media stretch must not fire", &problems)

        // A media stretch at or above the floor does.
        let longMedia = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let longMediaEngine = RewardEngine(log: [:], now: { clock.value })
        expect(longMediaEngine.next(for: longMedia)?.kind == .mediaEnded,
               "a ten-minute-plus media stretch should fire mediaEnded", &problems)

        // Fixed times comfortably inside one calendar day, away from midnight,
        // so calendar.isDate(inSameDayAs:) checks are never accidentally tripped
        // by timezone edge effects.
        let refDay = Calendar.current.startOfDay(for: base).addingTimeInterval(14 * 3_600)

        // Per-day cap: once the log already has rewardsPerDay entries today,
        // nothing more fires even for an otherwise-eligible candidate.
        var fullLog: [String: Date] = [:]
        for (index, kind) in [RewardKind.goalReached, .streakRecord, .milestone, .goalPace]
            .enumerated() {
            fullLog[kind.rawValue] = refDay.addingTimeInterval(-Double(index + 1) * 3_600)
        }
        let cappedContext = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let cappedEngine = RewardEngine(log: fullLog, now: { refDay })
        expect(cappedEngine.next(for: cappedContext) == nil,
               "the daily cap must block a fifth reward even with a fresh candidate",
               &problems)

        // Same-kind-once-per-day: a kind that already fired today must not fire
        // again today, even with nothing else competing for the slot.
        let sameKindLog: [String: Date] = [RewardKind.mediaEnded.rawValue:
                                           refDay.addingTimeInterval(-4 * 3_600)]
        let sameKindContext = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let sameKindEngine = RewardEngine(log: sameKindLog, now: { refDay })
        expect(sameKindEngine.next(for: sameKindContext) == nil,
               "mediaEnded must not fire twice in the same day", &problems)

        // Cooldown: a log rebuilt from persisted values (as after a relaunch)
        // with its most recent entry inside the cooldown window blocks the next
        // reward, whatever kind it is.
        let cooldownLog: [String: Date] = [RewardKind.workWithMusic.rawValue:
                                           refDay.addingTimeInterval(-10 * 60)]
        let cooldownContext = neutralContext(endedMedia: (appName: "A Film", seconds: 900))
        let cooldownEngine = RewardEngine(log: cooldownLog, now: { refDay })
        expect(cooldownEngine.next(for: cooldownContext) == nil,
               "a reward inside the cooldown window must block the next one", &problems)

        // Outside the cooldown window, the same setup fires normally.
        let clearLog: [String: Date] = [RewardKind.workWithMusic.rawValue:
                                        refDay.addingTimeInterval(-FocusConstants.rewardCooldown - 60)]
        let clearEngine = RewardEngine(log: clearLog, now: { refDay })
        expect(clearEngine.next(for: cooldownContext)?.kind == .mediaEnded,
               "once outside the cooldown, a new reward should fire", &problems)

        return problems
    }

    // MARK: - 57

    /// Regression for the worst defect the final review found: a qualifying run
    /// begun before the user pressed Start survived the whole manual session and
    /// fired the instant it ended, backdated across work already archived —
    /// double-counting hours into the day's total.
    static func testNoStaleQualifyingRun() -> [String] {
        var problems: [String] = []
        var detector = AutoSessionDetector(breakLength: 600)
        let high = makeFocusScore(0.8, purpose: .coding, explanation: "Warp 5m")
        let t0 = base

        // Working, but not yet long enough to auto-start.
        _ = detector.evaluate(score: high, at: t0, sessionRunning: false,
                              sessionWasAutoStarted: false, enginePaused: false)

        // The user presses Start by hand and works for two hours.
        for minutes in stride(from: 3, through: 120, by: 15) {
            let decision = detector.evaluate(score: high,
                                             at: t0.addingTimeInterval(Double(minutes) * 60),
                                             sessionRunning: true,
                                             sessionWasAutoStarted: false,
                                             enginePaused: false)
            expect(decision == .none, "a hand-started session is never touched", &problems)
        }

        // They stop. The very next evaluation must not fire instantly.
        let afterStop = detector.evaluate(score: high, at: t0.addingTimeInterval(121 * 60),
                                          sessionRunning: false,
                                          sessionWasAutoStarted: false, enginePaused: false)
        expect(afterStop == .none,
               "the first evaluation after a manual session must not auto-start, got "
               + "\(afterStop)", &problems)

        // It must serve a fresh dwell, and backdate no further than that.
        let restart = t0.addingTimeInterval(121 * 60)
        let tooSoon = detector.evaluate(score: high, at: restart.addingTimeInterval(240),
                                        sessionRunning: false,
                                        sessionWasAutoStarted: false, enginePaused: false)
        expect(tooSoon == .none, "the new run must serve the full dwell", &problems)
        let fired = detector.evaluate(score: high,
                                      at: restart.addingTimeInterval(FocusConstants.autoStartDwell),
                                      sessionRunning: false,
                                      sessionWasAutoStarted: false, enginePaused: false)
        if case .start(_, _, let backdatedTo, _) = fired {
            expect(backdatedTo >= restart,
                   "backdating must not reach behind the manual session", &problems)
        } else {
            problems.append("expected a start after a fresh dwell, got \(fired)")
        }

        // And an undone session cannot immediately return.
        detector.suppressStarts(until: restart.addingTimeInterval(3_600))
        let suppressed = detector.evaluate(score: high,
                                           at: restart.addingTimeInterval(1_800),
                                           sessionRunning: false,
                                           sessionWasAutoStarted: false, enginePaused: false)
        expect(suppressed == .none, "a rejected session stays rejected", &problems)

        return problems
    }

    // MARK: - 58

    static func testAdoptAndSystemProcesses() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        // An automatic session is running.
        engine.start(workType: .deepWork, intent: "", isAuto: true)
        let thread = engine.activeThreadID
        clock.value = base.addingTimeInterval(1_800)

        // Pressing Start on the same kind of work continues it: same session,
        // same thread, clock untouched, nothing archived.
        expect(engine.wouldAdopt(workType: .deepWork), "same work type adopts", &problems)
        engine.adopt(intent: "Refactor the parser")
        expectClose(engine.elapsed, 1_800, "adopting does not reset the clock", &problems)
        expect(engine.archive.records.isEmpty, "adopting archives nothing", &problems)
        expect(engine.activeThreadID == thread, "the thread survives", &problems)
        expect(engine.sessionName == "Refactor the parser", "the intent is taken", &problems)
        expect(!engine.activeIsAuto,
               "a claimed session is the user's, so the app may not end it", &problems)

        // A different work type is different work: that starts a new session.
        expect(!engine.wouldAdopt(workType: .meetings),
               "a different work type does not adopt", &problems)
        engine.start(workType: .meetings, intent: "Standup")
        expect(engine.archive.records.count == 1,
               "starting different work archives the previous session", &problems)
        expect(engine.activeThreadID != thread, "and begins a new thread", &problems)

        // The lock screen is never app usage, however long it is frontmost.
        let usageDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.value = base.addingTimeInterval(3_600)
        tracker.appActivated(bundleID: "com.apple.loginwindow", name: "loginwindow")
        clock.value = base.addingTimeInterval(3_600 + 6 * 3_600)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        tracker.flush()

        expect(!usage.sessions.contains { $0.bundleID == "com.apple.loginwindow" },
               "six hours at the lock screen is not six hours of app usage", &problems)
        expect(usage.sessions.contains { $0.bundleID == "com.apple.dt.Xcode" },
               "real usage either side of it survives", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }
}
