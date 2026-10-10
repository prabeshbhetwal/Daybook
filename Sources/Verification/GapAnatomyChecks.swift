import Foundation

/// A hole in the day unfolds into the stretches its Mac events mark out, so a
/// lock and an unlock read as one locked stretch rather than two list rows,
/// and a restart Daybook came back from within the minute still shows.
enum GapAnatomyChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A hole's events become stretches, and nothing recorded fills the rest", lockedAfterNothing),
        ("A locked Mac that sleeps reads asleep, and wakes to locked", deepestStateWins),
        ("A crash found at the next launch shows its window, then Daybook not running",
         crashWindow),
        ("A restart is off until Daybook opens, and ends the lock before it", restartEndsLock),
        ("Only events inside the hole count; an unlock alone was locked from the start",
         insideOnly),
        ("A restart that left no hole is pinned to the story; one inside a hole is not",
         pinnedRestart),
        ("A crash dated from its last heartbeat names its hole and is not pinned as well",
         heartbeatCrash),
        ("The launch that found a force quit ends Daybook's absence, and each crash keeps its launch",
         foundByItsLaunch),
        ("A piece of a hole an away answer split still carries what came before it", splitHole),
        ("A lid's close joins the sleep, and a crash window never grows", slivers),
        ("Expand all reaches a hole an event names, and a pin is never folded as quiet", disclosure),
        ("A short lock in the middle of nothing stays a lock, and slivers grow a stretch a minute at most",
         sliverLimits),
        ("A window that ends just before the hole is cut at the hole's start", clampedToHole),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func event(_ kind: MachineEvent.Kind, _ minutes: Double, until: Double? = nil) -> MachineEvent {
        MachineEvent(kind: kind, at: at(minutes), latest: until.map { at($0) })
    }

    private static func gap(_ from: Double, _ to: Double) -> DateInterval {
        DateInterval(start: at(from), end: at(to))
    }

    private static func shape(_ anatomy: GapAnatomy) -> [String] {
        anatomy.stretches.map { stretch in
            let from = stretch.span.start.timeIntervalSince(SelfTest.base) / 60
            let to = stretch.span.end.timeIntervalSince(SelfTest.base) / 60
            return "\(stretch.title) \(Int(from.rounded()))–\(Int(to.rounded()))"
        }
    }

    /// The day in the redesign's screenshot: Daybook opened at 4:42 pm into a
    /// hole that began at 2:13, then the screen locked from 5:04 to 5:34.
    private static func lockedAfterNothing() -> [String] {
        var problems: [String] = []
        // Recording resumed half a minute after the unlock: that sliver is
        // the lock's, not a third row.
        let anatomy = GapAnatomy.of(gap(0, 201.5), events: [
            event(.daybookStarted, 149), event(.displaySleep, 171), event(.lock, 171),
            event(.displayWake, 200), event(.unlock, 201),
        ])
        let wanted = ["Nothing recorded 0–171", "Mac locked 171–202"]
        expect(shape(anatomy) == wanted, "one locked stretch after nothing recorded, got \(shape(anatomy))",
               &problems)
        expect(anatomy.stretches.last?.displayOff == gap(171, 200),
               "the lock carries the display's dark time, got \(String(describing: anatomy.stretches.last?.displayOff))",
               &problems)
        expect(anatomy.marks == [at(149), at(171)], "marks at the launch and the lock, got \(anatomy.marks)",
               &problems)
        expect(anatomy.isExplained, "a hole with a lock in it unfolds", &problems)
        return problems
    }

    private static func deepestStateWins() -> [String] {
        var problems: [String] = []
        let anatomy = GapAnatomy.of(gap(0, 509), events: [
            event(.lock, 0), event(.displaySleep, 0), event(.systemSleep, 7),
            event(.wake, 502), event(.unlock, 503),
        ])
        let wanted = ["Mac locked 0–7", "Mac asleep 7–502", "Mac locked 502–503", "Display off 503–509"]
        expect(shape(anatomy) == wanted, "sleep outranks the lock it began under, got \(shape(anatomy))",
               &problems)
        return problems
    }

    private static func crashWindow() -> [String] {
        var problems: [String] = []
        let anatomy = GapAnatomy.of(gap(0, 41), events: [
            event(.crashed, 0, until: 32), event(.daybookStarted, 41),
        ])
        let wanted = ["Daybook crashed 0–32", "Daybook not running 32–41"]
        expect(shape(anatomy) == wanted, "the window, then not running, got \(shape(anatomy))", &problems)
        expect(anatomy.stretches.first?.state == .uncertain && anatomy.stretches.first?.foundAt == at(41),
               "the window is uncertain and found at the launch, got \(String(describing: anatomy.stretches.first))",
               &problems)
        return problems
    }

    private static func restartEndsLock() -> [String] {
        var problems: [String] = []
        let anatomy = GapAnatomy.of(gap(0, 30), events: [
            event(.lock, 2), event(.restart, 10), event(.macStarted, 12),
            event(.daybookStarted, 14), event(.unlock, 15),
        ])
        let wanted = ["Nothing recorded 0–2", "Mac locked 2–10", "Mac restarted 10–14",
                      "Mac locked 14–15", "Nothing recorded 15–30"]
        expect(shape(anatomy) == wanted, "the restart cuts the lock, got \(shape(anatomy))", &problems)
        expect(anatomy.marks.contains(at(12)), "the Mac's start is marked, got \(anatomy.marks)", &problems)
        return problems
    }

    private static func insideOnly() -> [String] {
        var problems: [String] = []
        let stale = GapAnatomy.of(gap(0, 30), events: [event(.lock, -60)])
        expect(shape(stale) == ["Nothing recorded 0–30"] && !stale.isExplained,
               "a lock before recorded use explains nothing, got \(shape(stale))", &problems)
        let late = GapAnatomy.of(gap(0, 30), events: [event(.lock, 0.5)])
        expect(shape(late) == ["Mac locked 0–30"],
               "a lock half a minute into the hole takes the hole, got \(shape(late))", &problems)
        let unlocked = GapAnatomy.of(gap(0, 30), events: [event(.unlock, 10)])
        expect(shape(unlocked) == ["Mac locked 0–10", "Nothing recorded 10–30"],
               "an unlock alone was locked from the hole's start, got \(shape(unlocked))", &problems)
        return problems
    }

    private static func pinnedRestart() -> [String] {
        var problems: [String] = []
        func pins(_ usage: [AppUsageSession], _ events: [MachineEvent]) -> [String] {
            StoryChronology.build(records: [], running: nil, usage: usage, machineEvents: events,
                                  day: SelfTest.base, now: at(600))
                .compactMap { moment -> String? in
                    guard case .machine(let event, let resumed) = moment else { return nil }
                    return event.kind.rawValue + (resumed == at(20.4) ? " back at the launch" : " not back")
                }
        }
        let quick = pins([use(0, 20), use(20.5, 40)],
                         [event(.restart, 20.2), event(.daybookStarted, 20.4), event(.lock, 30)])
        expect(quick == ["restart back at the launch"], "a quick restart is pinned with its return, got \(quick)",
               &problems)
        let inHole = pins([use(0, 20), use(80, 90)], [event(.shutDown, 30), event(.daybookStarted, 79)])
        expect(inHole.isEmpty, "a shut down inside a hole belongs to its card, got \(inHole)", &problems)
        let quitBy = GapAnatomy.of(gap(20, 80), events: [
            MachineEvent(kind: .quitByApp, at: at(30), detail: "System Settings"), event(.daybookStarted, 79),
        ])
        expect(shape(quitBy).contains("Daybook quit by System Settings 30–79"),
               "the card names the app that quit Daybook, got \(shape(quitBy))", &problems)
        return problems
    }

    private static func use(_ from: Double, _ to: Double) -> AppUsageSession {
        AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari", start: at(from), end: at(to),
                        endReason: .appSwitch)
    }

    /// `RunMarker` dates a power cut from the last heartbeat, up to a minute
    /// before the recording's hole begins.
    private static func heartbeatCrash() -> [String] {
        var problems: [String] = []
        let usage = [use(0, 20), use(80, 90)]
        let events = [event(.powerLost, 19, until: 79), event(.daybookStarted, 80)]
        let moments = StoryChronology.build(records: [], running: nil, usage: usage, machineEvents: events,
                                            day: SelfTest.base, now: at(600))
        let pins = moments.filter { if case .machine = $0 { return true }; return false }
        let reasons = moments.compactMap { moment -> StoryGapReason? in
            if case .unrecorded(_, let reason) = moment { return reason }
            return nil
        }
        expect(pins.isEmpty && reasons == [.machine(.powerLost)],
               "the cut names the hole once, got pins \(pins.count), reasons \(reasons)", &problems)
        let anatomy = GapAnatomy.of(gap(20, 80), events: events)
        expect(shape(anatomy) == ["Mac lost power 20–79", "Daybook not running 79–80"],
               "the window starts at the hole, got \(shape(anatomy))", &problems)
        return problems
    }

    private static func foundByItsLaunch() -> [String] {
        var problems: [String] = []
        // RunMarker writes a force quit's `latest` and the launch at one instant.
        let anatomy = GapAnatomy.of(gap(0, 100), events: [
            event(.forceQuit, 0, until: 40), event(.daybookStarted, 40), event(.lock, 60), event(.unlock, 90),
        ])
        let wanted = ["Daybook was force quit 0–40", "Nothing recorded 40–60", "Mac locked 60–90",
                      "Nothing recorded 90–100"]
        expect(shape(anatomy) == wanted, "Daybook was back at the launch, got \(shape(anatomy))", &problems)
        let twice = GapAnatomy.of(gap(0, 120), events: [
            event(.crashed, 0, until: 10), event(.daybookStarted, 12),
            event(.crashed, 60, until: 70), event(.daybookStarted, 72),
        ])
        let found = twice.stretches.filter { $0.state == .uncertain }.map(\.foundAt)
        expect(found == [at(12), at(72)], "each crash is found by its own launch, got \(found)", &problems)
        return problems
    }

    private static func splitHole() -> [String] {
        var problems: [String] = []
        let events = [event(.restart, 10), event(.daybookStarted, 100)]
        let piece = GapAnatomy.of(gap(50, 100), in: gap(0, 100), events: events)
        expect(shape(piece) == ["Mac restarted 50–100"],
               "the piece after the answer is still the restart, got \(shape(piece))", &problems)
        return problems
    }

    private static func slivers() -> [String] {
        var problems: [String] = []
        let lid = GapAnatomy.of(gap(0, 60), events: [
            event(.lock, 0.5), event(.systemSleep, 0.52), event(.wake, 58), event(.unlock, 58.5),
        ])
        expect(shape(lid) == ["Mac asleep 0–59", "Nothing recorded 59–60"],
               "the lid and the unlock join the sleep, got \(shape(lid))", &problems)
        let crash = GapAnatomy.of(gap(0, 30), events: [
            event(.crashed, 0, until: 10.25), event(.daybookStarted, 10.25), event(.lock, 10.5),
        ])
        expect(shape(crash) == ["Daybook crashed 0–10", "Mac locked 10–30"]
               && crash.stretches.first?.span.end == at(10.25),
               "the sliver goes to the lock, not the window, got \(shape(crash))", &problems)
        return problems
    }

    private static func disclosure() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let named = StoryMoment.unrecorded(gap(0, 30), reason: .machine(.lock))
            let bare = StoryMoment.unrecorded(gap(40, 50), reason: .unknown)
            let ids = DayStory.expandableIDs(in: [.moment(named), .moment(bare)])
            expect(ids == [named.id], "only the named hole opens, got \(ids)", &problems)
            let pin = StoryMoment.machine(event(.restart, 5), resumed: nil)
            expect(!StoryQuietGrouping.isQuiet(pin), "a restart pin is part of the day's account", &problems)
            return problems
        }
    }

    private static func sliverLimits() -> [String] {
        var problems: [String] = []
        let brief = GapAnatomy.of(gap(0, 30), events: [event(.lock, 10), event(.unlock, 10.5)])
        let states = brief.stretches.map(\.state)
        expect(states == [.unexplained, .locked, .unexplained] && brief.isExplained,
               "a half-minute lock between nothing stays, got \(shape(brief))", &problems)
        // After the wake, 55-second locks alternate with 55-second gaps.
        var events = [event(.systemSleep, 0), event(.wake, 50)]
        for step in 0..<6 {
            let start = 50 + Double(step) * 110 / 60
            events += [event(.lock, start + 55.0 / 60), event(.unlock, start + 110.0 / 60)]
        }
        let chain = GapAnatomy.of(gap(0, 70), events: events)
        let asleepEnd = chain.stretches.first { $0.state == .asleep }?.span.end
        expect(asleepEnd.map { $0 <= at(51) } == true,
               "the sleep claims at most a minute past the wake, got \(shape(chain))", &problems)
        return problems
    }

    private static func clampedToHole() -> [String] {
        var problems: [String] = []
        let anatomy = GapAnatomy.of(gap(10, 41), events: [event(.crashed, 9.9, until: 10 - 1.5 / 60)])
        let total = anatomy.stretches.reduce(0) { $0 + $1.span.duration }
        expect(anatomy.stretches.first?.span.start == at(10) && abs(total - 31 * 60) < 0.001,
               "the stretches cover exactly the hole, got \(shape(anatomy)) totalling \(total) s", &problems)
        return problems
    }
}
