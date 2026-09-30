import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 14

    /// The card blocks nothing, so the minutes that pass while it is up are
    /// ordinary working minutes and are credited — except under "Start fresh",
    /// where they belong to the session that starts on return rather than to the
    /// one that ended when the user walked away.
    static func testDecisionAccounting() -> [String] {
        var problems: [String] = []
        let deliberation: TimeInterval = 300
        let away: TimeInterval = 1_320
        let work: TimeInterval = 60

        /// Drives a session to the decision point, waits `deliberation`, answers.
        func engineAfter(_ decision: UserDecision) -> SessionEngine {
            let clock = TestClock(base)
            let engine = makeEngine(clock)
            engine.sessionName = "Refactor"
            engine.transition(on: .launch)
            clock.advance(work)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)
            clock.advance(deliberation)
            engine.transition(on: .decision(decision))
            return engine
        }

        let merged = engineAfter(.mergeTime)
        expectClose(merged.elapsed, work + away + deliberation,
                    "merge counts the away and the time since", &problems)

        let continued = engineAfter(.continueSession)
        expectClose(continued.elapsed, deliberation,
                    "continue starts fresh at the moment of return", &problems)

        let reset = engineAfter(.resetTimer)
        expect(reset.state == .running, "reset should leave a running session", &problems)
        // Not zero: the new session began when they came back, not when they
        // reached for the button.
        expectClose(reset.elapsed, deliberation, "fresh session dates from the return",
                    &problems)
        if let archived = reset.archive.records.last {
            expectClose(archived.workSeconds, work,
                        "archived work excludes both the break and the time since", &problems)
            expect(archived.name == "Refactor", "archived name, got \(archived.name)", &problems)
            // The old session stopped when the user walked away. Stamping it
            // `now()` drew it straight through the gap on the day timeline.
            expectClose(archived.end.timeIntervalSince(archived.start), work + 0,
                        "archived span ends where the away began", &problems)
        } else {
            problems.append("reset should archive the previous session")
        }

        // The manual escape hatch behaves like Continue Session.
        let clock = TestClock(base)
        let escaped = makeEngine(clock)
        escaped.transition(on: .launch)
        clock.advance(work)
        escaped.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(away)
        escaped.transition(on: .awayEnded)
        clock.advance(deliberation)
        escaped.transition(on: .manualResume)
        expect(escaped.state == .running, "manual resume must escape the decision state",
               &problems)
        expectClose(escaped.elapsed, deliberation,
                    "the manual escape behaves like 'I was away': a fresh clock "
                    + "from the moment of return", &problems)
        return problems
    }

    // MARK: - 15

    static func testArchiveQueries() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })

        for minutes in [20.0, 50.0, 20.0] {
            archive.append(SessionRecord(name: "s", workType: .deepWork,
                                         start: clock.value,
                                         end: clock.value.addingTimeInterval(minutes * 60),
                                         workSeconds: minutes * 60))
        }
        expectClose(archive.todayTotal(), 90 * 60, "todayTotal", &problems)
        expect(archive.sessionsToday() == 3,
               "sessionsToday should be 3, got \(archive.sessionsToday())", &problems)
        expectClose(archive.longestToday(), 50 * 60, "longestToday", &problems)

        let bars = archive.weekBars()
        expect(bars.count == 7, "weekBars should have 7 entries, got \(bars.count)", &problems)
        expect(bars.last?.isToday == true, "last bar should be today", &problems)
        expect(bars.last?.minutes == 90,
               "today should be 90 minutes, got \(bars.last?.minutes ?? -1)", &problems)
        expect(bars.dropLast().allSatisfy { $0.minutes == 0 },
               "earlier days should be empty", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 16

    static func testStreakRule() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })
        let day: TimeInterval = 86_400

        func add(daysAgo: Int, minutes: Double) {
            let start = clock.value.addingTimeInterval(-Double(daysAgo) * day)
            archive.append(SessionRecord(name: "s", workType: .deepWork,
                                         start: start,
                                         end: start.addingTimeInterval(minutes * 60),
                                         workSeconds: minutes * 60))
        }

        add(daysAgo: 0, minutes: 30)
        add(daysAgo: 1, minutes: 30)
        add(daysAgo: 2, minutes: 10)   // below the 25m bar — breaks the chain
        add(daysAgo: 3, minutes: 60)
        expect(archive.currentStreak() == 2,
               "streak should be 2, got \(archive.currentStreak())", &problems)

        // A streak ending yesterday still shows today, before today's first session.
        let dir2 = scratchDirectory()
        let archive2 = SessionArchive(directory: dir2, now: { clock.value })
        let yesterday = clock.value.addingTimeInterval(-day)
        archive2.append(SessionRecord(name: "s", workType: .deepWork,
                                      start: yesterday,
                                      end: yesterday.addingTimeInterval(1_800),
                                      workSeconds: 1_800))
        expect(archive2.currentStreak() == 1,
               "yesterday-only streak should be 1, got \(archive2.currentStreak())", &problems)

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir2)
        return problems
    }

    // MARK: - 17

    static func testArchivePersistence() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()

        let first = SessionArchive(directory: dir, now: { clock.value })
        first.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                   start: base, end: base.addingTimeInterval(600),
                                   workSeconds: 600, detectedApp: "com.apple.Terminal"))

        let second = SessionArchive(directory: dir, now: { clock.value })
        expect(second.records.count == 1, "record should survive a reload", &problems)
        expect(second.records.first?.name == "Refactor", "name should survive", &problems)
        expect(second.records.first?.detectedApp == "com.apple.Terminal",
               "detected app should survive", &problems)

        try? Data("not json".utf8).write(to: dir.appendingPathComponent("sessions.json"))
        let third = SessionArchive(directory: dir, now: { clock.value })
        expect(third.records.isEmpty, "corrupt store should start empty", &problems)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        expect(files.contains { $0.hasPrefix("sessions-corrupt-") },
               "corrupt file should be renamed aside, saw \(files)", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    // MARK: - 18

    static func testQuickStarts() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })

        func add(_ name: String, _ type: WorkType, count: Int) {
            for _ in 0..<count {
                archive.append(SessionRecord(name: name, workType: type,
                                             start: clock.value, end: clock.value,
                                             workSeconds: 600))
            }
        }
        add("Refactor", .deepWork, count: 3)
        add("Standup", .meetings, count: 2)
        add("Email", .admin, count: 1)
        // Empty intents never become quick starts.
        add("", .deepWork, count: 5)
        // Anything outside the window is ignored.
        let old = clock.value.addingTimeInterval(-30 * 86_400)
        archive.append(SessionRecord(name: "Ancient", workType: .learning,
                                     start: old, end: old, workSeconds: 600))

        let quick = archive.quickStarts(limit: 7)
        expect(quick.count == 3, "3 distinct pairs, got \(quick.count)", &problems)
        expect(quick.first?.name == "Refactor",
               "most frequent first, got \(quick.first?.name ?? "nil")", &problems)
        expect(quick.first?.workType == .deepWork, "work type should ride along", &problems)
        expect(!quick.contains { $0.name == "Ancient" }, "stale entries excluded", &problems)
        expect(archive.quickStarts(limit: 2).count == 2, "limit respected", &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }
}
