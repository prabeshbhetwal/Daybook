import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 67

    /// "It was a break" costs the session exactly what "I was away" costs it,
    /// and buys a record that explains the gap. The record must never reach the
    /// day's focused total — recording rest in order to have it counted as work
    /// would be worse than not recording it at all.
    static func testRecordedBreak() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 30 * 60
        let away: TimeInterval = 33 * 60

        func engineAfter(_ decision: UserDecision) -> (SessionEngine, Date) {
            let clock = TestClock(base)
            let engine = makeEngine(clock)
            engine.transition(on: .launch)
            clock.advance(work)
            let leftAt = clock.value
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            engine.transition(on: .awayEnded)
            engine.transition(on: .decision(decision))
            return (engine, leftAt)
        }

        let (rested, leftAt) = engineAfter(.tookBreak)
        let (gone, _) = engineAfter(.continueSession)
        expect(rested.state == .running, "a new session is running", &problems)
        expectClose(rested.elapsed, gone.elapsed,
                    "a break costs the session what an absence costs it", &problems)
        expectClose(rested.elapsed, 0,
                    "and both start a fresh clock on return", &problems)

        guard let record = rested.archive.records
            .first(where: { $0.workType == .breakTime }) else {
            problems.append("the break should be written down")
            return problems
        }
        expectClose(record.start.timeIntervalSince(leftAt), 0,
                    "it starts where the user left", &problems)
        expectClose(record.span, away, "and spans the whole absence", &problems)
        expect(record.threadID != rested.activeThreadID,
               "a break is not a segment of the work it interrupts", &problems)

        // The whole point: none of the rest counts as focus. The session that
        // closed does, so the day's total is the work, never the work plus the
        // break.
        expectClose(rested.archive.todayTotal(), work,
                    "the day counts the work and not the rest", &problems)
        expect(rested.archive.sessionsToday() == 1,
               "one focus session archived, not two, got "
               + "\(rested.archive.sessionsToday())", &problems)
        expectClose(rested.archive.longestToday(), work,
                    "the closed session is the longest; the break is not a "
                    + "candidate", &problems)
        expect(rested.archive.records.count == 2,
               "the break and the closed session, got "
               + "\(rested.archive.records.count)", &problems)
        expect(!gone.archive.records.contains { $0.workType == .breakTime },
               "being away records no break", &problems)
        expect(gone.archive.records.count == 1,
               "being away still closes the session it interrupted", &problems)

        // Against a real focus record, the break must be invisible to totals but
        // visible to anything listing the day.
        let clock = TestClock(base)
        let mixed = makeArchive(clock)
        mixed.append(SessionRecord(name: "Work", workType: .deepWork,
                                   start: base, end: base.addingTimeInterval(3_600),
                                   workSeconds: 3_600))
        mixed.append(SessionRecord(name: "Break", workType: .breakTime,
                                   start: base.addingTimeInterval(3_600),
                                   end: base.addingTimeInterval(5_400),
                                   workSeconds: 1_800))
        expectClose(mixed.todayTotal(), 3_600,
                    "the hour of work, not the half hour of rest", &problems)
        expect(mixed.records(on: base).count == 2,
               "both are still listed for the day", &problems)
        expect(mixed.weekBars().last?.minutes == 60,
               "the week chart shows focus only, got "
               + "\(mixed.weekBars().last?.minutes ?? -1)", &problems)
        return problems
    }

    // MARK: - 68

    /// Sitting idle pauses the session backdated to when input actually stopped,
    /// so the ten minutes that prove the user is gone are excluded too. Only an
    /// idle pause auto-resumes: a pause the user pressed is a deliberate act.
    static func testIdleAutoPause() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.transition(on: .launch)
        clock.advance(600)                       // ten minutes of real work

        // Nine minutes idle is tolerated — reading and calls are work.
        clock.advance(540)
        engine.transition(on: .idleObserved(seconds: 540))
        expect(engine.state == .running, "nine minutes idle keeps the session", &problems)
        expectClose(engine.elapsed, 1_140, "and counts", &problems)

        // Past the threshold it pauses, backdated to the last keypress.
        clock.advance(60)
        engine.transition(on: .idleObserved(seconds: 600))
        expect(engine.state == .paused(reason: .idle),
               "ten minutes idle pauses, got \(engine.state)", &problems)
        expectClose(engine.elapsed, 600,
                    "the whole idle stretch is excluded, not just the tail", &problems)

        // Still idle: no further effect, and no time accrues.
        clock.advance(240)
        engine.transition(on: .idleObserved(seconds: 840))
        expectClose(engine.elapsed, 600, "four more minutes away add nothing", &problems)

        // Input resumes it — quietly, because fourteen minutes is under the
        // asking threshold.
        engine.transition(on: .idleObserved(seconds: 0))
        expect(engine.state == .running, "input resumes an idle pause", &problems)
        clock.advance(300)
        expectClose(engine.elapsed, 900, "and the clock runs again", &problems)

        // Past the threshold the absence is asked about, exactly as a locked
        // one is: the idle pause was the app's observation, and the question
        // is the same whether or not the screen happened to lock.
        clock.advance(FocusConstants.idlePauseThreshold)
        engine.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        clock.advance(1_800)
        engine.transition(on: .idleObserved(seconds: 0))
        guard case .awaitingUserDecision(let asked, _) = engine.state else {
            return problems + ["forty idle minutes should raise the card, got \(engine.state)"]
        }
        expectClose(asked, 2_400, "naming the whole absence", &problems)
        engine.transition(on: .decision(.mergeTime))
        expect(engine.state == .running, "'I was working' resumes", &problems)
        expectClose(engine.elapsed, 3_300, "with the absence added back as work", &problems)

        // A pause the user pressed must not be undone by typing.
        let manualClock = TestClock(base)
        let manual = makeEngine(manualClock)
        manual.transition(on: .launch)
        manualClock.advance(60)
        manual.transition(on: .manualPause)
        manual.transition(on: .idleObserved(seconds: 0))
        expect(manual.state == .paused(reason: .manual),
               "input must not undo a deliberate pause, got \(manual.state)", &problems)

        // The reason survives persistence.
        let idleClock = TestClock(base)
        let persisted = makeEngine(idleClock)
        persisted.transition(on: .launch)
        idleClock.advance(1_200)
        persisted.transition(on: .idleObserved(seconds: 700))
        let blob = try? JSONEncoder().encode(persisted.snapshot())
        let reloaded = blob.flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        expect(reloaded?.restoredPauseReason == .idle,
               "an idle pause must survive a save/load cycle", &problems)
        return problems
    }

    // MARK: - 69

    /// The goal counts only seconds that are both inside a declared session and
    /// within reach of real input. Either alone is a lie: wall-clock sessions
    /// counted an untouched machine, and raw hands-on time would let an hour of
    /// messaging fill a focus goal.
    static func testFocusedActiveTime() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }
        func record(_ from: Double, _ to: Double,
                    type: WorkType = .deepWork) -> SessionRecord {
            SessionRecord(name: "S", workType: type, start: at(from), end: at(to),
                          workSeconds: (to - from) * 3_600)
        }
        func used(_ from: Double, _ to: Double) -> AppUsageSession {
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: at(from), end: at(to))
        }
        func seconds(_ records: [SessionRecord], _ usage: [AppUsageSession],
                     running: (start: Date, end: Date)? = nil) -> TimeInterval {
            FocusedActiveTime.seconds(on: day, records: records, usage: usage,
                                      running: running, calendar: calendar)
        }

        expectClose(seconds([record(9, 11)], [used(13, 14)]), 0,
                    "no overlap, nothing counted", &problems)
        expectClose(seconds([record(9, 11)], []), 0,
                    "a session with nobody at the keyboard counts nothing", &problems)
        expectClose(seconds([], [used(9, 11)]), 0,
                    "hands-on outside any session counts nothing", &problems)
        expectClose(seconds([record(9, 11)], [used(10, 12)]), 3_600,
                    "only the overlapping hour", &problems)

        // Two overlapping records must not count one second twice.
        expectClose(seconds([record(9, 11), record(10, 12)], [used(9, 12)]), 3 * 3_600,
                    "overlapping sessions are merged, not summed", &problems)
        // Nor two overlapping usage stretches.
        expectClose(seconds([record(9, 12)], [used(9, 11), used(10, 12)]), 3 * 3_600,
                    "overlapping usage is merged, not summed", &problems)

        // Breaks are not focus, so a break covering hands-on time counts nothing.
        expectClose(seconds([record(9, 11, type: .breakTime)], [used(9, 11)]), 0,
                    "a recorded break cannot fill the goal", &problems)

        // The running session participates.
        expectClose(seconds([], [used(9, 11)], running: (at(10), at(12))), 3_600,
                    "the in-flight session counts its overlap too", &problems)

        // Everything is clipped to the day.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let overnight = SessionRecord(name: "S", workType: .deepWork,
                                      start: yesterday.addingTimeInterval(22 * 3_600),
                                      end: at(2), workSeconds: 4 * 3_600)
        let overnightUse = AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                           start: yesterday.addingTimeInterval(22 * 3_600),
                                           end: at(2))
        expectClose(seconds([overnight], [overnightUse]), 2 * 3_600,
                    "only the hours after midnight belong to today", &problems)
        return problems
    }
}
