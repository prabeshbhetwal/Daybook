import Foundation

/// Activity-aware sessions: the beat recorder cuts the ticker's readings into 30-second
/// beats and keeps the input each front app received. Time is a `TestClock` that starts on
/// a grid edge, so the first tick of a check opens a whole cell.
enum BeatRecorderChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A beat closes on the grid edge with each app's seconds", closesOnGridEdge),
        ("Input lands in the slice that received it", inputLandsInItsSlice),
        ("A flick under five seconds folds into its neighbour", flickFoldsIntoNeighbour),
        ("Counts with no real input behind them are discarded", syntheticInputIsDiscarded),
        ("Presence is the sampler's reading for most of the beat", presenceIsTheMajority),
        ("Sleep never becomes one long slice", sleepIsNotOneSlice),
        ("Counters are read only when a beat closes or the app changes", countersReadAtEdgesOnly),
        ("Recording that starts mid-cell keeps its true times", midCellStartKeepsTimes),
        ("A counter that wraps still counts what arrived", wrappedCounterCounts),
        ("Holders are kept as read, with unknown apart from none", holdersKept),
        ("Stopping hands back the partial beat", stopHandsBackPartial),
        ("An app change after a gap or past the edge opens in the next beat", changeAfterGapOrEdge),
        ("A clock stepped back records no second twice", clockStepBackRecordsNothingTwice),
        ("A clock a day ahead, once corrected, records at once", clockCorrectedAfterADayAheadRecordsAtOnce),
        ("A single skipped timer fire keeps the typing it saw", skippedTimerFireKeepsTheTyping),
        ("Input that arrives in a gap is not credited to the slice before it", inputInAGapIsNotTheSlicesOwn),
        ("The idle guard counts from when the baseline was read", idleGuardCountsFromTheBaseline),
        ("Stopping after a gap ends the partial beat at the last tick", stopAfterAGapEndsAtTheLastTick),
    ]

    /// A recorder, a clock on a grid edge, and the readings its closures hand back.
    /// Shared with `BeatRecorderChecks+Time.swift`.
    final class Rig {
        let start = Beat.gridStart(for: SelfTest.base)
        let clock = TestClock(Beat.gridStart(for: SelfTest.base))
        var recorder = BeatRecorder()
        var counts = CounterReading(keys: 0, clicks: 0, scrolls: 0)
        var idle: TimeInterval = 0
        var counterReads = 0
        var beats: [Beat] = []

        func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

        func activate(_ app: String?) {
            recorder.activate(app: app, at: clock.value, counters: counts, idleSeconds: idle)
        }

        /// `n` ticker seconds, one per second from the clock's time; keeps every beat that closes.
        func tick(_ n: Int = 1, _ presence: BeatPresence = .input, watched: Set<String>? = nil) {
            for _ in 0..<n {
                if let beat = recorder.tick(at: clock.value, presence: presence, watchedApps: watched,
                                            counters: { self.counterReads += 1; return self.counts },
                                            idleSeconds: { self.idle }) {
                    beats.append(beat)
                }
                clock.advance(1)
            }
        }
    }

    static func slice(_ app: String, _ seconds: Int, keys: Int = 0, clicks: Int = 0,
                      scrolls: Int = 0) -> BeatSlice {
        BeatSlice(app: app, seconds: seconds, keys: keys, clicks: clicks, scrolls: scrolls)
    }

    private static func closesOnGridEdge() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(20)
        rig.activate("B")
        rig.tick(10)
        expect(rig.beats.isEmpty, "no beat should close before the edge, got \(rig.beats.count)", &problems)
        rig.tick()
        expect(rig.beats.count == 1, "the tick on the edge should close one beat, got \(rig.beats.count)", &problems)
        guard let beat = rig.beats.first else { return problems }
        expect(beat.start == rig.start && beat.offset == 0, "the beat should open at the cell, got \(beat.start) +\(beat.offset)", &problems)
        expect(beat.slices == [slice("A", 20), slice("B", 10)], "slices should be A 20 s then B 10 s, got \(beat.slices)", &problems)
        expect(beat.end == rig.at(30), "the beat should end on the edge, got \(beat.end)", &problems)
        return problems
    }

    private static func inputLandsInItsSlice() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(20)
        rig.counts = CounterReading(keys: 12, clicks: 2, scrolls: 5)
        rig.activate("B")
        rig.tick(11)
        expect(rig.beats.first?.slices == [slice("A", 20, keys: 12, clicks: 2, scrolls: 5), slice("B", 10)],
               "A should hold the 12 keys, 2 clicks and 5 scrolls and B none, got \(String(describing: rig.beats.first?.slices))", &problems)
        return problems
    }

    private static func flickFoldsIntoNeighbour() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(12)
        rig.activate("B")
        rig.tick(3)
        rig.counts = CounterReading(keys: 0, clicks: 1, scrolls: 0)
        rig.activate("A")
        rig.tick(16)
        expect(rig.beats.first?.slices == [slice("A", 30, clicks: 1)],
               "the 3 s flick should fold into one A slice of 30 s with its click, got \(String(describing: rig.beats.first?.slices))", &problems)

        // A short slice that comes first folds into the one after it; a lone short slice stays.
        let first = Rig()
        first.activate("A")
        first.tick(3)
        first.activate("B")
        first.tick(28)
        expect(first.beats.first?.slices == [slice("B", 30)], "a leading flick should fold forward, got \(String(describing: first.beats.first?.slices))", &problems)
        let lone = Rig()
        lone.clock.value = lone.at(27)
        lone.activate("A")
        lone.tick(4)
        expect(lone.beats.first?.slices == [slice("A", 3)], "a beat's only slice should be kept, got \(String(describing: lone.beats.first?.slices))", &problems)
        return problems
    }

    private static func syntheticInputIsDiscarded() -> [String] {
        var problems: [String] = []
        for (idle, keys) in [(31.0, 0), (30.0, 0), (29.0, 40)] {
            let rig = Rig()
            rig.activate("A")
            rig.tick(30)
            rig.counts = CounterReading(keys: 40, clicks: 0, scrolls: 0)
            rig.idle = idle
            rig.tick()
            expect(rig.beats.first?.slices == [slice("A", 30, keys: keys)],
                   "with the idle clock at \(idle) s the 30 s slice should keep \(keys) keys, got \(String(describing: rig.beats.first?.slices))", &problems)
        }
        return problems
    }

    private static func presenceIsTheMajority() -> [String] {
        var problems: [String] = []
        for (quiet, watched, expected) in [(18, 12, BeatPresence.quiet), (15, 15, .watched)] {
            let rig = Rig()
            rig.tick(quiet, .quiet)
            rig.tick(watched, .watched)
            rig.tick(1, .input)
            expect(rig.beats.first?.presence == expected,
                   "\(quiet) quiet and \(watched) watched ticks should read \(expected), got \(String(describing: rig.beats.first?.presence))", &problems)
        }
        return problems
    }

    private static func sleepIsNotOneSlice() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(11)
        rig.clock.value = rig.at(3_610)
        rig.tick(21)
        expect(rig.beats.count == 2, "the gap and the next edge should each close a beat, got \(rig.beats.count)", &problems)
        guard rig.beats.count == 2 else { return problems }
        let cut = rig.beats[0], resumed = rig.beats[1]
        expect(cut.end == rig.at(10) && cut.slices == [slice("A", 10)], "the cut beat should end at the last tick, got \(cut.end) \(cut.slices)", &problems)
        expect(resumed.start == Beat.gridStart(for: rig.at(3_610)) && resumed.offset == 10,
               "the next beat should open in its own cell at +10, got \(resumed.start) +\(resumed.offset)", &problems)
        expect(resumed.slices == [slice("A", 20)] && resumed.end == rig.at(3_630), "the next beat should hold 20 s to its edge, got \(resumed.slices)", &problems)
        return problems
    }

    private static func countersReadAtEdgesOnly() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(91)  // ninety seconds on: the 91st tick lands on the third edge
        expect(rig.counterReads == 4, "one baseline and three closes should read the counters 4 times, got \(rig.counterReads)", &problems)
        expect(rig.beats.count == 3, "three beats should have closed, got \(rig.beats.count)", &problems)
        return problems
    }

    private static func midCellStartKeepsTimes() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.clock.value = rig.at(17)
        rig.activate("A")
        rig.tick(14)
        guard let beat = rig.beats.first else { return ["a tick on the edge should close the late beat"] }
        expect(beat.start == rig.start && beat.offset == 17, "the beat should start at +17 of its cell, got \(beat.start) +\(beat.offset)", &problems)
        expect(beat.slices == [slice("A", 13)] && beat.end == beat.start.addingTimeInterval(30),
               "the slices should total 13 s and the beat end on the edge, got \(beat.slices) ending \(beat.end)", &problems)
        return problems
    }

    private static func wrappedCounterCounts() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.counts = CounterReading(keys: UInt32.max - 2, clicks: UInt32.max, scrolls: 0)
        rig.activate("A")
        rig.tick(30)
        rig.counts = CounterReading(keys: 5, clicks: 0, scrolls: 0)
        rig.tick()
        expect(rig.beats.first?.slices == [slice("A", 30, keys: 8, clicks: 1)],
               "a counter past 2^32 should still count 8 keys and 1 click, got \(String(describing: rig.beats.first?.slices))", &problems)
        return problems
    }

    private static func holdersKept() -> [String] {
        var problems: [String] = []
        func closed(watched: [Set<String>?]) -> Beat? {
            let rig = Rig()
            for set in watched { rig.tick(10, .watched, watched: set) }
            rig.tick()
            return rig.beats.first
        }
        let unread = closed(watched: [nil, nil, nil])
        expect(unread?.watchedApps == nil, "no holder read should stay unknown, got \(String(describing: unread?.watchedApps))", &problems)
        let none = closed(watched: [nil, [], nil])
        expect(none?.watchedApps == [], "a read with no holders should be [], got \(String(describing: none?.watchedApps))", &problems)
        let held = closed(watched: [["c"], ["b", "a"], []])
        expect(held?.watchedApps == ["a", "b"],
               "the last non-empty holder set should be kept, sorted, got \(String(describing: held?.watchedApps))", &problems)
        return problems
    }

    private static func stopHandsBackPartial() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        expect(rig.recorder.stop(at: rig.clock.value, counters: rig.counts, idleSeconds: 0) == nil,
               "stopping with nothing open should return no beat", &problems)
        rig.activate("A")
        rig.tick(10, .watched, watched: ["w"])
        rig.counts = CounterReading(keys: 4, clicks: 0, scrolls: 0)
        let partial = rig.recorder.stop(at: rig.clock.value, counters: rig.counts, idleSeconds: 0)
        expect(partial?.slices == [slice("A", 10, keys: 4)] && partial?.end == rig.at(10),
               "the partial beat should hold the 10 s so far, got \(String(describing: partial))", &problems)
        expect(partial?.presence == .watched && partial?.watchedApps == ["w"],
               "the partial beat should keep the presence and holders seen so far, got \(String(describing: partial))", &problems)
        rig.tick(21)
        expect(rig.beats.first?.offset == 10 && rig.beats.first?.slices == [slice("A", 20)],
               "recording again in the same cell should open a fresh beat at +10, got \(String(describing: rig.beats.first))", &problems)
        return problems
    }

    private static func changeAfterGapOrEdge() -> [String] {
        var problems: [String] = []
        let late = Rig()
        late.activate("A")
        late.tick(30)
        late.activate("B")  // lands on the edge, before the tick that closes the beat
        late.tick(31)
        expect(late.beats.first?.slices == [slice("A", 30)], "the beat should keep A to its edge, got \(String(describing: late.beats.first?.slices))", &problems)
        expect(late.beats.count == 2 && late.beats[1].slices == [slice("B", 30)], "B should open the next beat, got \(late.beats.count) beats", &problems)

        let slept = Rig()
        slept.activate("A")
        slept.tick(11)
        slept.clock.value = slept.at(3_610)
        slept.activate("B")  // wake: the app change arrives before the ticker resumes
        slept.tick(21)
        expect(slept.beats.first?.slices == [slice("A", 10)], "A should end at the last tick, not at the wake, got \(String(describing: slept.beats.first?.slices))", &problems)
        expect(slept.beats.count == 2 && slept.beats[1].slices == [slice("B", 20)], "B should open after the gap, got \(slept.beats.count) beats", &problems)
        return problems
    }
}
