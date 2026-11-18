import Foundation

/// What the first round of review found: a summary follows an undone Away answer, a sweep costs nothing
/// for records it has settled, a summary this build cannot read loses only itself, a stop waits for the
/// open beat, and a session over midnight is a row on each day.
extension ActivitySnapshotChecks {
    typealias Box = ActivityEvidenceStoreChecks.Box

    static let repairTests: [(String, () -> [String])] = [
        ("The heartbeat and the refresh after a stop write snapshots", heartbeatAndStopWrite),
        ("Writing and reading phases changes nothing a session counts", changesNothingCounted),
        ("An away answered as work and then undone is counted as the pause it was", undoneAwayIsRecounted),
        ("A record the sweep has looked at costs nothing until it changes", settledRecordsCostNothing),
        ("A sidecar that refuses the write is tried once for each record until it saves something", refusedWriteIsTriedOnce),
        ("A snapshot this build cannot read loses only itself", unreadableShapeLosesOnlyItself),
        ("A record that ended inside the open beat is written once the beat has closed, with all its seconds", snapshotWaitsForTheOpenBeat),
        ("A session over midnight is a row on each day, each with its own part of the snapshot", midnightRowsTakeTheirOwnPart),
        ("A caller that wants only the prose reads no beats", proseAloneReadsNoBeats),
    ]

    static func heartbeatAndStopWrite() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = endedRecord(r)
            r.run(59)
            expect(kept(r, ended) == nil, "nothing is written before the minute is up", &problems)
            r.run(1)
            expect(kept(r, ended) != nil, "the heartbeat writes it on the 60th tick", &problems)

            // As the app has it, the store schedules its own ticker: the stop ends recording, partial beat and all.
            guard let live = rig(session: true, ticker: true) else { return problems + ["could not create isolated preferences"] }
            defer { live.close() }
            live.activate(coding)
            live.run(100) { _ in live.keys.value &+= 3 }
            let before = live.store.metadataArchive.revision
            live.store.refresh()
            expect(live.store.metadataArchive.revision == before, "a refresh while it runs writes nothing", &problems)
            live.store.stop()
            let stopped = live.engine.archive.records.first
            let shape = stopped.flatMap { kept(live, $0) }
            expect(abs((shape?.credited["coding"] ?? 0) - 100) < 1,
                   "the refresh after it stops writes its snapshot, with no heartbeat and all 100 seconds, got \(String(describing: shape?.credited))", &problems)
            let revision = live.store.metadataArchive.revision
            live.store.refresh()
            expect(live.store.metadataArchive.revision == revision, "and only the one after", &problems)
            return problems
        }
    }

    static func changesNothingCounted() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.activate(coding)
            r.run(100) { _ in r.keys.value &+= 3 }
            func counted() -> [String] {
                ["\(r.engine.snapshot())", "\(r.store.elapsed) \(r.store.threadElapsed)",
                 "\(r.engine.archive.records)", "\(String(describing: r.engine.pausedSpansSoFar(until: r.clock.value)))"]
            }
            let names = ["the saved state", "the clocks", "the records", "the pauses"]
            let before = counted()
            if let session = liveSession(r) { _ = r.store.storySessionDetail(session, on: session.start) }
            r.store.writeActivitySnapshots()
            for (name, (was, now)) in zip(names, zip(before, counted())) {
                expect(was == now, "reading a running session's phases and sweeping changes \(name): \(was) against \(now)", &problems)
            }
            r.store.stop()
            let records = "\(r.engine.archive.records)"
            r.store.writeActivitySnapshots()
            expect("\(r.engine.archive.records)" == records, "nor does writing the snapshot of the one that ended", &problems)
            return problems
        }
    }

    /// Typing, then a long away answered "I was working", then typing; the beats are as the recorder wrote them
    /// (the away as paused, since the engine had paused for it). Undo lowers the record's work and leaves its
    /// pauses, so they no longer add up to it and the beats say what was paused.
    static func undoneAwayIsRecounted() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.clock.advance(600)
            r.engine.transition(on: .awayBegan(trigger: .screenLock))
            r.clock.advance(1_200)
            r.engine.transition(on: .awayEnded)
            guard case .awaitingUserDecision = r.engine.state else { return ["no away question was asked, got \(r.engine.state)"] }
            expect(r.store.resolve(.mergeTime), "the away is answered as work", &problems)
            r.clock.advance(300)
            beats(r.evidence.archive, from: t0, seconds: 600)
            beats(r.evidence.archive, from: t0.addingTimeInterval(600), seconds: 1_200, keys: 0, presence: .paused)
            beats(r.evidence.archive, from: t0.addingTimeInterval(1_800), seconds: 300)
            r.store.stop()
            guard r.engine.archive.records.count == 1, let record = r.engine.archive.records.first else {
                return problems + ["expected one record, got \(r.engine.archive.records.count)"]
            }
            let row = daySession([record])
            expect(abs((kept(r, record)?.countedSeconds ?? 0) - 2_100) < 1 && abs((r.store.sessionActivity(for: row)?.countedSeconds ?? 0) - 2_100) < 1,
                   "answered as work, all 2100 seconds count, got \(String(describing: kept(r, record)?.countedSeconds))", &problems)
            expect(r.store.undoLastCorrection(), "the answer is undone", &problems)
            guard let undone = r.engine.archive.records.first else { return problems + ["the record is gone"] }
            expect(abs(undone.workSeconds - 900) < 1, "the record's work is lowered to 900, got \(undone.workSeconds)", &problems)
            r.store.writeActivitySnapshots()
            let shape = kept(r, undone)
            expect(abs((shape?.countedSeconds ?? 0) - 900) <= 30 && abs((shape?.credited["coding"] ?? 0) - 900) <= 30,
                   "the snapshot is written again with the away as paused, got \(String(describing: shape?.countedSeconds)) and \(String(describing: shape?.credited))", &problems)
            r.evidence.memo.removeAll()
            let live = r.store.sessionActivity(for: daySession([undone]))
            expect(abs((live?.countedSeconds ?? 0) - 900) <= 30, "and so is the row, got \(String(describing: live?.countedSeconds))", &problems)
            return problems
        }
    }

    /// 400 records, none with a beat of its own, in the range the beats keep: the first sweep looks at each and
    /// the sweeps after touch no file; a record that changes is looked at again.
    static func settledRecordsCostNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            beats(r.evidence.archive, from: t0.addingTimeInterval(43_350), seconds: 30)   // a day file, in none of them
            let all = (0..<400).map { record(from: t0.addingTimeInterval(TimeInterval($0 * 180)), seconds: 120) }
            expect(r.engine.archive.edit(adding: all) == nil, "the records are saved", &problems)
            let archive = r.evidence.archive
            let before = archive.diskReads
            r.store.writeActivitySnapshots()
            let first = archive.diskReads - before
            expect(first > 0, "the first sweep looks at them, got \(first) reads", &problems)
            let after = archive.diskReads
            r.store.writeActivitySnapshots()
            r.store.writeActivitySnapshots()
            expect(archive.diskReads == after, "the next two read nothing, got \(archive.diskReads - after)", &problems)
            expect(all.allSatisfy { kept(r, $0) == nil }, "and nothing was written", &problems)
            var changed = all[3]
            changed.end = changed.end.addingTimeInterval(30)
            changed.workSeconds += 30
            expect(r.engine.archive.edit(removing: [all[3]], adding: [changed]) == nil, "a record is edited", &problems)
            r.store.writeActivitySnapshots()
            expect(archive.diskReads > after, "and looked at again", &problems)
            return problems
        }
    }

    static func refusedWriteIsTriedOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let refusing = Box(true), attempts = Box(0)
            let sidecar = SessionMetadataArchive(directory: SelfTest.scratchDirectory(), writeOverride: { _ in
                attempts.value += 1
                return refusing.value ? "Storage is unavailable" : nil
            })
            guard let r = rig(metadata: sidecar) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let all = (0..<25).map { endedRecord(r, from: t0.addingTimeInterval(TimeInterval($0 * 180)), seconds: 120) }
            func withShape() -> Int { all.filter { kept(r, $0) != nil }.count }
            for _ in 0..<3 { r.store.writeActivitySnapshots() }
            expect(attempts.value == 25 && withShape() == 0,
                   "three sweeps try each of 25 records once, not every minute, got \(attempts.value) tries", &problems)
            refusing.value = false
            sidecar.saveNote("a note saved by the way", for: UUID())
            r.store.writeActivitySnapshots()
            r.store.writeActivitySnapshots()
            expect(withShape() == 25, "once the sidecar has saved something they are tried again, got \(withShape())", &problems)
            return problems
        }
    }

    /// The sidecar as a build with an unknown `fidelity`, or an unknown phase, would have left it.
    static func unreadableShapeLosesOnlyItself() -> [String] {
        struct Document: Encodable { let version: Int; let entries: [SessionMetadata] }
        var problems: [String] = []
        let (_, directory, _) = metadata()
        let ids = (0..<3).map { _ in UUID() }
        let good = shape(.activity(.coding), credited: ["coding": 300], over: DateInterval(start: t0, duration: 300))
        var entries = ids.map { SessionMetadata(recordID: $0, note: "note \($0.uuidString.prefix(4))") }
        for index in entries.indices { entries[index].activityShape = good }
        guard let data = try? JSONEncoder().encode(Document(version: 2, entries: entries)),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var raw = root["entries"] as? [[String: Any]] else { return ["could not build the file"] }
        func edit(_ index: Int, _ change: (inout [String: Any]) -> Void) {
            guard var shape = raw[index]["activityShape"] as? [String: Any] else { return }
            change(&shape)
            raw[index]["activityShape"] = shape
        }
        edit(0) { $0["fidelity"] = "audio" }
        edit(1) { shape in
            guard var phases = shape["phases"] as? [[String: Any]] else { return }
            phases[0]["activity"] = ["podcast": [String: Any]()]
            shape["phases"] = phases
        }
        root["entries"] = raw
        guard let edited = try? JSONSerialization.data(withJSONObject: root) else { return ["could not write the file"] }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? edited.write(to: directory.appendingPathComponent("session-metadata.json"))
        let loaded = SessionMetadataArchive(directory: directory)
        for (index, entry) in entries.enumerated() {
            expect(loaded.metadata(for: entry.recordID)?.note == entry.note, "entry \(index)'s note still loads", &problems)
        }
        expect(loaded.metadata(for: ids[0])?.activityShape == nil, "an unknown fidelity loses the summary", &problems)
        expect(loaded.metadata(for: ids[1])?.activityShape == nil, "an unknown phase loses the summary", &problems)
        expect(loaded.metadata(for: ids[2])?.activityShape == good, "and no other entry's", &problems)
        expect(loaded.saveNote("written after", for: ids[0]) == .saved, "the sidecar can still be written", &problems)
        expect(SessionMetadataArchive(directory: directory).metadata(for: ids[0])?.note == "written after", "and it was", &problems)
        return problems
    }

    /// Recording goes on after a stop when automatic sessions are on, so the beat that holds the last seconds
    /// is still open; a summary written then would never have them.
    static func snapshotWaitsForTheOpenBeat() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig(session: true, auto: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.activate(coding)
            r.run(100) { _ in r.keys.value &+= 3 }
            r.store.stop()
            guard let stopped = r.engine.archive.records.first else { return ["nothing was archived"] }
            expect(kept(r, stopped) == nil, "with recording on and its last beat open, the record waits", &problems)
            r.run(80)
            let credited = kept(r, stopped)?.credited["coding"] ?? 0
            expect(abs(credited - 100) < 1, "once the beat has closed the snapshot has all 100 seconds, got \(credited)", &problems)
            return problems
        }
    }

    static func midnightRowsTakeTheirOwnPart() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let midnight = Calendar.current.startOfDay(for: t0)
            let ended = endedRecord(r, from: midnight.addingTimeInterval(-1_800), seconds: 3_600)
            func row(_ range: DateInterval) -> DaySession {
                DaySession(id: ended.id, threadID: ended.threadID, name: ended.name, workType: ended.workType,
                           start: range.start, end: range.end, worked: range.duration, stretches: 1,
                           spans: [range], recordIDs: [ended.id], isRunning: false)
            }
            let before = row(DateInterval(start: ended.start, end: midnight))
            let after = row(DateInterval(start: midnight, end: ended.end))
            let first = r.store.sessionActivity(for: before), second = r.store.sessionActivity(for: after)
            expect(first?.bounds.end == midnight && second?.bounds.start == midnight, "each row reads its own bounds from the beats", &problems)
            let sentinel = shape(.mixed, credited: [:], over: DateInterval(start: t0, duration: 1))
            r.evidence.memo[SessionActivityMemoKey(before)]?.shape = sentinel
            r.evidence.stamped[SessionActivityMemoKey(before)] = nil   // ask the memo behind the row's stamp
            _ = r.store.sessionActivity(for: after)
            expect(r.store.sessionActivity(for: before) == sentinel, "the second row does not replace the first in the memo", &problems)

            r.store.writeActivitySnapshots()
            guard let whole = kept(r, ended) else { return problems + ["no snapshot was written"] }
            r.evidence.archive.prune(olderThan: 0, now: t0.addingTimeInterval(3 * 86_400))
            r.evidence.memo.removeAll()
            let early = r.store.sessionActivity(for: before), late = r.store.sessionActivity(for: after)
            expect(abs((early?.credited["coding"] ?? 0) - 1_800) < 1 && abs((late?.credited["coding"] ?? 0) - 1_800) < 1,
                   "with the beats gone each day's row has its half of the credit, got \(String(describing: early?.credited)) and \(String(describing: late?.credited))", &problems)
            expect(early?.bounds == before.spans[0] && late?.bounds == after.spans[0]
                    && abs((early?.countedSeconds ?? 0) - 1_800) < 1 && early?.depth == nil && late?.fingerprint == nil,
                   "its bounds and counted time are the row's, and depth is left out", &problems)
            expect(r.store.sessionActivity(for: row(whole.bounds)) == whole, "a row that holds the whole record gets the whole snapshot", &problems)
            return problems
        }
    }

    static func proseAloneReadsNoBeats() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = endedRecord(r)
            let session = daySession([ended])
            let reads = r.evidence.archive.diskReads
            let prose = r.store.sessionShape(session)
            expect(r.evidence.archive.diskReads == reads && r.evidence.memo.isEmpty, "the prose is worked out without reading a beat", &problems)
            let detail = r.store.storySessionDetail(session, on: r.store.selectedDay)
            expect(detail.text == prose && detail.phases != nil, "and is what the full detail carries, beside its phases", &problems)
            expect(r.store.storySessionDetail(session, on: r.store.selectedDay, withPhases: false).phases == nil, "left out, the phases are nil", &problems)
            return problems
        }
    }
}
