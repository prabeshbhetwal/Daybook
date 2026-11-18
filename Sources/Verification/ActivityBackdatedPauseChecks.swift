import Foundation

/// The engine backdates an idle or watching pause to the last keypress, after the beats since have
/// been written as quiet. Credit follows the counted time the engine keeps, never the beats'
/// presence, so those quiet minutes earn nothing, and the snapshot written at the end says the same.
extension ActivitySnapshotChecks {
    static let backdatedPauseTests: [(String, () -> [String])] = [
        ("A pause the engine backdates earns no credit, end to end", backdatedPauseEarnsNothing),
        ("A pause answered as work after all is counted in the snapshot written for it", correctedPauseIsCounted),
        ("A corrected pause rewrites the snapshot with the new counted time", movedPauseRewrites),
    ]

    private static let browser = "com.google.Chrome"

    /// Five minutes of typing in the code editor, then quiet, with the idle pause at ten minutes: the engine
    /// pauses a ten minutes' quiet later, back to the last keypress. With `film`, a browser holds the screen
    /// from before the quiet begins and the person is looking at it, so the pause is a watching one.
    @MainActor
    private static func quietUntilPaused(_ r: Rig, film: Bool) {
        r.persistence.idlePauseThreshold = 600
        r.store.readWatching = {
            film ? WatchDetector.Reading(watching: true, keptAwake: false, watchedApps: [browser]) : WatchDetector.Reading()
        }
        r.activate(coding)
        var lastInput = 0
        r.run(1_000) { t in
            if t < 300 { lastInput = t; r.keys.value &+= 3 }
            if film && t == 300 { r.activate(browser) }
            r.idle.value = TimeInterval(t - lastInput)
        }
    }

    static func backdatedPauseEarnsNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for film in [false, true] {
                let label = film ? "a film in a browser" : "nothing on the screen"
                guard let r = rig(session: true) else { return ["could not create isolated preferences"] }
                defer { r.close() }
                quietUntilPaused(r, film: film)
                let wanted: SessionState = .paused(reason: film ? .watching : .idle)
                expect(r.engine.state == wanted, "\(label): the quiet pauses the session, got \(r.engine.state)", &problems)
                guard let session = liveSession(r) else { problems.append("\(label): no row"); continue }
                let live = r.store.sessionActivity(for: session)
                let coded = live?.credited["coding"] ?? 0
                expect(abs(coded - 300) <= 30, "\(label): five minutes of typing earn five minutes, got \(coded) of \(String(describing: live?.credited))", &problems)
                expect(abs((live?.countedSeconds ?? 0) - 300) <= 30, "\(label): and the counted time is five minutes, got \(String(describing: live?.countedSeconds))", &problems)
                expect(live?.credited["media"] == nil, "\(label): the browser earns nothing, got \(String(describing: live?.credited))", &problems)
                if film {
                    let held = live?.phases.contains { !$0.counted && $0.activity == .purpose(.media) } ?? false
                    expect(held, "the film is an uncounted media phase, got \(String(describing: live?.phases.map { "\($0.activity) \($0.counted)" }))", &problems)
                }
                r.store.stop()
                r.run(1)   // recording ends with the next tick, partial beat and all
                guard let ended = r.engine.archive.records.last else { problems.append("\(label): nothing was archived"); continue }
                r.store.writeActivitySnapshots()
                let stored = kept(r, ended)
                expect(abs((stored?.credited["coding"] ?? 0) - 300) <= 30 && abs((stored?.countedSeconds ?? 0) - 300) <= 30,
                       "\(label): the snapshot says the same, got \(String(describing: stored?.credited)) over \(String(describing: stored?.countedSeconds))", &problems)
            }
            return problems
        }
    }

    /// The stretch before an away is saved on any answer but "counted as focus"; asked about again, the
    /// away is answered as work and becomes a work record of its own, which is counted in full.
    static func correctedPauseIsCounted() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.clock.advance(600)
            r.engine.transition(on: .awayBegan(trigger: .screenLock))
            r.clock.advance(1_200)
            r.engine.transition(on: .awayEnded)
            guard case .awaitingUserDecision = r.engine.state else { return ["no away question was asked, got \(r.engine.state)"] }
            expect(r.store.resolve(.tookBreak), "the away is answered as a break", &problems)
            r.clock.advance(300)
            beats(r.evidence.archive, from: t0, seconds: 2_100)
            r.store.writeActivitySnapshots()
            func counted() -> Double {
                r.engine.archive.records.reduce(0) { $0 + (kept(r, $1)?.countedSeconds ?? 0) }
            }
            let before = counted()
            expect(abs(before - 600) <= 30, "only the work before the away is counted, got \(before)", &problems)
            expect(r.store.undoLastCorrection() && r.store.applyAwayDecision(.mergeTime, reviewing: true),
                   "the away is answered again, as work", &problems)
            r.store.writeActivitySnapshots()
            let after = counted()
            expect(after > before + 1_000, "the next sweep counts the away as work too, got \(after) after \(before)", &problems)
            return problems
        }
    }

    /// A pause inside a record that has ended can move while its bounds and its beats stay as they were:
    /// the archive's own edit, which is how a correction's Undo puts a record back. Pauses and work add up,
    /// as the engine writes them. (Undoing an Away answered as work is `undoneAwayIsRecounted`.)
    static func movedPauseRewrites() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = endedRecord(r)
            r.store.writeActivitySnapshots()
            expect(kept(r, ended)?.countedSeconds == 600, "the whole record counts, got \(String(describing: kept(r, ended)?.countedSeconds))", &problems)
            var moved = ended
            moved.pausedSpans = [DateInterval(start: t0.addingTimeInterval(300), duration: 120)]
            moved.workSeconds = 480
            expect(r.engine.archive.edit(removing: [ended], adding: [moved]) == nil, "a pause is added", &problems)
            let written = r.store.metadataArchive.revision
            r.store.writeActivitySnapshots()
            expect(r.store.metadataArchive.revision == written + 1 && kept(r, moved)?.countedSeconds == 480,
                   "the next sweep writes it again with two minutes less, got \(String(describing: kept(r, moved)?.countedSeconds))", &problems)
            expect(r.engine.archive.edit(removing: [moved], adding: [ended]) == nil, "the pause is given back as work", &problems)
            r.store.writeActivitySnapshots()
            expect(r.store.metadataArchive.revision == written + 2 && kept(r, ended)?.countedSeconds == 600,
                   "and the next with the larger counted time, got \(String(describing: kept(r, ended)?.countedSeconds))", &problems)
            return problems
        }
    }
}
