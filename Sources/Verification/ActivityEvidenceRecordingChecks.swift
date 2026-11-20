import Foundation

/// The store writes beats from its ticker. The rig moves the clock by hand, keeps the beats in a
/// scratch folder, and reads the input counters and the idle clock from boxes, so a beat's contents
/// follow from the script alone. A tick runs, then the clock moves a second: a beat that began on
/// its grid edge closes on the tick that reaches the next one.
extension ActivityEvidenceStoreChecks {
    typealias Box = BreakStoreChecks.Box

    struct Rig {
        let store: SessionStore
        let engine: SessionEngine
        let clock: TestClock
        let persistence: PersistenceStore
        let evidence: ActivityEvidence
        /// Seconds since the last input: 0 is typing, 600 is nobody there.
        let idle: Box<TimeInterval>
        let keys: Box<UInt32>
        /// How many times the counters were read.
        let reads: Box<Int>
        /// The app a break or a wake finds in front.
        let front: Box<BreakStoreChecks.Front?>
        /// Whether the display is awake: a person at the keys is only seen on a display that is.
        let awake: Box<Bool>
        let suite: String

        func close() { MemoryDefaults.remove(named: suite) }

        /// A tick, then a second; `each` runs first with the tick's number.
        func run(_ ticks: Int, each: (Int) -> Void = { _ in }) {
            for number in 0..<ticks { each(number); store.runTick(); clock.advance(1) }
        }

        func activate(_ bundleID: String?) {
            _ = store.handleApplicationActivation(bundleID: bundleID, name: bundleID ?? "None")
        }

        /// For a failure message: the engine's state and each beat's slices and presence.
        var described: String {
            "\(engine.state): " + beats.map { beat in
                "\(beat.presence) " + beat.slices.map { "\($0.app) \($0.seconds) s" }.joined(separator: ", ")
            }.joined(separator: "; ")
        }

        var beats: [Beat] {
            let year: TimeInterval = 365 * 86_400
            return evidence.archive.beats(in: DateInterval(start: clock.value.addingTimeInterval(-year),
                                                           end: clock.value.addingTimeInterval(year)))
        }
    }

    /// The first tick falls on a grid edge. `session` begins one before the store is built, as the
    /// store reads the engine's state once at start, `sessionAge` seconds before that edge: a break
    /// begun in a session too short to record leaves none behind. Automatic sessions are off unless `auto`.
    /// The display is awake unless `awake` says otherwise, whatever the Mac running the checks is doing.
    @MainActor
    static func rig(session: Bool = true, sessionAge: TimeInterval = 0, auto: Bool = false,
                    idle idleSeconds: TimeInterval = 0, awake displayAwake: Bool = true,
                    beatsDirectory: URL? = nil, ticker: Bool = false, tracker withTracker: Bool = false,
                    metadata: SessionMetadataArchive? = nil, journal: (() -> String?)? = nil,
                    countsInput: Bool = false) -> Rig? {
        let suite = "fc-selftest-evidence-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
        let clock = TestClock(Beat.gridStart(for: SelfTest.base))
        let persistence = PersistenceStore(defaults: defaults)
        persistence.autoSessionsEnabled = auto
        persistence.idlePauseThreshold = 120
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
        let engine = SessionEngine(store: persistence, archive: archive, ownBundleID: FocusConstants.bundleIdentifier,
                                   schedulesDwell: false, correctionWriteOverride: journal, now: { clock.value })
        if session {
            clock.advance(-sessionAge)
            engine.start(workType: .deepWork, intent: "Parser")
            clock.advance(sessionAge)
        }
        let idle = Box<TimeInterval>(idleSeconds), keys = Box<UInt32>(0), reads = Box(0)
        let front = Box<BreakStoreChecks.Front?>(nil), awake = Box(displayAwake)
        let evidence = ActivityEvidence(
            archive: BeatArchive(directory: beatsDirectory ?? SelfTest.scratchDirectory().appendingPathComponent("beats")),
            counters: InputCounters(keys: { reads.value += 1; return keys.value }, clicks: { 0 }, scrolls: { 0 }))
        let store = SessionStore(engine: engine, schedulesTicker: ticker, metadataArchive: metadata,
                                 activityEvidence: evidence,
                                 now: { clock.value },
                                 idle: IdleMonitor(idleSeconds: { idle.value },
                                                   inputCount: countsInput ? { UInt64(keys.value) } : { nil }),
                                 readDisplayAwake: { awake.value }, frontmostApplication: { front.value })
        let usage = AppUsageArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
        if withTracker {
            // As the app has it: the tracker watching app use, which keeps the ticker going.
            store.attach(tracker: AppUsageTracker(archive: usage, ownBundleID: FocusConstants.bundleIdentifier,
                                                  idle: .disabled, now: { clock.value }), usage: usage)
        } else {
            store.usage = usage
        }
        return Rig(store: store, engine: engine, clock: clock, persistence: persistence, evidence: evidence,
                   idle: idle, keys: keys, reads: reads, front: front, awake: awake, suite: suite)
    }

    static func writesEveryThirtySeconds() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let start = Beat.gridStart(for: SelfTest.base)
            r.run(90)
            expect(r.beats.count == 2, "90 ticks close two beats, got \(r.beats.count)", &problems)
            r.run(1)
            let beats = r.beats
            expect(beats.count == 3, "the third closes on the 91st tick, got \(beats.count)", &problems)
            expect(beats.map(\.start) == [0, 30, 60].map { start.addingTimeInterval($0) },
                   "each beat is one grid cell, got \(beats.map { $0.start.timeIntervalSince(start) })", &problems)
            expect(beats.allSatisfy { $0.offset == 0 && $0.slices.map(\.seconds).reduce(0, +) == 30 },
                   "and holds its 30 seconds whole", &problems)
            return problems
        }
    }

    static func writesNothingWhenOff() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: false) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.run(91)
            expect(r.beats.isEmpty, "no session and automatic sessions off writes nothing, got \(r.beats.count)", &problems)
            expect(r.reads.value == 0, "and reads no counter, got \(r.reads.value) readings", &problems)
            r.persistence.autoSessionsEnabled = true
            r.run(91)
            expect(r.beats.count == 3 && r.beats.allSatisfy { $0.presence == .paused },
                   "automatic sessions on records an idle engine as paused, got \(r.beats.map(\.presence))", &problems)
            return problems
        }
    }

    static func endsOnceWhenRecordingStops() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.run(45)
            r.store.stop()
            r.run(1)
            let beats = r.beats
            expect(beats.count == 2 && beats.last?.slices.map(\.seconds) == [15],
                   "the partial beat is written when the session stops, got \(beats.map { $0.slices.map(\.seconds) })",
                   &problems)
            let reads = r.reads.value
            r.run(91)
            expect(r.reads.value == reads && r.beats.count == 2,
                   "and a stopped store reads nothing more and writes nothing more", &problems)
            return problems
        }
    }

    static func pausesAreWrittenAsPauses() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(idle: 600) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.store.readWatching = { WatchDetector.Reading(watching: true, keptAwake: false,
                                                           watchedApps: ["com.example.player"]) }
            r.run(91)
            expect(r.engine.state == .paused(reason: .watching), "the fixture is watching, got \(r.engine.state)", &problems)
            expect(r.beats.count == 3 && r.beats.allSatisfy { $0.presence == .watchPause },
                   "a watching pause is written as one, got \(r.beats.map(\.presence))", &problems)
            expect(r.beats.allSatisfy { $0.watchedApps == ["com.example.player"] }, "with its holders", &problems)
            guard let m = rig() else { return problems + ["could not create isolated preferences"] }
            defer { m.close() }
            m.store.togglePause()
            m.run(91)
            expect(m.engine.state == .paused(reason: .manual), "a pause by hand holds, got \(m.engine.state)", &problems)
            expect(m.beats.count == 3 && m.beats.allSatisfy { $0.presence == .paused },
                   "any other pause is written as paused, got \(m.beats.map(\.presence))", &problems)
            return problems
        }
    }

    static func appSwitchSplitsInput() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.activate("com.a")
            r.run(61) { tick in
                if tick == 10 { r.keys.value += 40; r.activate("com.b") }
                if tick == 25 { r.keys.value += 25 }
                // Daybook's own window in front is not an app the session was in.
                if tick == 40 { r.activate(FocusConstants.bundleIdentifier) }
            }
            let beats = r.beats
            expect(beats.first?.slices == [BeatSlice(app: "com.a", seconds: 10, keys: 40, clicks: 0, scrolls: 0),
                                           BeatSlice(app: "com.b", seconds: 20, keys: 25, clicks: 0, scrolls: 0)],
                   "an activation mid-beat gives two slices with their own counts, got \(String(describing: beats.first?.slices))",
                   &problems)
            expect(beats.count == 2 && beats.last?.slices.map(\.app) == ["com.b"] && beats.last?.slices.map(\.seconds) == [30],
                   "Daybook's own window does not split a beat, got \(beats.map { $0.slices.map(\.app) })", &problems)
            return problems
        }
    }

    static func launchSeedsTheFrontApp() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: false, auto: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            // The launch tells the engine and the tracker which app is in front, not the store.
            r.engine.transition(on: .appActivated(bundleID: "com.seed", name: "Seed"))
            r.run(31)
            expect(r.beats.first?.slices.map(\.app) == ["com.seed"],
                   "a beat names the app that was in front at launch, got \(String(describing: r.beats.first?.slices.map(\.app)))",
                   &problems)
            return problems
        }
    }

    static func resumeMovesToTheFrontApp() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let apps = [["com.a"], ["com.a", "com.b"], ["com.b"]]
            // The presence gate reads the real clock and the rig's is a fixed year, so a person is
            // confirmed with the real one; a confirmation dated by the rig reads as years of quiet.
            // A session long enough to be recorded: a break from a shorter one would end it.
            guard let r = rig(sessionAge: 1_200) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            // A break: activations are not delivered while it lasts, and the end reads the app in front.
            r.activate("com.a")
            r.run(95) { tick in
                if tick == 15 { r.store.startBreak(length: 300) }
                if tick == 20 { r.activate("com.b") }
                if tick == 35 { r.front.value = ("com.b", "B"); r.store.endBreak(); _ = r.store.confirmPresence(at: Date()) }
            }
            expect(r.beats.map { $0.slices.map(\.app) } == apps,
                   "after a break the seconds go to the app now in front, got \(r.described)", &problems)
            // A wake: the activation waits for the person, and is delivered when they are confirmed.
            guard let w = rig(sessionAge: 1_200) else { return problems + ["could not create isolated preferences"] }
            defer { w.close() }
            w.activate("com.a")
            w.run(95) { tick in
                if tick == 15 { w.store.noteMachineWake() }
                if tick == 20 { w.activate("com.b") }
                if tick == 35 { _ = w.store.confirmPresence(at: Date()) }
            }
            expect(w.beats.map { $0.slices.map(\.app) } == apps,
                   "after a wake the seconds go to the app now in front, got \(w.described)", &problems)
            return problems
        }
    }
}
