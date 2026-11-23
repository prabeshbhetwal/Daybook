import Foundation

/// What a beat says of the second it was cut from, and that recording it is only a record: it changes
/// nothing a session counts, and a failure to write it is never an alert.
extension ActivityEvidenceStoreChecks {
    private static let player = WatchDetector.Reading(watching: true, keptAwake: false,
                                                      watchedApps: ["com.example.player"])

    /// The first beat of 31 ticks with the Mac held at one idle time and one reading of what holds the
    /// screen, its display awake or asleep.
    private static func firstBeat(idle: TimeInterval, awake: Bool, holders: WatchDetector.Reading, ping: Bool)
        -> (beat: Beat?, problems: [String]) {
        MainActor.assumeIsolated { () -> (beat: Beat?, problems: [String]) in
            guard let r = rig(idle: idle, awake: awake) else { return (nil, ["could not create isolated preferences"]) }
            defer { r.close() }
            if ping { r.store.lastAgentPing = r.clock.value }
            r.store.readWatching = { holders }
            r.run(31)
            return (r.beats.first, [])
        }
    }

    static func presenceIsWhatTheSamplerRead() -> [String] {
        var problems: [String] = []
        let none = WatchDetector.Reading()
        let keptAwake = WatchDetector.Reading(watching: false, keptAwake: true, watchedApps: [])
        // A person at the keys, or an agent at work, is only seen on a display that is awake.
        let cases: [(String, Bool, TimeInterval, WatchDetector.Reading, Bool, BeatPresence, [String]?)] = [
            ("typing", true, 0, none, false, .input, nil),
            ("typing on a sleeping display", false, 0, none, false, .quiet, nil),
            ("half a minute of quiet", true, 30, none, false, .quiet, nil),
            ("a film", true, 100, player, false, .watched, ["com.example.player"]),
            ("an agent at work", true, 100, keptAwake, true, .agent, []),
            ("an agent at work on a sleeping display", false, 100, keptAwake, true, .quiet, []),
            ("keep-awake alone", true, 100, keptAwake, false, .quiet, []),
            ("quiet with nothing on screen", true, 100, none, false, .quiet, []),
        ]
        for (label, awake, idle, holders, ping, presence, watched) in cases {
            let got = firstBeat(idle: idle, awake: awake, holders: holders, ping: ping)
            problems += got.problems
            expect(got.beat?.presence == presence, "\(label) is written as \(presence), got \(String(describing: got.beat?.presence))", &problems)
            expect(got.beat?.watchedApps == watched, "\(label) writes holders \(String(describing: watched)), got \(String(describing: got.beat?.watchedApps))", &problems)
        }
        return problems
    }

    static func holdersAreUnreadUntilRead() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for (label, holders) in [("a film", player), ("nothing", WatchDetector.Reading())] {
                guard let r = rig() else { return ["could not create isolated preferences"] }
                defer { r.close() }
                r.store.readWatching = { holders }
                // Quiet from 10 s to 100 s: holders are read from the 60th second of quiet, mid-beat in the second beat.
                r.run(91) { r.idle.value = TimeInterval($0 + 10) }
                let beats = r.beats
                let read = holders.watching ? ["com.example.player"] : []
                expect(beats.count == 3 && beats[0].watchedApps == nil,
                       "\(label): in the first minute of quiet holders are written as not read, got \(beats.map(\.watchedApps))", &problems)
                expect(beats.count == 3 && beats[1].watchedApps == read && beats[2].watchedApps == read,
                       "\(label): from then on the reading is written, got \(beats.map(\.watchedApps))", &problems)
            }
            return problems
        }
    }

    /// 600 seconds of a session: typing, quiet long enough to pause it, typing, a film already holding
    /// the screen when the quiet begins, so the pause is a watching one, typing, a pause by hand, and
    /// quiet; apps switch throughout, one of them while paused and one of them Daybook's own window.
    /// Returns the pauses the engine was seen in.
    @discardableResult
    private static func runScript(_ r: Rig) -> Set<String> {
        let typing = [0..<60, 200..<240, 400..<420, 480..<490]
        let switches: [Int: String] = [10: "com.b", 20: "com.a", 30: FocusConstants.bundleIdentifier, 70: "com.b",
                                       250: "com.c", 330: "com.a", 410: "com.b", 440: "com.c", 500: "com.a"]
        var lastInput = 0
        var seen: Set<String> = []
        r.run(600) { t in
            if case .paused = r.engine.state { seen.insert("\(r.engine.state)") }
            if typing.contains(where: { $0.contains(t) }) { lastInput = t; r.keys.value &+= 3 }
            r.idle.value = TimeInterval(t - lastInput)
            if let app = switches[t] { r.activate(app) }
            if t == 235 { r.store.readWatching = { player } }
            if t == 400 { r.store.readWatching = { WatchDetector.Reading() } }
            if t == 430 || t == 470 { r.store.togglePause() }
        }
        return seen
    }

    /// Everything a session counts and shows, with the random identities taken out.
    private static func counted(_ r: Rig) -> [String] {
        var snapshot = r.engine.snapshot()
        snapshot.activeRecordID = nil
        snapshot.threadID = nil
        snapshot.pendingDecisionID = nil
        let records = r.engine.archive.records.map { "\($0.workType.rawValue)=\($0.workSeconds)" }
        return ["\(snapshot)", "\(r.store.elapsed) \(r.store.threadElapsed)", "\(records)"]
    }

    static func recordingChangesNothingCounted() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let on = rig(), let off = rig(), let again = rig() else { return ["could not create isolated preferences"] }
            defer { on.close(); off.close(); again.close() }
            off.evidence.enabled = false
            again.evidence.enabled = false
            let paused = [on, off, again].map(runScript)
            let wanted = [PauseReason.idle, .watching, .manual].map { "\(SessionState.paused(reason: $0))" }
            for (run, seen) in zip(["recording", "unrecorded", "repeated"], paused) {
                expect(Set(wanted).isSubset(of: seen), "the \(run) run visits an idle, a watching and a manual pause, got \(seen.sorted())", &problems)
            }
            expect(on.beats.count >= 19, "the recording run wrote its beats, got \(on.beats.count)", &problems)
            expect(off.beats.isEmpty && off.reads.value == 0, "the other run recorded nothing", &problems)
            expect(counted(off) == counted(again), "the script repeats exactly without recording", &problems)
            let names = ["the saved state", "the clocks", "the records"]
            for (name, (with, without)) in zip(names, zip(counted(on), counted(off))) {
                expect(with == without, "recording changes \(name): \(with) against \(without)", &problems)
            }
            expect(on.engine.pausedSpansSoFar(until: on.clock.value) == off.engine.pausedSpansSoFar(until: off.clock.value),
                   "recording changes the pauses", &problems)
            return problems
        }
    }

    static func failedWriteIsDropped() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // A file where the folder for the day files should be: every append fails.
            let blocked = SelfTest.scratchDirectory()
            _ = FileManager.default.createFile(atPath: blocked.path, contents: Data())
            ActivityEvidence.loggedAppendFailure = false
            guard let r = rig(beatsDirectory: blocked), let ok = rig() else { return ["could not create isolated preferences"] }
            defer { r.close(); ok.close() }
            r.run(91)
            ok.run(91)
            expect(ActivityEvidence.loggedAppendFailure, "a failed write is logged", &problems)
            expect(!ActivityEvidence.noteAppendFailure(CocoaError(.fileWriteUnknown)), "and only once a launch", &problems)
            expect(r.beats.isEmpty, "the beat is dropped", &problems)
            expect(r.engine.state == .running && r.store.elapsed == ok.store.elapsed,
                   "the session carries on as if it had been written", &problems)
            expect(r.store.correctionError == nil && r.store.activityAutomationError == nil && r.store.powerMetadataError == nil,
                   "and nothing is raised", &problems)
            return problems
        }
    }

    static func prunesOncePerDay() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let day: TimeInterval = 86_400
            func beat(daysAgo: Double) -> Beat {
                Beat(start: Beat.gridStart(for: r.clock.value.addingTimeInterval(-daysAgo * day)),
                     slices: [BeatSlice(app: "com.old", seconds: 30, keys: 0, clicks: 0, scrolls: 0)], presence: .quiet)
            }
            try? r.evidence.archive.append(beat(daysAgo: 100))
            try? r.evidence.archive.append(beat(daysAgo: 10))
            // The store's first refresh has already pruned today, before these were written; as a day no refresh began.
            r.evidence.lastPruneDay = nil
            r.run(1)
            expect(r.beats.filter { $0.start < r.clock.value.addingTimeInterval(-90 * day) }.isEmpty,
                   "the first tick of the day removes beats past their retention", &problems)
            expect(r.beats.contains { $0.start < r.clock.value.addingTimeInterval(-9 * day) },
                   "and keeps the rest", &problems)
            try? r.evidence.archive.append(beat(daysAgo: 100))
            r.run(5)
            expect(r.beats.contains { $0.start < r.clock.value.addingTimeInterval(-90 * day) },
                   "later ticks of the same day leave the files alone", &problems)
            r.clock.advance(day)
            r.run(1)
            expect(r.beats.filter { $0.start < r.clock.value.addingTimeInterval(-90 * day) }.isEmpty,
                   "the first tick of the next day removes them", &problems)
            return problems
        }
    }
}
