import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 92

    /// "Apps used inside this session": usage intersected with the session's
    /// spans, ranked, with shares out of the inside rather than the day.
    static func testAppsWithinSpans() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(base)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let day = Calendar.current.startOfDay(for: base)
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
        usage.record(AppUsageSession(bundleID: "com.a", appName: "A", start: at(9), end: at(10)))   // 1h
        usage.record(AppUsageSession(bundleID: "com.b", appName: "B", start: at(10), end: at(10.5))) // 30m
        usage.record(AppUsageSession(bundleID: "com.c", appName: "C", start: at(14), end: at(16)))  // outside
        let stats = DashboardStats(sessions: SessionArchive(directory: directory, now: { clock.value }),
                                   usage: usage, now: { clock.value })
        let inside = stats.rankedApps(for: day, within: [DateInterval(start: at(9.5), end: at(10.5))])
        expect(inside.map(\.bundleID) == ["com.a", "com.b"], "A then B, C excluded, got \(inside.map(\.bundleID))",
               &problems)
        expectClose(inside.first?.total ?? 0, 1_800, "A counts only its 30m inside the span", &problems)
        expectClose(inside.first?.share ?? 0, 0.5, "shares are of the inside (30m of 60m)", &problems)
        expectClose(stats.trackedTotal(for: day, within: [DateInterval(start: at(9.5), end: at(10.5))]),
                    3_600, "hands-on inside the span", &problems)
        return problems
    }

    // MARK: - 93

    /// The summary is the figures in words. A full day names its time, its
    /// sessions, its apps and the day before; an empty day says it is empty;
    /// independent focus/tracked totals are never called an intersection;
    /// today speaks in the present.
    static func testSummaryText() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
        let thread = UUID()
        let deep = DaySession(id: UUID(), threadID: thread, name: "Refactor the parser",
                              workType: .deepWork, start: at(8.75), end: at(15.9),
                              worked: 3 * 3_600 + 47 * 60, stretches: 4,
                              spans: [DateInterval(start: at(8.75), end: at(12)),
                                      DateInterval(start: at(12.5), end: at(15.9))],
                              isRunning: false)
        let email = DaySession(id: UUID(), threadID: UUID(), name: "", workType: .admin,
                               start: at(16), end: at(16.5), worked: 1_800, stretches: 1,
                               spans: [DateInterval(start: at(16), end: at(16.5))], isRunning: false)
        let lunch = RestEntry(id: UUID(), name: "Lunch", start: at(12), end: at(12.5))
        var input = DaySummaryInput(
            day: day, isToday: false,
            tracked: 8 * 3_600 + 6 * 60, firstSeen: at(8.7), lastSeen: at(23.35),
            focused: 4 * 3_600 + 17 * 60, goal: 4 * 3_600,
            sessions: [deep, email], rests: [lunch],
            apps: [AppRank(bundleID: "a", appName: "Dia", total: 3 * 3_600 + 4 * 60, share: 0.38, longest: 0),
                   AppRank(bundleID: "b", appName: "Claude", total: 2 * 3_600 + 19 * 60, share: 0.29, longest: 0),
                   AppRank(bundleID: "c", appName: "Finder", total: 600, share: 0.02, longest: 0)],
            peak: "1pm–4pm", insideSessionShare: 0.45, switchesPerStretch: 57.3,
            workTypes: [WorkTypeShare(workType: .deepWork, seconds: 3_000, share: 0.94),
                        WorkTypeShare(workType: .breakTime, seconds: 200, share: 0.06)],
            previousTracked: 9 * 3_600, previousFocused: 3 * 3_600 + 7 * 60)
        let text = SummaryText.plain(SummaryText.day(input))
        for needle in ["You were at the Mac for 8h 6m", "focused for 4h 17m in 2 sessions",
                       "goal met",
                       "The longest, Deep work, Refactor the parser, ran", "for 3h 47m in 4 stretches with one break (Lunch 30m)",
                       "The busiest apps were Dia (3h 4m, 38%) and Claude (2h 19m, 29%), across 3 apps in all",
                       "the busiest hours were 1pm–4pm",
                       "45% of the time at the Mac fell inside a session, with about 57 app switches per stretch",
                       "by type, Deep work 94%, Break 6%",
                       "54m less at the Mac and 1h 10m more focused"] {
            expect(text.contains(needle), "summary says “\(needle)”, got: \(text)", &problems)
        }
        expect(!text.contains("**"), "plain text carries no bold marks", &problems)
        expect(!text.contains("% of that time"),
               "raw focused/tracked division is not a temporal share, even below 100%", &problems)
        expect(SummaryText.day(input).count == 5, "five sentences for a full day", &problems)

        // Short of the goal, written as a shortfall on a past day.
        input.focused = 3 * 3_600 + 47 * 60
        expect(SummaryText.plain(SummaryText.day(input)).contains("13m short of the 4h goal"),
               "a past day fell short", &problems)

        // Today: present tense, "to the goal", and a running session is said to run.
        input.isToday = true
        input.sessions = [DaySession(id: deep.id, threadID: thread, name: deep.name, workType: .deepWork,
                                     start: deep.start, end: deep.end, worked: deep.worked, stretches: 4,
                                     spans: deep.spans, isRunning: true), email]
        let today = SummaryText.plain(SummaryText.day(input))
        expect(today.hasPrefix("So far today you've been at the Mac for 8h 6m, since"),
               "today speaks in the present, got: \(today)", &problems)
        expect(today.contains("13m to the 4h goal"), "today has a goal to reach", &problems)
        expect(today.contains("and it's still running"), "the running session is named as running", &problems)
        expect(today.contains("Against the whole of yesterday"), "today compares against all of yesterday", &problems)

        // Focused above tracked: the share is not a share, so it is not said.
        input.focused = 9 * 3_600
        expect(!SummaryText.plain(SummaryText.day(input)).contains("% of that time"),
               "no share above 100%", &problems)

        // Nothing at all.
        input = DaySummaryInput(day: day, isToday: false, tracked: 0, firstSeen: nil, lastSeen: nil,
                                focused: 0, goal: 4 * 3_600, sessions: [], rests: [], apps: [], peak: nil,
                                insideSessionShare: 0, switchesPerStretch: 0, workTypes: [],
                                previousTracked: 0, previousFocused: 0)
        expect(SummaryText.day(input) == ["Nothing was recorded on this day."],
               "an empty day says so and nothing else", &problems)

        // A week.
        let week = SummaryText.plain(SummaryText.period(PeriodSummaryInput(
            period: .week, containsToday: true, tracked: 31 * 3_600 + 20 * 60, activeDays: 5, totalDays: 7,
            averagePerActiveDay: 6 * 3_600 + 16 * 60, previousTracked: 29 * 3_600 + 10 * 60,
            focused: 14 * 3_600, sessions: 9, goal: 4 * 3_600, goalMetDays: 2,
            busiestDay: day, busiestTracked: 8 * 3_600 + 6 * 60,
            longestSitting: ("Dia", 95 * 60, day), apps: [("Dia", 12 * 3_600, 0.38)], appCount: 14,
            workTypes: [])))
        for needle in ["This week you were at the Mac for 31h 20m across 5 of 7 days — 6h 16m per active day, 2h 10m more than the week before.",
                       "You focused for 14h in 9 sessions, meeting the 4h goal on 2 days.",
                       "(8h 6m); the longest single sitting was 1h 35m in Dia on",
                       "All of the time was in Dia, across 14 apps in all."] {
            expect(week.contains(needle), "week summary says “\(needle)”, got: \(week)", &problems)
        }
        return problems
    }

    // MARK: - 94

    /// A session is a thread. Two stretches of one thread are one session with
    /// their work added; the running stretch joins its thread's count rather
    /// than adding one; a different thread is another session.
    static func testSessionsAreThreads() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let archive = SessionArchive(directory: directory)
        let engine = SessionEngine(store: prefs, archive: archive,
                                   ownBundleID: "com.test", schedulesDwell: false)
        let thread = UUID()
        let now = anchoredNow()
        archive.append(SessionRecord(name: "Parser", workType: .deepWork,
                                     start: now.addingTimeInterval(-7_200),
                                     end: now.addingTimeInterval(-5_400),
                                     workSeconds: 1_800, threadID: thread))
        archive.append(SessionRecord(name: "Parser, tests", workType: .deepWork,
                                     start: now.addingTimeInterval(-5_000),
                                     end: now.addingTimeInterval(-2_300),
                                     workSeconds: 2_700, threadID: thread))
        archive.append(SessionRecord(name: "Email", workType: .admin,
                                     start: now.addingTimeInterval(-2_000),
                                     end: now.addingTimeInterval(-1_000),
                                     workSeconds: 1_000))
        archive.append(SessionRecord(name: "Lunch", workType: .breakTime,
                                     start: now.addingTimeInterval(-5_400),
                                     end: now.addingTimeInterval(-5_000),
                                     workSeconds: 400))
        expect(archive.threadCount(on: now) == 2,
               "two sessions — the thread once, got \(archive.threadCount(on: now))", &problems)
        let longest = archive.longestThread(on: now)
        expectClose(longest?.seconds ?? 0, 4_500, "the thread's stretches add up", &problems)
        expect(longest?.name == "Parser, tests", "named by its latest stretch, got \(longest?.name ?? "nil")",
               &problems)
        expectClose(archive.threadWork(thread, on: now), 4_500, "thread work on the day", &problems)
        expect(archive.sessionsToday() == 2 && abs(archive.longestToday() - 4_500) < 1,
               "today's figures count threads", &problems)

        // Running on the same thread: still two sessions; the longest grows.
        engine.start(workType: .deepWork, intent: "Parser", threadID: thread)
        expect(engine.sessionsToday == 2, "the running stretch joins its thread, got \(engine.sessionsToday)",
               &problems)
        expect(engine.longestToday >= 4_500, "longest is the thread with its live stretch", &problems)
        engine.stop()
        // Running on a new thread: a third session.
        engine.start(workType: .deepWork, intent: "Fresh")
        expect(engine.sessionsToday == 3, "a new thread is a new session, got \(engine.sessionsToday)",
               &problems)
        engine.stop()
        return problems
    }

    // MARK: - 95

    /// The lid closes at T (away begins). The machine sleeps; during a dark
    /// wake the idle sampler, whose clock did not run while asleep, back-dates
    /// a pause only to T+86m. The wake at T+132m must measure the absence from
    /// T: past the cap the session ends where the lid closed, and below the
    /// cap the question is about the whole of it.
    static func testAbsenceFromWhereItBegan() -> [String] {
        var problems: [String] = []
        func scenario(capHours: Double) -> (engine: SessionEngine, archive: SessionArchive, clock: TestClock) {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = capHours * 3_600
            let clock = TestClock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Lid test")
            clock.advance(30 * 60)                                     // 30m of work
            engine.transition(on: .awayBegan(trigger: .systemSleep))    // T: lid closes
            clock.advance(96 * 60)                                     // asleep, dark wakes
            engine.transition(on: .idleObserved(seconds: 600))         // sampler: "idle 10m" → pause at T+86m
            guard engine.state.isPaused else { problems.append("the sampler pauses"); return (engine, archive, clock) }
            clock.advance(36 * 60)                                     // T+132m: lid opens
            engine.transition(on: .awayEnded)
            return (engine, archive, clock)
        }

        // Cap one hour: 132 minutes away ends the session where the lid closed.
        let capped = scenario(capHours: 1)
        expect(capped.engine.state == .idle, "past the cap the session is over, got \(capped.engine.state)", &problems)
        let record = capped.archive.records.last
        expectClose(record?.end.timeIntervalSince(base) ?? 0, 30 * 60,
                    "the record ends where the lid closed, not at the late pause", &problems)
        expectClose(record?.workSeconds ?? 0, 30 * 60, "and carries only the work before it", &problems)

        // Cap four hours: the question is about 132 minutes, not the pause's 46.
        let asked = scenario(capHours: 4)
        if case .awaitingUserDecision(let away, _) = asked.engine.state {
            expectClose(away, 132 * 60, "the whole absence is asked about, got \(Int(away / 60))m", &problems)
        } else {
            problems.append("below the cap the absence is asked about, got \(asked.engine.state)")
        }
        return problems
    }
}
