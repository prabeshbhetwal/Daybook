import Foundation

/// What the whole-branch review of activity-aware sessions found: phases are worked out only for a
/// row that shows them, depth is left out when work was split, the settings a summary was derived
/// under are part of what keeps it current, expired beats go without waiting for a tick, a sweep
/// reads a bounded number of day files, and a record archived on wake waits for its open beat.
enum ActivityReviewFixChecks: CheckSuite {
    typealias S = ActivitySnapshotChecks

    static let tests: [(String, () -> [String])] = [
        ("The day's projection reads no beat file, and an open card still gets its phases", projectionLeavesPhasesOut),
        ("A session split by a departure has no depth word", splitLeavesDepthOut),
        ("A changed purpose override refreshes a session's row and its stored summary", overrideRefreshes),
        ("A changed category watching setting refreshes a session's row and its stored summary", watchingRefreshes),
        ("Expired beats are removed at launch and when Record app use is switched off, with no tick", pruneWithoutATick),
        ("A sweep reads at most 20 beat day files, so a relaunch does not read them all at once", sweepReadsBounded),
        ("A record archived on wake while its last beat is open gets all its seconds", wakeWaitsForTheOpenBeat),
        ("A past day's open card reads no beat file on a redraw until its beats or records change", openCardIsStamped),
        ("The launch sweep writes a record at the edge of the 90 days before its beats are removed", launchSweepBeforePrune),
    ]

    static func projectionLeavesPhasesOut() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = S.endedRecord(r)
            let reads = r.evidence.archive.diskReads
            let projection = r.store.storyDayProjection(on: ended.start)
            expect(r.evidence.archive.diskReads == reads,
                   "the day's projection reads no beat file, got \(r.evidence.archive.diskReads - reads) reads", &problems)
            let sessions = projection.sessions.compactMap { entry -> DaySession? in
                if case .session(let session) = entry { return session }
                return nil
            }
            guard let session = sessions.first else { return problems + ["the day has no session row"] }
            expect(projection.sessionDetails[session.id] != nil && projection.sessionDetails[session.id]?.phases == nil,
                   "its detail leaves the phases out", &problems)
            let open = r.store.openSessionDetail(session, in: projection)
            expect(open.phases?.label == .activity(.coding) && open.phases?.fidelity == .beats,
                   "an open card gets its phases from the beats, got \(String(describing: open.phases?.label))", &problems)
            return problems
        }
    }

    static func splitLeavesDepthOut() -> [String] {
        var problems: [String] = []
        let mailThenEditor = ActivityTraces.session([ActivityTraces.step("com.apple.mail", 1, .keys),
                                                     ActivityTraces.step(ActivityTraces.editor, 120, .keys)])
        var cases = [("1 minute in Mail then 2 hours in the editor", mailThenEditor)]
        if let left = ActivityTraces.all.first(where: { $0.name.hasPrefix("f.") }) { cases.append((left.name, left.input)) }
        for (name, input) in cases {
            let shape = ActivityDerivation.derive(input)
            expect(!shape.splitCandidates.isEmpty, "\(name) has a split candidate, got none", &problems)
            expect(shape.depth == nil && SessionPhaseText.depthWord(shape.depth) == nil,
                   "\(name) has no depth word, got \(String(describing: shape.depth))", &problems)
        }
        return problems
    }

    static func overrideRefreshes() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let ended = S.endedRecord(r)
            let session = S.daySession([ended])
            r.store.writeActivitySnapshots()
            expect(S.kept(r, ended)?.label == .activity(.coding) && r.store.sessionActivity(for: session)?.label == .activity(.coding),
                   "an editor reads as coding before the override", &problems)
            r.persistence.purposeOverrides = [S.coding: AppPurpose.communication.rawValue]
            let row = r.store.sessionActivity(for: session)?.label
            expect(row == .activity(.communication), "the row follows the override, got \(String(describing: row))", &problems)
            r.store.writeActivitySnapshots()
            let kept = S.kept(r, ended)?.label
            expect(kept == .activity(.communication), "and so does the stored summary, got \(String(describing: kept))", &problems)
            return problems
        }
    }

    static func watchingRefreshes() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let calls = WorkType(rawValue: "custom.selftest.calls")
            func define(watching: Bool) {
                WorkTypeCatalog.shared.apply(customisations: [
                    WorkTypeDefinition(id: calls.rawValue, name: "Calls", symbolName: "phone.fill", hue: .green,
                                       countsWhileWatching: watching)])
            }
            define(watching: false)
            // Later checks read the shared catalogue; leave it as shipped.
            defer { WorkTypeCatalog.shared.apply(customisations: []) }
            let ended = S.record(from: S.t0, seconds: 600, type: calls)
            S.beats(r.evidence.archive, from: S.t0, seconds: 600)
            r.engine.archive.append(ended)
            let session = S.daySession([ended])
            r.store.writeActivitySnapshots()
            expect(S.kept(r, ended)?.countsWhileWatching == false && r.store.sessionActivity(for: session)?.countsWhileWatching == false,
                   "derived with watching off at first", &problems)
            define(watching: true)
            let row = r.store.sessionActivity(for: session)?.countsWhileWatching
            expect(row == true, "the row follows the category's new setting, got \(String(describing: row))", &problems)
            r.store.writeActivitySnapshots()
            let kept = S.kept(r, ended)?.countsWhileWatching
            expect(kept == true, "and so does the stored summary, got \(String(describing: kept))", &problems)
            return problems
        }
    }

    static func pruneWithoutATick() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let calendar = r.store.periodCalendar
            func expired() -> Date { calendar.date(byAdding: .day, value: -100, to: r.clock.value) ?? r.clock.value }
            S.beats(r.evidence.archive, from: Beat.gridStart(for: expired()), seconds: 60)
            r.evidence.lastPruneDay = nil   // as a launch finds it
            r.store.refresh()
            expect(!r.evidence.archive.covers(from: expired()), "the refresh at launch removes beats past their 90 days", &problems)
            // The next day, with no tick: switching Record app use off removes what has expired since.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: r.clock.value) ?? r.clock.value
            r.clock.advance(tomorrow.timeIntervalSince(r.clock.value))
            S.beats(r.evidence.archive, from: Beat.gridStart(for: expired()), seconds: 60)
            r.store.setTrackingEnabled(false)
            expect(!r.evidence.archive.covers(from: expired()), "switching Record app use off removes them too", &problems)
            return problems
        }
    }

    static func sweepReadsBounded() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            // Forty records on forty days, two apart, whose pauses are not known, so each reads its days
            // to settle; a beat an hour after each keeps a day file there. Eight days stay decoded.
            for index in 1...40 {
                let day = Calendar.current.date(byAdding: .day, value: -2 * index, to: S.t0) ?? S.t0
                let start = Beat.gridStart(for: day)
                S.beats(r.evidence.archive, from: start.addingTimeInterval(3_600), seconds: 30)
                r.engine.archive.append(S.record(from: start, seconds: 120, paused: nil))
            }
            let before = r.evidence.archive.dayFileReads
            r.store.writeActivitySnapshots()
            let read = r.evidence.archive.dayFileReads - before
            // The budget is checked before each record, and one record's window holds at most five days.
            expect(read >= 20 && read < 25, "a sweep reads about 20 day files and stops, got \(read)", &problems)
            return problems
        }
    }

    static func wakeWaitsForTheOpenBeat() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig(session: true) else { return ["could not create isolated preferences"] }
            defer { r.close() }
            r.activate(S.coding)
            r.run(100) { _ in r.keys.value &+= 3 }
            let asleep = r.clock.value
            r.clock.advance(3_600)
            // On wake the session is closed where the Mac went to sleep, and the store refreshes.
            _ = r.engine.stop(endingAt: asleep)
            r.store.refresh()
            guard let record = r.engine.archive.records.first else { return problems + ["nothing was archived"] }
            expect(S.kept(r, record) == nil, "the refresh on wake writes nothing while the last beat is open", &problems)
            r.run(70)
            let credited = S.kept(r, record)?.credited["coding"] ?? 0
            expect(credited >= 98.5, "the next heartbeat writes it with all its seconds, got \(credited)", &problems)
            return problems
        }
    }

    static func openCardIsStamped() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            func daysAgo(_ days: Int) -> Date {
                Beat.gridStart(for: Calendar.current.date(byAdding: .day, value: -days, to: S.t0) ?? S.t0)
            }
            let near = S.endedRecord(r, from: daysAgo(1)), far = S.endedRecord(r, from: daysAgo(8))
            // Thirty days back, with neither beats nor a summary: its phases come from its apps alone.
            let old = S.record(from: daysAgo(30), seconds: 600)
            r.engine.archive.append(old)
            /// The open card for a record, as DayStory reads it.
            func open(_ record: SessionRecord) -> (key: SessionActivityMemoKey, phases: SessionActivityShape?)? {
                let projection = r.store.storyDayProjection(on: record.start)
                for case .session(let session) in projection.sessions where session.recordIDs.contains(record.id) {
                    return (SessionActivityMemoKey(session), r.store.openSessionDetail(session, in: projection).phases)
                }
                return nil
            }
            func reads() -> [Int] { [r.evidence.archive.diskReads, r.evidence.archive.dayFileReads] }
            let first = [near, far].map { open($0)?.phases }
            expect(first.allSatisfy { $0?.fidelity == .beats }, "two open cards a week apart read their beats", &problems)
            let before = reads()
            let second = [near, far].map { open($0)?.phases }
            expect(reads() == before && second == first,
                   "redrawn, they read nothing (disk, day files) \(zip(reads(), before).map { $0 - $1 })", &problems)
            let sentinel = S.shape(.mixed, credited: [:], over: DateInterval(start: S.t0, duration: 1))
            func plant(_ record: SessionRecord) {
                if let key = open(record)?.key { r.evidence.stamped[key]?.shape = sentinel }
            }
            plant(near)
            expect(open(near)?.phases == sentinel, "with nothing changed the row's last reading is kept", &problems)
            try? r.evidence.archive.append(Beat(start: near.start, offset: 5,
                                                slices: [BeatSlice(app: S.coding, seconds: 5, keys: 1, clicks: 0, scrolls: 0)],
                                                presence: .input))
            expect(open(near)?.phases != sentinel, "a beat appended reads it again", &problems)
            plant(far)
            var paused = far
            paused.pausedSpans = [DateInterval(start: far.start.addingTimeInterval(300), duration: 60)]
            paused.workSeconds = 540
            expect(r.engine.archive.edit(removing: [far], adding: [paused]) == nil, "a pause is edited", &problems)
            let edited = open(paused)?.phases
            expect(edited != sentinel && edited?.countedSeconds == 540,
                   "an edit reads it again, got \(String(describing: edited?.countedSeconds))", &problems)
            let apps = open(old)
            expect(apps?.phases?.fidelity == .appsOnly, "the old session reads its apps alone", &problems)
            plant(old)
            expect(open(old)?.phases == sentinel, "and is not worked out again on a redraw", &problems)
            return problems
        }
    }

    static func launchSweepBeforePrune() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let calendar = r.store.periodCalendar
            let edge = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -90, to: r.clock.value) ?? r.clock.value)
            // From 11 pm on the day past the 90 to late morning on the 90th: its first day's file is the one removed.
            let record = S.record(from: Beat.gridStart(for: edge.addingTimeInterval(-3_600)), seconds: 12 * 3_600)
            S.beats(r.evidence.archive, from: record.start, seconds: 600)
            r.engine.archive.append(record)
            r.evidence.lastPruneDay = nil   // as a launch finds it
            r.store.refresh()
            expect(S.kept(r, record) != nil, "the launch refresh writes its summary before removing its first day", &problems)
            expect(!r.evidence.archive.covers(from: record.start), "and then removes the expired day", &problems)
            return problems
        }
    }
}
