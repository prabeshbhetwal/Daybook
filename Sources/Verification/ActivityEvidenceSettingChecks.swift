import Foundation

/// When recording stops, and what stays out of reach of a backup: the "Record app use" setting, a quit,
/// a break that outlasts a wake, and the data folder's copy.
extension ActivityEvidenceStoreChecks {
    static func trackingOffRecordsNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let running = rig(), let waiting = rig(session: false, auto: true) else {
                return ["could not create isolated preferences"]
            }
            defer { running.close(); waiting.close() }
            for (label, r) in [("a session running", running), ("automatic sessions on and no session", waiting)] {
                r.persistence.isUsageTrackingEnabled = false
                r.run(91) { if $0 == 20 { r.activate("com.c") } }
                expect(r.beats.isEmpty && r.reads.value == 0,
                       "\(label), app use not recorded: no beat and no counter read, got \(r.beats.count) beats and \(r.reads.value) readings",
                       &problems)
                r.persistence.isUsageTrackingEnabled = true
                r.run(91)
                expect(r.beats.count == 3 && r.beats.first?.slices.map(\.app) == ["com.c"],
                       "\(label): recording resumes with the app that was in front, got \(r.described)", &problems)
            }
            return problems
        }
    }

    static func turningTrackingOffEndsOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.run(45)
            r.persistence.isUsageTrackingEnabled = false
            r.run(1)
            expect(r.beats.map { $0.slices.map(\.seconds) } == [[30], [15]],
                   "turning it off mid-run writes the partial beat, got \(r.described)", &problems)
            let reads = r.reads.value
            r.run(91)
            expect(r.reads.value == reads && r.beats.count == 2, "and nothing after it", &problems)
            r.persistence.isUsageTrackingEnabled = true
            r.run(91)
            expect(r.beats.count == 5, "turned on again, recording goes on, got \(r.beats.count) beats", &problems)
            return problems
        }
    }

    /// The store as the app has it, with a ticker of its own: turning the setting off can stop the ticker
    /// before any tick sees it, so recording has to end where the ticker does, or the next start keeps
    /// the app that was in front when it ended.
    static func tickerStopEndsRecording() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: false, auto: true, ticker: true, tracker: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.activate("com.a")
            expect(r.store.hasScheduledTicker, "app use being recorded keeps the ticker going", &problems)
            r.run(45)
            expect(r.evidence.recording, "and beats are being written", &problems)
            // Off through the tracker, so the store learns only that nothing needs its ticker now.
            r.persistence.isUsageTrackingEnabled = false
            r.store.tracker?.setEnabled(false)
            expect(!r.store.hasScheduledTicker && !r.evidence.recording,
                   "with it off the ticker stops, and recording ends with it", &problems)
            r.activate("com.c")
            r.persistence.isUsageTrackingEnabled = true
            r.store.tracker?.setEnabled(true)
            r.store.start()
            r.run(31)
            expect(r.beats.last?.slices.map(\.app) == ["com.c"],
                   "a session begun in the new app names it from its first beat, got \(r.described)", &problems)
            return problems
        }
    }

    static func settingOffEndsRecordingAtOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(ticker: true, tracker: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.run(45)
            r.store.setTrackingEnabled(false)
            expect(!r.evidence.recording && r.beats.map({ $0.slices.map(\.seconds) }) == [[30], [15]],
                   "turning it off writes the partial beat and ends recording before any tick, got \(r.described)",
                   &problems)
            return problems
        }
    }

    static func quitWritesThePartialBeat() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.run(45)
            r.store.endBeatRecording(at: r.clock.value)
            expect(r.beats.map { $0.slices.map(\.seconds) } == [[30], [15]],
                   "a quit writes the beat in progress, got \(r.described)", &problems)
            let reads = r.reads.value
            r.store.endBeatRecording(at: r.clock.value)
            expect(r.reads.value == reads && r.beats.count == 2, "and only once", &problems)
            return problems
        }
    }

    static func steppedBackClockReadsOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.run(45)
            // The recorder closes the beat it had and waits for time to pass what it wrote; the ticks
            // in between must not tell it the app in front again, each at the price of a counter reading.
            r.clock.advance(-10)
            let before = r.reads.value
            r.run(8)
            expect(r.reads.value - before <= 1, "a stepped-back clock costs one reading, got \(r.reads.value - before)", &problems)
            return problems
        }
    }

    static func waitingActivationIsNotDeliveredOnABreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(sessionAge: 1_200) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.activate("com.a")
            r.run(95) { tick in
                if tick == 15 { r.store.startBreak(length: 300) }
                if tick == 20 { r.store.noteMachineWake() }
                // It waits for the person; confirmed on the break, the engine drops it, so the beats do too.
                if tick == 22 { r.activate("com.b") }
                if tick == 25 { _ = r.store.confirmPresence(at: Date()) }
                if tick == 40 { r.front.value = ("com.a", "A"); r.store.endBreak(); _ = r.store.confirmPresence(at: Date()) }
            }
            expect(r.beats.map { $0.slices.map(\.app) } == [["com.a"], ["com.a"], ["com.a"]],
                   "an activation confirmed during a break is not recorded, got \(r.described)", &problems)
            return problems
        }
    }

    /// A store with no evidence handed to it keeps its beats in its own data folder, in `beats`; a
    /// backup of that folder leaves them out. Evidence expires; a copy in iCloud Drive would not.
    static func backupLeavesBeatsOut() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let suite = "fc-selftest-evidence-backup-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated preferences"] }
            defer { MemoryDefaults.remove(named: suite) }
            let clock = TestClock(Beat.gridStart(for: SelfTest.base))
            let data = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults),
                                       archive: SessionArchive(directory: data, now: { clock.value }),
                                       ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false,
                                       now: { clock.value })
            engine.start(workType: .deepWork, intent: "Parser")
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value },
                                     idle: IdleMonitor(idleSeconds: { 0 }), frontmostApplication: { nil })
            for _ in 0..<31 { store.runTick(); clock.advance(1) }
            try? Data("[]".utf8).write(to: data.appendingPathComponent("sessions.json"))
            let manager = FileManager.default
            let beats = data.appendingPathComponent(BeatArchive.folderName)
            expect(((try? manager.contentsOfDirectory(atPath: beats.path)) ?? []).count == 1,
                   "the store's beats go to a beats folder inside its data folder", &problems)
            guard let clone = try? DataBackup.clone(of: data) else { return problems + ["no clone was made"] }
            defer { try? manager.removeItem(at: clone) }
            expect(manager.fileExists(atPath: clone.appendingPathComponent("sessions.json").path),
                   "the backup's copy keeps the data", &problems)
            expect(!manager.fileExists(atPath: clone.appendingPathComponent(BeatArchive.folderName).path),
                   "and leaves the beats out", &problems)
            return problems
        }
    }
}
