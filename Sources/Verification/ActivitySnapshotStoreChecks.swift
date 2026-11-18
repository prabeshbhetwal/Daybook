import Foundation

/// The store's side: the row's phases, the snapshot sweep, and what they leave alone.
extension ActivitySnapshotChecks {
    typealias Rig = ActivityEvidenceStoreChecks.Rig

    @MainActor
    static func rig(session: Bool = false, auto: Bool = false, ticker: Bool = false,
                    metadata: SessionMetadataArchive? = nil) -> Rig? {
        ActivityEvidenceStoreChecks.rig(session: session, auto: auto, ticker: ticker, metadata: metadata)
    }

    /// The row the day shows for the session under way.
    @MainActor
    static func liveSession(_ r: Rig) -> DaySession? {
        let entries = SessionDigest.entries(records: r.engine.archive.records, running: r.store.runningThread(),
                                            now: r.clock.value, day: r.clock.value)
        for case .session(let session) in entries { return session }
        return nil
    }

    /// An ended record with its beats.
    @MainActor
    static func endedRecord(_ r: Rig, from start: Date = t0, seconds: Int = 600) -> SessionRecord {
        let ended = record(from: start, seconds: TimeInterval(seconds))
        beats(r.evidence.archive, from: start, seconds: seconds)
        r.engine.archive.append(ended)
        return ended
    }

    static func kept(_ r: Rig, _ record: SessionRecord) -> SessionActivityShape? {
        MainActor.assumeIsolated { r.store.metadataArchive.metadata(for: record.id)?.activityShape }
    }

    static func phasesReachTheRow() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.activate(coding)
            r.run(1_800) { _ in r.keys.value &+= 3 }
            guard let session = liveSession(r) else { return ["the running session has no row"] }
            let phases = r.store.storySessionDetail(session, on: session.start).phases
            expect(phases?.label == .activity(.coding), "thirty minutes of typing in a code editor read as coding, got \(String(describing: phases?.label))", &problems)
            expect(phases?.fidelity == .beats && phases?.signals.isEmpty == true,
                   "from beats, with no signal claimed, got \(String(describing: phases?.fidelity)) \(String(describing: phases?.signals))", &problems)
            r.store.stop()
            guard let ended = liveSession(r) else { return problems + ["the ended session has no row"] }
            let after = r.store.storySessionDetail(ended, on: ended.start).phases
            expect(after?.label == .activity(.coding), "and the same once it has ended, got \(String(describing: after?.label))", &problems)
            return problems
        }
    }

    static func writtenOnceRewrittenOnChange() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = endedRecord(r)
            r.store.writeActivitySnapshots()
            let written = r.store.metadataArchive.revision
            expect(written > 0, "a first sweep writes the snapshot", &problems)
            let first = kept(r, ended)
            expect(first?.bounds == DateInterval(start: ended.start, end: ended.end) && first?.countedSeconds == 600
                    && first?.signals.isEmpty == true && first?.fidelity == .beats,
                   "over the record's own bounds and counted time, with no signal, got \(String(describing: first?.bounds)) \(String(describing: first?.countedSeconds))", &problems)
            r.store.writeActivitySnapshots()
            r.store.writeActivitySnapshots()
            expect(r.store.metadataArchive.revision == written, "sweeping again writes nothing", &problems)

            var shorter = ended
            shorter.end = ended.end.addingTimeInterval(-60)
            shorter.workSeconds = 540
            expect(r.engine.archive.edit(removing: [ended], adding: [shorter]) == nil, "the record's end is edited", &problems)
            r.store.writeActivitySnapshots()
            expect(r.store.metadataArchive.revision == written + 1 && kept(r, shorter)?.bounds.end == shorter.end,
                   "a changed end writes a second snapshot with the new bounds, got revision \(r.store.metadataArchive.revision)", &problems)

            let old = shape(.activity(.coding), credited: ["coding": 540], over: DateInterval(start: shorter.start, end: shorter.end),
                            version: 0)
            r.store.metadataArchive.saveActivityShape(old, for: shorter.id)
            r.evidence.settled.removeAll()   // as after a relaunch: the record itself has not changed
            r.store.writeActivitySnapshots()
            expect(kept(r, shorter)?.algorithmVersion == ActivityConstants.algorithmVersion,
                   "a snapshot of an earlier version is written again, got \(String(describing: kept(r, shorter)?.algorithmVersion))", &problems)
            return problems
        }
    }

    static func snapshotIsTheRecord() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = endedRecord(r)
            let session = daySession([ended])
            let fromBeats = r.store.sessionActivity(for: session)
            expect(fromBeats?.fidelity == .beats && fromBeats?.credited["coding"] == 600, "with its beats it reads them, got \(String(describing: fromBeats?.credited))", &problems)
            r.store.writeActivitySnapshots()
            guard let stored = kept(r, ended) else { return problems + ["no snapshot was written"] }
            r.evidence.archive.prune(olderThan: 0, now: t0.addingTimeInterval(3 * 86_400))
            r.evidence.memo.removeAll()
            expect(r.evidence.archive.beats(in: DateInterval(start: t0, duration: 600)).isEmpty, "every beat is gone", &problems)
            expect(r.store.sessionActivity(for: session) == stored, "the snapshot is what the session reads", &problems)
            return problems
        }
    }

    static func appsOnlyWhenNothingElse() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = record(from: t0, seconds: 600)
            r.engine.archive.append(ended)
            r.store.usage = SelfTest.makeUsageArchive(r.clock, sessions: [
                AppUsageSession(bundleID: coding, appName: "Xcode", start: t0, end: t0.addingTimeInterval(600))])
            let session = daySession([ended])
            let phases = r.store.storySessionDetail(session, on: session.start).phases
            expect(phases?.fidelity == .appsOnly, "no beats and no snapshot read the apps, got \(String(describing: phases?.fidelity))", &problems)
            expect(phases?.credited["coding"] == 600 && phases?.label == .activity(.coding),
                   "as coding, got \(String(describing: phases?.credited)) \(String(describing: phases?.label))", &problems)
            expect(r.store.sessionActivity(for: session)?.fidelity == .appsOnly, "the same without the row", &problems)
            return problems
        }
    }

    /// A record from half an hour before midnight to half an hour after, its beats in two day files.
    static func beganBeforeTheOldestDay() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: t0)
            let start = calendar.date(byAdding: .minute, value: -30, to: midnight) ?? midnight
            let ended = endedRecord(r, from: start, seconds: 3_600)
            let stored = shape(.activity(.design), credited: ["design": 3_000], over: DateInterval(start: ended.start, end: ended.end))
            r.store.metadataArchive.saveActivityShape(stored, for: ended.id)
            let session = daySession([ended])
            expect(r.store.sessionActivity(for: session)?.label == .activity(.coding), "with both days kept it reads its beats", &problems)
            r.evidence.archive.prune(olderThan: 0, now: midnight.addingTimeInterval(3_600))
            r.evidence.memo.removeAll()
            let left = r.evidence.archive.beats(in: DateInterval(start: ended.start, end: ended.end))
            expect(left.count == 60 && left.allSatisfy { $0.start >= midnight },
                   "the day before is gone and the half after midnight is not, got \(left.count) beats", &problems)
            expect(r.store.sessionActivity(for: session) == stored,
                   "the half that is left is not read as the session: its snapshot is, got \(String(describing: r.store.sessionActivity(for: session)?.label))", &problems)
            return problems
        }
    }

    static func severalRecordsJoin() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let thread = UUID()
            let first = record(from: t0, seconds: 600, thread: thread)
            let second = record(from: t0.addingTimeInterval(900), seconds: 600, thread: thread)
            r.engine.archive.append(first)
            r.engine.archive.append(second)
            let session = daySession([first, second])
            // Beats run through the five minutes between the stretches too: only the stretches count.
            beats(r.evidence.archive, from: t0, seconds: 1_500)
            let live = r.store.sessionActivity(for: session)
            expect(live?.credited["coding"] == 1_200 && live?.countedSeconds == 1_200,
                   "beats read the stretches as one session and credit nothing between them, got \(String(describing: live?.credited)) \(String(describing: live?.countedSeconds))", &problems)
            r.evidence.archive.prune(olderThan: 0, now: t0.addingTimeInterval(3 * 86_400))
            r.evidence.memo.removeAll()
            let one = shape(.activity(.coding), credited: ["coding": 600], over: DateInterval(start: first.start, end: first.end))
            let two = shape(.activity(.design), credited: ["design": 700], over: DateInterval(start: second.start, end: second.end))
            r.store.metadataArchive.saveActivityShape(one, for: first.id)
            expect(r.store.sessionActivity(for: session)?.fidelity == .appsOnly,
                   "with a snapshot for only one record the session reads its apps", &problems)
            r.store.metadataArchive.saveActivityShape(two, for: second.id)
            expect(r.store.sessionActivity(for: session) == SessionActivityShape.joined([one, two]),
                   "with both it reads them as one", &problems)
            return problems
        }
    }

    static func runningTrailsByABeat() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.activate(coding)
            r.run(100) { _ in r.keys.value &+= 3 }
            guard let session = liveSession(r) else { return ["the running session has no row"] }
            let credited = r.store.sessionActivity(for: session)?.credited["coding"] ?? 0
            expect(r.beats.count == 3 && abs(credited - 90) < 1,
                   "100 seconds in, three beats have closed and 90 seconds are credited, got \(r.beats.count) and \(credited)", &problems)
            return problems
        }
    }

    static func memoKey() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = endedRecord(r)
            let session = daySession([ended])
            let sentinel = shape(.mixed, credited: [:], over: DateInterval(start: t0, duration: 1))
            func ask() -> SessionActivityShape? { r.store.sessionActivity(for: session) }
            // The row's stamp is dropped too, so what is asked of is the memo behind it.
            func plant() {
                r.evidence.memo[SessionActivityMemoKey(session)]?.shape = sentinel
                r.evidence.stamped[SessionActivityMemoKey(session)] = nil
            }
            let real = ask()
            plant()
            expect(ask() == sentinel, "asked again with nothing changed, the kept one is read", &problems)
            beats(r.evidence.archive, from: t0.addingTimeInterval(3_600), seconds: 60)
            expect(ask() == sentinel, "a beat that lands in another session changes nothing", &problems)
            try? r.evidence.archive.append(Beat(start: t0, offset: 5, slices: [BeatSlice(app: coding, seconds: 5, keys: 1, clicks: 0, scrolls: 0)],
                                                presence: .input))
            expect(ask() != sentinel && real?.fidelity == .beats, "a beat that lands inside it is read in", &problems)
            plant()
            var paused = ended
            paused.pausedSpans = [DateInterval(start: t0.addingTimeInterval(300), duration: 60)]
            paused.workSeconds = 540
            expect(r.engine.archive.edit(removing: [ended], adding: [paused]) == nil, "a pause is edited", &problems)
            let edited = ask()
            expect(edited != sentinel && edited?.countedSeconds == 540,
                   "with the same beats, a moved pause is read in, got \(String(describing: edited?.countedSeconds))", &problems)
            if let entry = r.evidence.memo[SessionActivityMemoKey(session)] {
                let old = SessionActivityKey(bounds: entry.key.bounds, counted: entry.key.counted, beats: entry.key.beats,
                                             algorithmVersion: 0, isRunning: entry.key.isRunning,
                                             countsWhileWatching: entry.key.countsWhileWatching,
                                             overridesDigest: entry.key.overridesDigest)
                r.evidence.memo[SessionActivityMemoKey(session)] = SessionActivityMemo(key: old, shape: sentinel)
                r.evidence.stamped[SessionActivityMemoKey(session)] = nil
            }
            expect(ask() != sentinel, "and so is a change of the rules' version", &problems)
            return problems
        }
    }

    static func twentyPerSweep() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let all = (0..<25).map { endedRecord(r, from: t0.addingTimeInterval(TimeInterval($0 * 180)), seconds: 120) }
            func withShape() -> [Int] { all.indices.filter { kept(r, all[$0]) != nil } }
            r.store.writeActivitySnapshots()
            expect(withShape() == Array(5..<25), "a sweep writes 20, the newest, got \(withShape())", &problems)
            r.store.writeActivitySnapshots()
            expect(withShape() == Array(0..<25), "and the next the rest, got \(withShape())", &problems)
            return problems
        }
    }
}
