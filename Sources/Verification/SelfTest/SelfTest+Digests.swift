import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 90

    /// "Dinner" in the reason field becomes the break record's name — what the
    /// timeline labels the gap — capitalised and trimmed; no name means
    /// "Break"; and a label given with any other answer is consumed, not kept
    /// for the next question.
    static func testNamedBreak() -> [String] {
        var problems: [String] = []
        func absence(_ engine: SessionEngine, _ clock: TestClock) {
            clock.advance(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(22 * 60)
            engine.transition(on: .awayEnded)
        }
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Work")
        absence(engine, clock)
        engine.decide(.tookBreak, label: "  dinner ")
        let named = engine.archive.records.last { $0.workType == .breakTime }
        expect(named?.name == "Dinner", "the break is recorded as Dinner, got \(named?.name ?? "nil")",
               &problems)
        expectClose(named?.workSeconds ?? 0, 22 * 60, "for the absence's length", &problems)

        absence(engine, clock)
        engine.decide(.tookBreak)
        let plain = engine.archive.records.last { $0.workType == .breakTime }
        expect(plain?.name == "Break", "no name means Break", &problems)

        absence(engine, clock)
        engine.decide(.continueSession, label: "lunch")
        let count = engine.archive.records.filter { $0.workType == .breakTime }.count
        expect(count == 2, "'I was away' with a label records nothing", &problems)
        absence(engine, clock)
        engine.decide(.tookBreak)
        expect(engine.archive.records.last { $0.workType == .breakTime }?.name == "Break",
               "and the label did not leak into the next break", &problems)
        return problems
    }

    // MARK: - 91

    /// The Sessions card's rows: two stretches of one thread with a break
    /// between them are one session with two stretches and a rest row; a
    /// different thread is its own session; the running session joins its
    /// thread and is marked.
    static func testSessionDigest() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        let thread = UUID()
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
        let records = [
            SessionRecord(name: "Refactor", workType: .deepWork, start: at(9), end: at(10),
                          workSeconds: 3_600, threadID: thread),
            SessionRecord(name: "Dinner", workType: .breakTime, start: at(10), end: at(10.5),
                          workSeconds: 1_800),
            SessionRecord(name: "Refactor", workType: .deepWork, start: at(10.5), end: at(11),
                          workSeconds: 1_800, threadID: thread),
            SessionRecord(name: "Email", workType: .admin, start: at(13), end: at(13.5),
                          workSeconds: 1_800)
        ]
        let running = RunningThread(threadID: thread, name: "Refactor", workType: .deepWork,
                                    start: at(15), worked: 600)
        let entries = SessionDigest.entries(records: records, running: running, now: at(15.2), day: day)
        expect(entries.count == 4, "session, rest, session, running session → 4 rows, got \(entries.count)",
               &problems)
        guard entries.count == 4 else { return problems }
        guard case .session(let first) = entries[0] else { return problems + ["first row is a session"] }
        expect(first.stretches == 2, "two stretches fold into one session, got \(first.stretches)", &problems)
        expectClose(first.worked, 5_400, "worked sums the stretches", &problems)
        expect(first.spans.count == 2, "and keeps both spans", &problems)
        guard case .rest(let rest) = entries[1] else { return problems + ["second row is the rest"] }
        expect(rest.name == "Dinner", "the rest keeps its name", &problems)
        guard case .session(let email) = entries[2] else { return problems + ["third row is Email"] }
        expect(email.workType == .admin && email.stretches == 1, "another thread is its own row", &problems)
        guard case .session(let live) = entries[3] else { return problems + ["fourth row is the running one"] }
        expect(live.isRunning && live.threadID == thread, "the running session is marked", &problems)
        expect(live.stretches == 1, "and, separated by another thread, starts its own row", &problems)
        return problems
    }

    /// A record crossing midnight belongs to each day only for its overlap. A
    /// named break remains evidence in the digest, but never becomes focus in
    /// the dashboard's session, bracket, count, or work-type figures.
    ///
    /// This catches the old raw-record path: it rendered a 23:30–00:30 record
    /// as a full hour on either day and let break records into focus quality.
    static func testDayDigestAndFocusAreDayScoped() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(base)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else {
            return ["could not make yesterday"]
        }
        let crossMidnight = SessionRecord(name: "Night shift", workType: .deepWork,
                                          start: yesterday.addingTimeInterval(23.5 * 3_600),
                                          end: day.addingTimeInterval(0.5 * 3_600),
                                          workSeconds: 3_600)
        let dinner = SessionRecord(name: "Dinner", workType: .breakTime,
                                   start: day.addingTimeInterval(9 * 3_600),
                                   end: day.addingTimeInterval(9.5 * 3_600),
                                   workSeconds: 1_800)
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        archive.append(crossMidnight)
        archive.append(dinner)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        usage.record(AppUsageSession(bundleID: "com.night", appName: "Night",
                                     start: day, end: day.addingTimeInterval(0.5 * 3_600)))
        usage.record(AppUsageSession(bundleID: "com.dinner", appName: "Dinner",
                                     start: day.addingTimeInterval(9 * 3_600),
                                     end: day.addingTimeInterval(9.5 * 3_600)))

        let previousDigest = SessionDigest.entries(records: [crossMidnight], running: nil,
                                                   now: day, day: yesterday, calendar: calendar)
        let previousRows = previousDigest.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        expectClose(previousRows.first?.start.timeIntervalSince(yesterday) ?? -1, 23.5 * 3_600,
                    "the previous-day row begins at 23:30", &problems)
        expectClose(previousRows.first?.end.timeIntervalSince(yesterday) ?? -1, 24 * 3_600,
                    "the previous-day row ends at midnight", &problems)
        expectClose(previousRows.first?.worked ?? 0, 1_800,
                    "the previous-day row receives 30m of work credit", &problems)

        let digest = SessionDigest.entries(records: archive.records(on: day),
                                           running: nil, now: day.addingTimeInterval(10 * 3_600),
                                           day: day,
                                           calendar: calendar)
        let focusRows = digest.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        expect(focusRows.count == 1, "only the work record is a session row", &problems)
        expectClose(focusRows.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "the selected-day row begins at midnight", &problems)
        expectClose(focusRows.first?.end.timeIntervalSince(day) ?? -1, 1_800,
                    "the selected-day row ends after its 30m overlap", &problems)
        expectClose(focusRows.first?.worked ?? 0, 1_800,
                    "the selected-day row receives 30m of work credit", &problems)
        expect(digest.contains { entry in
            if case .rest(let rest) = entry { return rest.name == "Dinner" }
            return false
        }, "the named break remains a rest row", &problems)

        let live = RunningThread(threadID: UUID(), name: "Late deploy", workType: .deepWork,
                                 start: yesterday.addingTimeInterval(23.75 * 3_600), worked: 1_800)
        let runningDigest = SessionDigest.entries(records: [], running: live,
                                                  now: day.addingTimeInterval(0.25 * 3_600),
                                                  day: day, calendar: calendar)
        let runningRows = runningDigest.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
        expectClose(runningRows.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "a running span is clipped at today's midnight", &problems)
        expectClose(runningRows.first?.end.timeIntervalSince(day) ?? -1, 900,
                    "a running span ends at now inside the selected day", &problems)
        expectClose(runningRows.first?.worked ?? 0, 900,
                    "a running span receives only its 15m day credit", &problems)

        let stats = DashboardStats(sessions: archive, usage: usage,
                                   calendar: calendar, now: { clock.value })
        let focus = stats.focusSessions(for: day)
        expect(focus.count == 1, "break records are not focus sessions, got \(focus.count)", &problems)
        expectClose(focus.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "focus session starts inside the selected day", &problems)
        expectClose(focus.first?.end.timeIntervalSince(day) ?? -1, 1_800,
                    "focus session ends inside the selected day", &problems)
        expectClose(focus.first?.workSeconds ?? 0, 1_800,
                    "focus session has only this day's work credit", &problems)
        let spans = stats.focusSpans(for: day)
        expect(spans.count == 1, "the break does not create a focus bracket", &problems)
        expectClose(spans.first?.start.timeIntervalSince(day) ?? -1, 0,
                    "the focus bracket begins inside the day", &problems)
        expectClose(spans.first?.end.timeIntervalSince(day) ?? -1, 1_800,
                    "the focus bracket ends inside the day", &problems)
        let quality = stats.focusQuality(for: day)
        expect(quality.sessionCount == 1,
               "the break does not increase the focus session count, got \(quality.sessionCount)", &problems)
        expect(quality.byWorkType.allSatisfy { $0.workType != WorkType.breakTime },
               "the break is absent from focus work-type shares", &problems)
        return problems
    }

    /// A running stretch can begin yesterday while the dashboard is showing
    /// today. Its work-type credit must be the overlap since local midnight,
    /// otherwise last night's work inflates today's focus-quality composition.
    static func testLiveFocusQualityClipsAtMidnight() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        let clock = TestClock(day.addingTimeInterval(-30 * 60))
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, calendar: calendar,
                                     now: { clock.value })
        archive.append(SessionRecord(name: "Morning admin", workType: .admin,
                                     start: day, end: day.addingTimeInterval(30 * 60),
                                     workSeconds: 30 * 60))
        let defaults = MemoryDefaults.suite(named: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self",
                                   schedulesDwell: false, now: { clock.value })
        engine.start(workType: .deepWork, intent: "Overnight deploy")
        clock.advance(60 * 60)

        let usage = AppUsageArchive(directory: directory, calendar: calendar,
                                    now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)

        let deep = store.focusQuality.byWorkType.first { $0.workType == .deepWork }
        let admin = store.focusQuality.byWorkType.first { $0.workType == .admin }
        expectClose(engine.elapsed, 60 * 60,
                    "the underlying running stretch still spans the full hour", &problems)
        expectClose(engine.elapsedToday(), 30 * 60,
                    "only thirty running minutes belong to today", &problems)
        expectClose(deep?.seconds ?? -1, 30 * 60,
                    "today's live Deep Work quality credit is midnight-clipped", &problems)
        expectClose(admin?.seconds ?? -1, 30 * 60,
                    "today's archived Admin quality credit remains thirty minutes", &problems)
        expectClose(deep?.share ?? -1, 0.5,
                    "today's work-type share excludes last night's running portion", &problems)
        return problems
    }
}
