import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 62

    static func testManualAway() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.transition(on: .launch)
        clock.advance(300)
        engine.transition(on: .markedAway)
        expect(engine.state == .paused(reason: .away),
               "marking away should pause with an away reason, got \(engine.state)", &problems)

        clock.advance(1_800)
        // Saying it twice must not restart the pause clock and hand back the
        // half hour already spent away as work.
        engine.transition(on: .markedAway)
        clock.advance(600)
        let thread = engine.activeThreadID
        engine.transition(on: .manualResume)
        // Forty minutes away is a break, and a break ends a stretch: the work
        // before it is archived where they left, the gap is written down as
        // Away, and a new stretch begins now on the same thread.
        expect(engine.state == .running, "coming back resumes", &problems)
        expectClose(engine.elapsed, 0, "a new stretch, clock from zero", &problems)
        expect(engine.activeThreadID == thread, "on the same thread", &problems)
        let records = engine.archive.records.suffix(2)
        let away = records.first { $0.workType == .breakTime }
        let stretch = records.first { $0.workType != .breakTime }
        expectClose(away?.workSeconds ?? 0, 2_400, "the whole away is written down as one break", &problems)
        expect(away?.name == "Away", "named Away, got \(away?.name ?? "nil")", &problems)
        expectClose(stretch?.workSeconds ?? 0, 300, "the stretch carries only the work before it", &problems)
        expectClose(stretch?.end.timeIntervalSince(base) ?? 0, 300, "and ends where they left", &problems)

        // A short away stays a pause inside the stretch.
        let short = makeEngine(TestClock(base))
        short.breakThreshold = 5 * 60
        short.transition(on: .launch)
        short.transition(on: .markedAway)
        let shortClock = TestClock(base)
        _ = shortClock
        short.transition(on: .manualResume)
        expect(short.state == .running && short.archive.records.isEmpty,
               "a short away resumes the same stretch, nothing written", &problems)

        // The reason survives a save/load cycle, or the menu bar forgets.
        let reloaded = try? JSONDecoder().decode(
            PersistedState.self,
            from: JSONEncoder().encode(makeAwayEngine().snapshot()))
        expect(reloaded?.restoredPauseReason == .away,
               "an away pause must survive persistence", &problems)
        return problems
    }

    static func makeAwayEngine() -> SessionEngine {
        let engine = makeEngine(TestClock(base))
        engine.transition(on: .launch)
        engine.transition(on: .markedAway)
        return engine
    }

    // MARK: - 64

    /// The defect behind almost every wrong figure in the app: a record was
    /// filed under the day it *ended*, so a session begun on Friday and stopped
    /// on Sunday made Friday read as a day with no focus at all — blanking its
    /// bar, breaking the streak through it, and dropping it from the "usual
    /// pace" median as an inactive day.
    static func testDayAttribution() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day2 = calendar.startOfDay(for: base)
        guard let day1 = calendar.date(byAdding: .day, value: -1, to: day2),
              let day3 = calendar.date(byAdding: .day, value: 1, to: day2) else {
            return ["could not build a three-day window"]
        }

        // Starts 22:00 on day 1, ends 02:00 on day 2: six hours of span, three
        // of them on each side of midnight, carrying 60 minutes of work.
        let record = SessionRecord(name: "Overnight", workType: .deepWork,
                                   start: day1.addingTimeInterval(22 * 3_600),
                                   end: day2.addingTimeInterval(2 * 3_600),
                                   workSeconds: 3_600)
        expectClose(record.workSeconds(on: day1, calendar: calendar), 1_800,
                    "half the work belongs to the first day", &problems)
        expectClose(record.workSeconds(on: day2, calendar: calendar), 1_800,
                    "half the work belongs to the second day", &problems)
        expectClose(record.workSeconds(on: day3, calendar: calendar), 0,
                    "no work belongs to a day the record never touched", &problems)
        expectClose(record.workSeconds(on: day1, calendar: calendar)
                    + record.workSeconds(on: day2, calendar: calendar),
                    record.workSeconds, "the split adds back up", &problems)

        // A zero-length record has no span to spread and belongs where it fell.
        let instant = SessionRecord(name: "", workType: .deepWork,
                                    start: day2.addingTimeInterval(600),
                                    end: day2.addingTimeInterval(600),
                                    workSeconds: 120)
        expectClose(instant.workSeconds(on: day2, calendar: calendar), 120,
                    "a zero-span record still lands on its own day", &problems)
        expectClose(instant.workSeconds(on: day1, calendar: calendar), 0,
                    "and on no other", &problems)

        // Through the archive: the streak must not break on the earlier day.
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(day2.addingTimeInterval(12 * 3_600))
        let archive = SessionArchive(directory: directory, now: { clock.value })
        // 50 minutes each side of midnight — both days clear the 25-minute bar
        // only if the split happens.
        archive.append(SessionRecord(name: "Split", workType: .deepWork,
                                     start: day1.addingTimeInterval(22 * 3_600),
                                     end: day2.addingTimeInterval(2 * 3_600),
                                     workSeconds: 100 * 60))
        expectClose(archive.workSeconds(on: day1), 50 * 60,
                    "the earlier day gets its half", &problems)
        expectClose(archive.workSeconds(on: day2), 50 * 60,
                    "the later day gets its half", &problems)
        expect(archive.currentStreak() == 2,
               "both days qualify, got a streak of \(archive.currentStreak())", &problems)
        expect(archive.records(on: day1).count == 1,
               "the record is visible on the day it started", &problems)
        let bars = archive.weekBars()
        expect(bars.last?.minutes == 50, "today's bar shows its own half, got "
               + "\(bars.last?.minutes ?? -1)", &problems)
        return problems
    }

    // MARK: - 65

    /// Two accounting leaks in the "at the Mac" figure, both of which only ever
    /// pushed it downward.
    static func testFlushAndTotalToday() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = TestClock(base)
        let archive = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: archive, ownBundleID: "self",
                                      idle: .disabled, now: { clock.value })

        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        // Flushes fire on every app switch, lock and wake, so two landing inside
        // the archive's five-second floor is routine. The rejected write used to
        // advance the segment's start anyway, deleting the seconds between them.
        clock.advance(2)
        tracker.flush()
        clock.advance(2)
        tracker.flush()
        expect(archive.sessions.isEmpty, "neither short flush should be recorded", &problems)
        expectClose(tracker.openSeconds(), 4,
                    "the refused seconds must still be on the open stretch", &problems)

        clock.advance(56)
        tracker.flush()
        expectClose(archive.totalToday(), 60,
                    "the whole minute survives, not just the last flush", &problems)

        // System processes are not the user working. This total was the one
        // query in the app reading past the filter.
        tracker.appActivated(bundleID: "com.apple.loginwindow", name: "loginwindow")
        clock.advance(3_600)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(60)
        tracker.flush()
        expectClose(archive.totalToday(), 120,
                    "an hour on the lock screen is not an hour at the Mac", &problems)

        // A stretch running through midnight belongs to both days it covers.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: clock.value)
        let split = AppUsageArchive(directory: directory
            .appendingPathComponent("split"), now: { midnight.addingTimeInterval(3_600) })
        split.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                     start: midnight.addingTimeInterval(-1_800),
                                     end: midnight.addingTimeInterval(1_800)))
        expectClose(split.totalToday(), 1_800,
                    "only the half after midnight counts toward today", &problems)
        return problems
    }
}
