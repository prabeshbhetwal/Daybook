import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 96

    /// The app comes back up while the screen is still locked. The snapshot
    /// says the absence began at T; nobody has returned, so it must stay open
    /// and the unlock must measure all of it — not the slice up to the launch.
    static func testRestoreBehindLock() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        prefs.longAwayCap = 4 * 3_600
        let clock = TestClock(base)
        let archive = SessionArchive(directory: directory, now: { clock.value })
        let first = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                  schedulesDwell: false, now: { clock.value })
        first.start(workType: .deepWork, intent: "Lock test")
        clock.advance(20 * 60)
        first.transition(on: .awayBegan(trigger: .screenLock))      // T: locked
        let snapshot = first.snapshot()

        // Relaunched 10 minutes later, still locked; unlocked 30 minutes after that.
        clock.advance(10 * 60)
        let relaunched = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
        relaunched.restore(from: snapshot, awayAtLaunch: true)
        expect(relaunched.state == .running, "still running, nothing resolved yet, got \(relaunched.state)", &problems)
        clock.advance(30 * 60)
        relaunched.transition(on: .awayEnded)
        if case .awaitingUserDecision(let away, _) = relaunched.state {
            expectClose(away, 40 * 60, "the unlock measures from the lock, got \(Int(away / 60))m", &problems)
        } else {
            problems.append("the unlock asks about the absence, got \(relaunched.state)")
        }

        // Not locked at launch: the gap since the snapshot is resolved at once, as before.
        clock.advance(5 * 60)
        let unlockedLaunch = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                           schedulesDwell: false, now: { clock.value })
        unlockedLaunch.restore(from: snapshot, awayAtLaunch: false)
        if case .awaitingUserDecision(let away, _) = unlockedLaunch.state {
            expectClose(away, 45 * 60, "an unlocked launch resolves the gap since the lock", &problems)
        } else {
            problems.append("an unlocked launch resolves at once, got \(unlockedLaunch.state)")
        }
        return problems
    }

    // MARK: - 97

    /// The popover's Today band is today's whatever day the dashboard shows:
    /// stepping the dashboard to yesterday must leave the glance segments,
    /// brackets and hover on today. It used to draw the selected day's
    /// segments on today's axis, which emptied the band.
    static func testGlanceStaysOnToday() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return ["calendar"] }
        let usage = AppUsageArchive(directory: directory)
        usage.record(AppUsageSession(bundleID: "com.y", appName: "Y",
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(10 * 3_600)))
        usage.record(AppUsageSession(bundleID: "com.t", appName: "T",
                                     start: today.addingTimeInterval(60),
                                     end: today.addingTimeInterval(3_500)))
        let archive = SessionArchive(directory: directory)
        archive.append(SessionRecord(name: "Y work", workType: .deepWork,
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(10 * 3_600), workSeconds: 3_600))
        archive.append(SessionRecord(name: "T work", workType: .deepWork,
                                     start: today.addingTimeInterval(60),
                                     end: today.addingTimeInterval(3_500), workSeconds: 3_440))
        archive.append(SessionRecord(name: "T overlap", workType: .admin,
                                     start: today.addingTimeInterval(120),
                                     end: today.addingTimeInterval(3_400), workSeconds: 3_280))
        let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                   schedulesDwell: false)
        let store = SessionStore(engine: engine)
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.test", idle: .disabled)
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.refresh()
        expect(store.timelineSegments.map(\.bundleID) == ["com.t"],
               "today's segments on today, got \(store.timelineSegments.map(\.bundleID))", &problems)
        store.stepDay(by: -1)
        expect(store.timelineSegments.map(\.bundleID) == ["com.y"],
               "the dashboard browses yesterday, got \(store.timelineSegments.map(\.bundleID))", &problems)
        expect(store.glanceTimeline.map(\.bundleID) == ["com.t"],
               "the glance band stays on today, got \(store.glanceTimeline.map(\.bundleID))", &problems)
        expect(store.glanceBrackets.count == 1 && store.focusBrackets.count == 1,
               "brackets merge today's overlap for the glance and preserve yesterday's page bracket", &problems)
        store.hoverTimeline(at: 0.5, glance: true)
        expect(store.hoveredSegment?.bundleID == "com.t",
               "hovering the glance band names today's app, got \(store.hoveredSegment?.bundleID ?? "nil")",
               &problems)
        store.hoverTimeline(at: 0.5)
        expect(store.hoveredSegment?.bundleID == "com.y",
               "hovering the page names yesterday's, got \(store.hoveredSegment?.bundleID ?? "nil")", &problems)
        return problems
    }

    // MARK: - 98

    /// Watching is presence, not absence: a Deep work session quietly pauses
    /// behind a film and writes it down as "Watching"; a Meetings session keeps
    /// counting; once the film ends, idle counts from then; a lock mid-film
    /// begins the absence at the lock.
    static func testWatchingIsNotAbsence() -> [String] {
        var problems: [String] = []
        func make(_ type: WorkType) -> (engine: SessionEngine, archive: SessionArchive, clock: TestClock) {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = 4 * 3_600
            prefs.breakThreshold = 5 * 60
            let clock = TestClock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: type, intent: "Watch test")
            clock.advance(20 * 60)                                   // 20m of work, then the film
            return (engine, archive, clock)
        }

        // Deep work: ten quiet minutes behind a film → a quiet pause, back-dated.
        let deep = make(.deepWork)
        deep.clock.advance(10 * 60)
        deep.engine.transition(on: .watchingObserved(seconds: 600))
        expect(deep.engine.state == .paused(reason: .watching),
               "watching pauses deep work quietly, got \(deep.engine.state)", &problems)
        deep.clock.advance(35 * 60)                                  // the film runs on
        deep.engine.transition(on: .watchingObserved(seconds: 45 * 60))
        deep.engine.transition(on: .idleObserved(seconds: 2))        // a keypress
        expect(deep.engine.state == .running, "input resumes without a question, got \(deep.engine.state)",
               &problems)
        expectClose(deep.engine.elapsed, 20 * 60, "the film is not work", &problems)
        let watched = deep.archive.records.last
        expect(watched?.workType == .breakTime && watched?.name == "Watching",
               "a Watching rest is written down, got \(String(describing: watched?.name))", &problems)
        expectClose(watched?.workSeconds ?? 0, 45 * 60, "for the time watched", &problems)

        // Meetings: the same quiet is attendance.
        let meeting = make(.meetings)
        meeting.clock.advance(10 * 60)
        meeting.engine.transition(on: .watchingObserved(seconds: 600))
        expect(meeting.engine.state == .running, "a meeting keeps counting while watched", &problems)
        expectClose(meeting.engine.elapsed, 30 * 60, "and the minutes are kept", &problems)

        // The film ends at T+60 and nobody touches the machine: idle counts
        // from the film's end, and the question on return is about that.
        let left = make(.deepWork)
        left.clock.advance(10 * 60)
        left.engine.transition(on: .watchingObserved(seconds: 600))
        left.clock.advance(42 * 60)                                  // T+72: 12m since the film ended
        left.engine.transition(on: .idleObserved(seconds: 12 * 60))
        expect(left.engine.state == .paused(reason: .idle),
               "after the film, quiet is idle, got \(left.engine.state)", &problems)
        expectClose(left.archive.records.last?.workSeconds ?? 0, 40 * 60,
                    "the Watching rest ends where the film did", &problems)
        left.clock.advance(3 * 60)                                   // T+75
        left.engine.transition(on: .idleObserved(seconds: 1))        // back
        if case .awaitingUserDecision(let away, _) = left.engine.state {
            expectClose(away, 15 * 60, "asked about the 15m after the film, not the film, got \(Int(away / 60))m",
                        &problems)
        } else {
            problems.append("asked about the absence after the film, got \(left.engine.state)")
        }

        // A lock mid-film: the absence begins at the lock.
        let locked = make(.deepWork)
        locked.clock.advance(10 * 60)
        locked.engine.transition(on: .watchingObserved(seconds: 600))
        locked.clock.advance(20 * 60)                                // T+50
        locked.engine.transition(on: .awayBegan(trigger: .screenLock))
        locked.clock.advance(8 * 60)                                 // T+58
        locked.engine.transition(on: .awayEnded)
        if case .awaitingUserDecision(let away, _) = locked.engine.state {
            expectClose(away, 8 * 60, "the question is about the time away, not the film, got \(Int(away / 60))m",
                        &problems)
        } else {
            problems.append("a lock mid-film asks about the lock, got \(locked.engine.state)")
        }
        return problems
    }
}
