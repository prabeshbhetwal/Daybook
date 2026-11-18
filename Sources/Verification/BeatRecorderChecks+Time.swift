import Foundation

/// The beat recorder across clock steps, stalls and late ticks: time is recorded once, and
/// input is credited only to the slice that received it.
extension BeatRecorderChecks {
    static func clockStepBackRecordsNothingTwice() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(46)                    // +0 ... +45: one whole beat and 15 s of the next
        rig.clock.value = rig.at(15)    // the clock steps back 30 s, a beat
        rig.tick(46)                    // +15 ... +60: nothing opens until +45
        expect(shape(rig) == ["0+0:30", "30+0:15", "30+15:15"],
               "60 s of clock should be recorded once as 30 s, 15 s, 15 s from +45, got \(shape(rig))", &problems)
        return problems
    }

    static func clockCorrectedAfterADayAheadRecordsAtOnce() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(11)                    // +0 ... +10
        rig.clock.value = rig.at(86_400)
        rig.tick(11)                    // a clock a day ahead: +86 400 ... +86 410
        rig.clock.value = rig.at(20)    // corrected
        rig.tick(41)                    // +20 ... +60 are real time and must not wait for +86 410
        expect(shape(rig) == ["0+0:10", "86400+0:10", "0+20:10", "30+0:30"],
               "beats should resume at +20 once the clock is corrected, got \(shape(rig))", &problems)
        return problems
    }

    /// Each beat as "cell start + offset : seconds", the start in seconds from the grid start of the rig.
    private static func shape(_ rig: Rig) -> [String] {
        rig.beats.map { beat in
            "\(Int(beat.start.timeIntervalSince(rig.start)))+\(beat.offset):\(beat.slices.reduce(0) { $0 + $1.seconds })"
        }
    }

    static func inputInAGapIsNotTheSlicesOwn() -> [String] {
        var problems: [String] = []
        // (label, gap in s, keys that arrived, idle clock at the first tick back, keys the slice keeps)
        let cases: [(String, TimeInterval, UInt32, TimeInterval, Int)] = [
            ("wake keystrokes after a night", 3_600, 3, 0.5, 0),
            ("typing that stopped before a short stall", 3, 7, 9, 7),
        ]
        for (label, gap, keys, idle, kept) in cases {
            let rig = Rig()
            rig.activate("A")
            rig.tick(11)                // +0 ... +10
            rig.clock.value = rig.at(10 + gap)
            rig.counts = CounterReading(keys: keys, clicks: 0, scrolls: 0)
            rig.idle = idle
            rig.tick()
            expect(rig.beats.first?.slices == [slice("A", 10, keys: kept)],
                   "\(label) should leave \(kept) keys on the 10 s slice, got \(String(describing: rig.beats.first?.slices))", &problems)
        }
        return problems
    }

    static func skippedTimerFireKeepsTheTyping() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(11)                    // +0 ... +10, typing throughout
        rig.clock.value = rig.at(12.2)  // one timer fire skipped: the next tick is 2.2 s late
        rig.counts = CounterReading(keys: 40, clicks: 0, scrolls: 0)
        rig.idle = 0.3                  // a key a moment ago
        rig.tick()
        expect(rig.beats.first?.slices == [slice("A", 10, keys: 40)],
               "a 2.2 s hiccup should keep the 40 keys typed through it, got \(String(describing: rig.beats.first?.slices))", &problems)
        return problems
    }

    static func idleGuardCountsFromTheBaseline() -> [String] {
        var problems: [String] = []
        for (idle, kept) in [(29.5, 0), (28.5, 9)] {
            let rig = Rig()
            rig.activate("A")
            rig.tick(30)                // +0 ... +29
            rig.clock.value = rig.at(31)
            rig.tick()                  // the edge tick is a second late: the next baseline is read at +31
            rig.counts = CounterReading(keys: 9, clicks: 0, scrolls: 0)
            rig.idle = idle
            rig.tick(29)                // +32 ... +60: the slice's baseline is 29 s old, though it opened at +30
            expect(rig.beats.count == 2 && rig.beats[1].slices == [slice("A", 30, keys: kept)],
                   "with the idle clock at \(idle) s of a 29 s baseline the slice should keep \(kept) keys, got \(rig.beats.map(\.slices))", &problems)
        }
        return problems
    }

    static func stopAfterAGapEndsAtTheLastTick() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate("A")
        rig.tick(6)                     // +0 ... +5
        rig.clock.value = rig.at(3_600)
        let partial = rig.recorder.stop(at: rig.clock.value, counters: rig.counts, idleSeconds: 3_600)
        expect(partial?.end == rig.at(5) && partial?.slices == [slice("A", 5)],
               "a stop long after the last tick should end the beat at it, got \(String(describing: partial))", &problems)
        return problems
    }
}
