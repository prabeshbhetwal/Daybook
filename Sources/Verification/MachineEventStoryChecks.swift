import Foundation

/// The story names a hole in the day by the machine event inside it — a
/// sleep, a shut down, a crash — and History lists every event of the day.
/// A day recorded before events were kept reads exactly as it did.
enum MachineEventStoryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A hole in the day is named by the machine event inside it, not 'Mac locked'",
         holeNamedByEvent),
        ("A day without machine events keeps the labels it always had",
         oldDaysUnchanged),
        ("History lists every machine event of the day, every wake included",
         everyEventListed),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func use(_ from: Double, _ to: Double, _ end: UsageEndReason) -> AppUsageSession {
        AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari", start: at(from), end: at(to), endReason: end)
    }

    private static func event(_ kind: MachineEvent.Kind, _ minutes: Double, until: Double? = nil) -> MachineEvent {
        MachineEvent(kind: kind, at: at(minutes), latest: until.map { at($0) })
    }

    private static func reasons(_ usage: [AppUsageSession], _ events: [MachineEvent]) -> [StoryGapReason] {
        StoryChronology.build(records: [], running: nil, usage: usage, machineEvents: events,
                              day: SelfTest.base, now: at(600))
            .compactMap { moment -> StoryGapReason? in
                if case .unrecorded(_, let reason) = moment { return reason }
                return nil
            }
    }

    private static func holeNamedByEvent() -> [String] {
        var problems: [String] = []
        let locked = [use(0, 20, .systemLock), use(80, 90, .appSwitch)]
        // The sleep is a moment before the recording stops.
        let slept = reasons(locked, [event(.systemSleep, 19.99), event(.wake, 50), event(.unlock, 79.9)])
        expect(slept.map(\.title) == ["Mac asleep"], "a sleep names its hole, got \(slept.map(\.title))", &problems)
        let gap = DateInterval(start: at(20), end: at(80))
        let cases: [(StoryGapReason, [MachineEvent], UsageEndReason, String)] = [
            (.machine(.displaySleep), [event(.displaySleep, 20)], .systemLock, "Display off"),
            (.machine(.shutDown), [event(.shutDown, 20), event(.macStarted, 60)], .systemLock, "Mac shut down"),
            (.machine(.crashed), [event(.crashed, 19.2, until: 20.2)], .stillOpen, "Daybook crashed"),
            (.machine(.systemSleep), [event(.lock, 20), event(.systemSleep, 21)], .systemLock, "Mac asleep"),
            (.idle, [event(.lock, 24), event(.displaySleep, 30)], .idle, "No input"),
            (.machine(.systemSleep), [event(.displaySleep, 30), event(.systemSleep, 40)], .idle, "Mac asleep"),
            // A sleep where the next stretch begins belongs to that stretch.
            (.locked, [event(.systemSleep, 80)], .systemLock, "Mac locked"),
        ]
        for (wanted, events, ending, title) in cases {
            let reason = StoryChronology.gapReason(for: gap, usage: [use(0, 20, ending)], events: events)
            expect(reason == wanted && reason.title == title,
                   "\(events.map(\.kind.rawValue)) after a \(ending) stretch reads \(title), got \(reason.title)",
                   &problems)
        }
        return problems
    }

    private static func oldDaysUnchanged() -> [String] {
        var problems: [String] = []
        let usage = [use(0, 10, .systemLock), use(20, 30, .idle), use(40, 50, .appSwitch), use(60, 70, .appSwitch)]
        let before = reasons(usage, [])
        expect(before == [.locked, .idle, .unknown], "without events the old labels stand, got \(before)", &problems)
        // Events that end a hole say nothing about why it is there.
        let enders = reasons(usage, [event(.wake, 15), event(.unlock, 35), event(.daybookStarted, 55)])
        expect(enders == before, "a wake, an unlock or a start changes no label, got \(enders)", &problems)
        return problems
    }

    private static func everyEventListed() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // The next day, so History keeps the day it draws.
            let clock = TestClock(Calendar.current.date(byAdding: .day, value: 1, to: at(0)) ?? at(1_440))
            let folder = SelfTest.scratchDirectory()
            let log = MachineEventLog(directory: folder)
            let wakes = (1...5).map { event(.wake, 20 + Double($0) * 5) }
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: at(20)) ?? at(-1_440)
            log.append(wakes + [MachineEvent(kind: .systemSleep, at: yesterday)])
            let usage = AppUsageArchive(directory: folder, now: { clock.value })
            _ = usage.record(use(0, 20, .systemLock))
            _ = usage.record(use(80, 90, .appSwitch))
            let engine = SelfTest.makeEngine(clock)
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: AppUsageTracker(archive: usage, ownBundleID: "fc.machine.test",
                                                  idle: .disabled, now: { clock.value }),
                         usage: usage)
            store.machineEventLog = log
            func drawn() -> [String] {
                store.storyDayProjection(on: SelfTest.base).chronology.compactMap { item -> String? in
                    if case .moment(.unrecorded(_, let reason)) = item { return reason.title }
                    return nil
                }
            }
            let before = drawn()
            expect(before == ["Mac locked"], "with only wakes the hole reads as before, got \(before)", &problems)
            // A launch names a past day's hole after that day was drawn.
            log.append([event(.systemSleep, 19.99)])
            expect(drawn() == ["Mac asleep"], "History redraws a day its log has grown for, got \(drawn())",
                   &problems)
            let listed = store.machineEvents(on: SelfTest.base)
            expect(listed.count == 6 && listed.filter { $0.kind == .wake }.count == 5,
                   "the day lists its sleep and all five wakes, not yesterday's, got \(listed.map(\.kind))",
                   &problems)
            let titles = store.storyMoments(on: SelfTest.base).compactMap { moment -> String? in
                if case .unrecorded(_, let reason) = moment { return reason.title }
                return nil
            }
            expect(titles == ["Mac asleep"], "the story names the hole from the log, got \(titles)", &problems)
            return problems
        }
    }
}
