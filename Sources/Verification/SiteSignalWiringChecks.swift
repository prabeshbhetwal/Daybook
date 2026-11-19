import Foundation

/// A confirmed browser's site kind reaches the beats the store writes: asked for at an activation and at each
/// beat edge while recording, labelled by when it was asked, dropped once recording ends. Fakes only.
enum SiteSignalWiringChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A browser activated during a session gets its site kind", activationGetsKind),
        ("Each half-minute asks again while the browser stays in front", edgesAskAgain),
        ("Nothing is read when nothing is being recorded", nothingReadWhenNotRecording),
        ("An editor is never asked, nor a browser with no process to ask", editorNeverAsked),
        ("A session's snapshot lists the site signal only when its beats carry one", snapshotListsSignal),
        ("Stopping the session drops a late answer", stopDropsLateAnswer),
        ("A late answer labels the slice whole, or splits it where it arrives", lateAnswerWholeOrSplit),
        ("An answer for the browser never labels the app now in front", answerNamesItsApp),
        ("Ending the recording clears a browser's breaker", endClearsBreaker),
        ("A kept summary made without the signal is written again once its beats carry one", staleSummaryRewritten),
    ] + recordingTests

    typealias Rig = ActivityEvidenceStoreChecks.Rig
    static let chrome = SiteSignalChecks.chrome
    static let editor = "com.microsoft.VSCode"
    static let video = SiteAddressRead.address("https://www.youtube.com/watch?v=x")
    static let social = SiteAddressRead.address("https://www.reddit.com/")

    private static func activationGetsKind() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let w = wired() else { return ["could not create isolated preferences"] }
            defer { w.close() }
            w.fake.answer = video
            w.r.run(3)
            w.r.activate(chrome)
            w.r.run(28)
            let inChrome = w.slices.filter { $0.app == chrome }
            expect(w.r.beats.count == 1 && inChrome.map(\.seconds).reduce(0, +) >= 25 && inChrome.allSatisfy { $0.site == .video },
                   "the beat's Chrome seconds carry the kind, got \(w.slices)", &problems)
            expect(w.slices.filter { $0.app != chrome }.allSatisfy { $0.site == nil }, "and no other app's does", &problems)
            return problems
        }
    }

    private static func edgesAskAgain() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let w = wired() else { return ["could not create isolated preferences"] }
            defer { w.close() }
            w.fake.answer = video
            w.r.activate(chrome)
            w.r.run(90)
            expect(w.fake.asked.count == 3, "the first tick and two beat edges ask, got \(w.fake.asked.count)", &problems)
            w.r.run(1)
            expect(w.fake.asked.count == 4, "and the third edge asks again, got \(w.fake.asked.count)", &problems)
            let later = w.r.beats.dropFirst().flatMap(\.slices)
            expect(!later.isEmpty && later.allSatisfy { $0.site == .video }, "each beat after the first carries the kind, got \(later)", &problems)
            return problems
        }
    }

    private static func nothingReadWhenNotRecording() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let w = wired(session: false) else { return ["could not create isolated preferences"] }
            defer { w.close() }
            w.r.activate(chrome)
            w.r.run(91)
            w.r.store.requestSiteRead(app: chrome, at: w.r.clock.value)
            expect(w.fake.asked.isEmpty, "no session and automatic sessions off reads nothing, got \(w.fake.asked.count)", &problems)
            w.r.persistence.autoSessionsEnabled = true; w.r.activate(chrome)
            w.r.run(31)
            expect(!w.fake.asked.isEmpty, "with automatic sessions on the same browser is read", &problems)
            return problems
        }
    }

    private static func editorNeverAsked() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let w = wired() else { return ["could not create isolated preferences"] }
            defer { w.close() }
            w.r.activate(editor)
            w.r.run(91)
            expect(w.fake.asked.isEmpty, "an editor that is not listed is never asked, got \(w.fake.asked.count)", &problems)
            w.r.evidence.frontPID = { _ in nil }; w.r.activate(chrome)
            w.r.run(91)
            expect(w.fake.asked.isEmpty, "a browser with no process to ask is not read, got \(w.fake.asked.count)", &problems)
            w.r.evidence.frontPID = { _ in SiteSignalChecks.chromePID }
            w.r.run(31)
            expect(!w.fake.asked.isEmpty, "and is read at the next edge once its process is known", &problems)
            return problems
        }
    }

    private static func snapshotListsSignal() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for on in [true, false] {
                guard let w = wired(consented: on) else { return problems + ["could not create isolated preferences"] }
                defer { w.close() }
                w.fake.answer = video
                w.r.activate(chrome)
                w.r.run(100)
                guard let session = ActivitySnapshotChecks.liveSession(w.r) else {
                    problems.append("the running session has no row")
                    continue
                }
                let wanted: [SignalKind] = on ? [.siteKind] : []
                let signals = w.r.store.sessionActivity(for: session)?.signals
                expect(signals == wanted, "with the signal \(on ? "on" : "off") its shape lists \(String(describing: signals))", &problems)
                guard on, let key = w.r.evidence.memo[SessionActivityMemoKey(session)]?.key else { continue }
                // The memo is keyed on the signals: a shape worked out without them is read again.
                let sentinel = ActivitySnapshotChecks.shape(.mixed, credited: [:], over: DateInterval(start: ActivitySnapshotChecks.t0, duration: 1))
                let old = SessionActivityKey(bounds: key.bounds, counted: key.counted, beats: key.beats,
                                             algorithmVersion: key.algorithmVersion, isRunning: key.isRunning,
                                             countsWhileWatching: key.countsWhileWatching,
                                             overridesDigest: key.overridesDigest, signals: [])
                w.r.evidence.memo[SessionActivityMemoKey(session)] = SessionActivityMemo(key: old, shape: sentinel)
                expect(w.r.store.sessionActivity(for: session)?.signals == [.siteKind], "a memo made without the signal is not kept", &problems)
            }
            return problems
        }
    }

    private static func stopDropsLateAnswer() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // The read waits, or its answer is on its way, when the session stops; it lands while the
            // partial beat is still open, or after it was written.
            for (jobWaits, afterTick) in [(true, false), (false, false), (false, true)] {
                guard let w = wired() else { return problems + ["could not create isolated preferences"] }
                defer { w.close() }
                w.fake.answer = video
                w.r.run(3)
                if jobWaits { w.deferred = [] } else { w.held = [] }
                w.r.activate(chrome)
                w.r.run(10)
                w.r.store.stop()
                if !afterTick { w.runJobs(); w.deliver() }
                w.r.run(2)
                w.runJobs(); w.deliver()
                expect(w.slices.contains { $0.app == chrome && $0.seconds >= 5 } && w.slices.allSatisfy { $0.site == nil },
                       "a beat written after the stop carries a site (\(jobWaits), \(afterTick)), got \(w.slices)", &problems)
            }
            return problems
        }
    }

    private static func lateAnswerWholeOrSplit() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Asked at the activation, answered four seconds on: the slice began at the request, so it is whole.
            guard let a = wired() else { return ["could not create isolated preferences"] }
            defer { a.close() }
            a.fake.answer = video
            a.deferred = []; a.held = []
            a.r.run(3)
            a.r.activate(chrome)
            a.r.run(4)
            a.runJobs()
            a.deliver()
            a.r.run(24)
            let inChrome = a.slices.filter { $0.app == chrome }
            expect(inChrome.count == 1 && inChrome[0].seconds >= 27 && inChrome[0].site == .video,
                   "an answer four ticks late labels the whole slice, got \(a.slices)", &problems)
            // Asked 0.4 s past an edge, answered eight seconds in with another kind: the slice began before
            // the request, so it splits where the answer came.
            guard let b = wired() else { return problems + ["could not create isolated preferences"] }
            defer { b.close() }
            b.fake.answer = video
            b.r.activate(chrome)
            b.r.run(31)
            b.fake.answer = social
            b.deferred = []; b.held = []
            b.r.run(29)
            b.r.clock.advance(0.4)
            b.r.run(8)
            b.runJobs()
            b.deliver()
            b.r.run(23)
            let beats = b.r.beats
            expect(beats.count == 3 && beats[1].slices.allSatisfy { $0.site == .video },
                   "the second beat carries the first kind whole, got \(beats.map(\.slices))", &problems)
            let third = beats.last?.slices ?? []
            expect(third.map(\.site) == [.video, .social] && (7...9).contains(third.first?.seconds ?? 0)
                   && third.map(\.seconds).reduce(0, +) == 30,
                   "the third splits at the answer, the early seconds keeping the kind they had, got \(third)", &problems)
            return problems
        }
    }

    private static func answerNamesItsApp() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let w = wired() else { return ["could not create isolated preferences"] }
            defer { w.close() }
            w.fake.answer = video
            w.deferred = []
            w.r.run(3)
            w.r.activate(chrome)
            w.r.run(5)
            w.r.activate(editor)
            w.r.run(5)
            w.runJobs()
            w.r.run(20)
            expect(w.fake.asked.count == 1 && w.r.beats.count == 1,
                   "the editor coming to the front did not cancel the browser's read, got \(w.fake.asked.count)", &problems)
            expect(w.slices.allSatisfy { $0.site == nil }, "and its answer labelled no slice of the editor, got \(w.slices)", &problems)
            return problems
        }
    }

    private static func endClearsBreaker() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let w = wired() else { return ["could not create isolated preferences"] }
            defer { w.close() }
            w.fake.answer = .timedOut
            w.r.activate(chrome)
            w.r.run(61)
            expect(w.fake.asked.count == 2, "two timeouts stop the reads for the rest of the recording, got \(w.fake.asked.count)", &problems)
            w.r.store.stop()
            w.r.run(2)
            w.r.engine.start(workType: .deepWork, intent: "Parser")
            w.r.activate(chrome)
            w.r.run(2)
            expect(w.fake.asked.count == 3, "a new recording reads again, got \(w.fake.asked.count)", &problems)
            return problems
        }
    }

    private static func staleSummaryRewritten() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: false) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let t0 = ActivitySnapshotChecks.t0
            let record = ActivitySnapshotChecks.record(from: t0, seconds: 600, paused: nil)
            r.engine.archive.append(record)
            for step in 0..<20 {
                let slice = BeatSlice(app: chrome, seconds: 30, keys: 3, clicks: 0, scrolls: 0, site: .video)
                try? r.evidence.archive.append(Beat(start: t0.addingTimeInterval(TimeInterval(step * 30)), slices: [slice], presence: .input))
            }
            func sweep(planting planted: SessionActivityShape?) -> SessionActivityShape? {
                if let planted { _ = r.store.metadataArchive.saveActivityShape(planted, for: record.id) }
                r.evidence.settled = [:]
                r.store.writeActivitySnapshots()
                return ActivitySnapshotChecks.kept(r, record)
            }
            guard let first = sweep(planting: nil) else { return problems + ["no summary was written"] }
            expect(first.signals == [.siteKind], "a summary of beats that carry a site lists it, got \(first.signals)", &problems)
            func planted(_ signals: [SignalKind], credited: [String: TimeInterval]) -> SessionActivityShape {
                var copy = SessionActivityShape(algorithmVersion: first.algorithmVersion, fidelity: first.fidelity,
                                                bounds: first.bounds, countedSeconds: first.countedSeconds, signals: signals,
                                                phases: first.phases, depth: first.depth, label: first.label, credited: credited,
                                                fingerprint: first.fingerprint, splitCandidates: first.splitCandidates)
                copy.countsWhileWatching = first.countsWhileWatching
                copy.overridesDigest = first.overridesDigest
                return copy
            }
            let kept = sweep(planting: planted([.siteKind], credited: ["marker": 7]))
            expect(kept?.credited == ["marker": 7], "a current summary is left alone, got \(String(describing: kept?.credited))", &problems)
            let rewritten = sweep(planting: planted([], credited: ["marker": 9]))
            expect(rewritten?.signals == [.siteKind] && rewritten?.credited != ["marker": 9],
                   "one made without the signal is written again, got \(String(describing: rewritten?.signals))", &problems)
            return problems
        }
    }
}
