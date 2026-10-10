import Foundation

/// The tracker ends a stretch `.systemLock` at the lock screen, and also when
/// Spotlight, Control Centre or a password prompt comes forward, when
/// recording is turned off and on Step away. Since the machine event log
/// began a lock leaves its own event, so a hole with none is not called a
/// lock; a day from before the log reads exactly as it did.
enum GapUnexplainedStopChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A hole Spotlight left after the event log began reads 'Not recorded', not 'Mac locked'",
         spotlightHoleNotLocked),
        ("A hole from before the event log began still reads 'Mac locked'",
         preLogHoleUnchanged),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func use(_ from: Double, _ to: Double, _ end: UsageEndReason) -> AppUsageSession {
        AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari", start: at(from), end: at(to), endReason: end)
    }

    private static func log(startingAt minutes: Double) -> MachineEventLog {
        let log = MachineEventLog(directory: SelfTest.scratchDirectory())
        log.append([MachineEvent(kind: .daybookStarted, at: at(minutes))])
        return log
    }

    /// A store a day later, so History keeps the day it draws: Safari until
    /// recording stopped at 20 minutes, Safari again from 80.
    @MainActor
    private static func makeStore(log: MachineEventLog?) -> SessionStore {
        let clock = TestClock(Calendar.current.date(byAdding: .day, value: 1, to: at(0)) ?? at(1_440))
        let usage = AppUsageArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
        _ = usage.record(use(0, 20, .systemLock))
        _ = usage.record(use(80, 90, .appSwitch))
        let store = SessionStore(engine: SelfTest.makeEngine(clock), now: { clock.value })
        store.attach(tracker: AppUsageTracker(archive: usage, ownBundleID: "fc.gapstop.test",
                                              idle: .disabled, now: { clock.value }),
                     usage: usage)
        store.machineEventLog = log
        return store
    }

    /// The hole's reason in the story, then in History's drawing of the day.
    @MainActor
    private static func holes(_ store: SessionStore) -> [StoryGapReason] {
        let story = store.storyMoments(on: SelfTest.base).compactMap { moment -> StoryGapReason? in
            if case .unrecorded(_, let reason) = moment { return reason }
            return nil
        }
        let drawn = store.storyDayProjection(on: SelfTest.base).chronology.compactMap { item -> StoryGapReason? in
            if case .moment(.unrecorded(_, let reason)) = item { return reason }
            return nil
        }
        return story + drawn
    }

    private static func spotlightHoleNotLocked() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let reasons = holes(makeStore(log: log(startingAt: -60)))
            expect(reasons == [.recordingStopped, .recordingStopped] && reasons.allSatisfy { $0.title == "Not recorded" },
                   "the story and History call the hole 'Not recorded', got \(reasons.map(\.title))", &problems)
            let hint = reasons.first?.explanation ?? ""
            expect(hint.contains("Spotlight") && hint.contains("recording was off"),
                   "its hint names what stops recording, got \(hint)", &problems)
            // A lock still names its hole, however late macOS reports it, and
            // idleness and other endings read as before. A restart announced
            // 24 s before the stop, with no launch since, is no Spotlight: its
            // pin names it, and the hole keeps the plain hint.
            let gap = DateInterval(start: at(20), end: at(80))
            let restart = MachineEvent(kind: .restart, at: at(19.6))
            let cases: [(UsageEndReason, [MachineEvent], StoryGapReason)] = [
                (.systemLock, [MachineEvent(kind: .lock, at: at(25))], .machine(.lock)),
                (.idle, [], .idle),
                (.appSwitch, [], .unknown),
                (.systemLock, [restart], .unknown),
                (.systemLock, [MachineEvent(kind: .restart, at: at(5)), MachineEvent(kind: .daybookStarted, at: at(8))],
                 .recordingStopped),
            ]
            for (ending, events, wanted) in cases {
                let reason = StoryChronology.gapReason(for: gap, usage: [use(0, 20, ending)], events: events,
                                                       eventLogStart: at(-60))
                expect(reason == wanted, "a \(ending) hole with \(events.map(\.kind.rawValue)) reads "
                       + "\(wanted.title), got \(reason)", &problems)
            }
            // A stop at the log's first moment is inside it.
            let first = StoryChronology.gapReason(for: gap, usage: [use(0, 20, .systemLock)], events: [],
                                                  eventLogStart: at(20))
            expect(first == .recordingStopped, "a stop as the log begins is not a lock, got \(first)", &problems)
            return problems
        }
    }

    private static func preLogHoleUnchanged() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let none = holes(makeStore(log: nil))
            expect(none == [.locked, .locked] && none.allSatisfy { $0.title == "Mac locked" && $0.explanation == nil },
                   "without a log the hole reads 'Mac locked' as it did, got \(none.map(\.title))", &problems)
            // The log began inside the hole: the stop came before it.
            let store = makeStore(log: log(startingAt: 40))
            let inside = holes(store)
            expect(inside == [.locked, .locked],
                   "a stop before the log began reads 'Mac locked', got \(inside.map(\.title))", &problems)
            // A log of the same length that began earlier redraws the day.
            store.machineEventLog = log(startingAt: -60)
            let redrawn = holes(store)
            expect(redrawn == [.recordingStopped, .recordingStopped],
                   "History redraws a day when the log's start moves, got \(redrawn.map(\.title))", &problems)
            return problems
        }
    }
}
