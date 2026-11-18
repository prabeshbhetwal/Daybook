import Foundation

/// A session's phases cover what was recorded and no more: the break between two records stays a
/// break once only their summaries are left, counted time no beat saw borrows no neighbour's purpose,
/// and a manual pause in a session read from its apps alone is not counted.
enum ActivityCoverageChecks: CheckSuite {
    typealias S = ActivitySnapshotChecks

    static let tests: [(String, () -> [String])] = [
        ("Joined summaries keep the break between a session's records, as its beats do", joinKeepsTheBreak),
        ("Counted time no beat recorded borrows no purpose, and no summary says otherwise", unrecordedTimeBorrowsNothing),
        ("A session read from its apps alone does not count its manual pause", appsOnlyRespectsPauses),
        ("A running session stays on one reading as each beat closes", runningRowHoldsItsReading),
        ("Joined summaries read an away beside the break after it as one", joinMergesAway),
        ("A row whose records are not found counts its spans whole", missingRecordsCountWhole),
        ("A partly recorded session reads its apps, not a summary an edit may have left stale", partlyRecordedSkipsSummary),
    ]

    static func joinKeepsTheBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            // Two ten-minute stretches of one session with a ten-minute break between them.
            let thread = UUID()
            let first = S.record(from: S.t0, seconds: 600, thread: thread)
            let second = S.record(from: S.t0.addingTimeInterval(1_200), seconds: 600, thread: thread)
            for record in [first, second] {
                S.beats(r.evidence.archive, from: record.start, seconds: 600)
                r.engine.archive.append(record)
            }
            guard let live = r.store.sessionActivity(for: S.daySession([first, second])) else { return ["the session has no phases"] }
            r.store.writeActivitySnapshots()
            guard let one = S.kept(r, first), let two = S.kept(r, second),
                  let joined = SessionActivityShape.joined([one, two]) else { return ["no summaries were kept"] }
            func span(_ shape: SessionActivityShape) -> TimeInterval {
                shape.phases.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            }
            func described(_ shape: SessionActivityShape) -> String {
                shape.phases.map { "\($0.activity) \($0.counted ? "counted" : "uncounted")" }.joined(separator: ", ")
            }
            expect(span(live) == 1_800 && span(joined) == span(live) && joined.bounds == live.bounds,
                   "the joined summaries span the whole half hour as the beats do, got \(span(joined)) and \(span(live))", &problems)
            expect(joined.phases.map(\.activity) == live.phases.map(\.activity)
                    && joined.phases.map(\.counted) == live.phases.map(\.counted)
                    && live.phases.map(\.counted) == [true, false, true],
                   "the same phases in order, the break uncounted: beats \(described(live)); joined \(described(joined))", &problems)
            let half = joined.clipped(to: DateInterval(start: S.t0, end: S.t0.addingTimeInterval(900)))
            expect(span(half) == 900 && half.phases.map(\.activity) == [.purpose(.coding), .away],
                   "a row cut at the break's middle keeps its part of it, got \(described(half))", &problems)
            expect(joined.clipped(to: joined.bounds) == joined, "a row that holds the whole session gets the whole join", &problems)
            return problems
        }
    }

    static func unrecordedTimeBorrowsNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            // Three hours before Record app use was switched on, then ten minutes in the editor.
            let record = S.record(from: S.t0, seconds: 190 * 60)
            S.beats(r.evidence.archive, from: S.t0.addingTimeInterval(180 * 60), seconds: 600)
            r.engine.archive.append(record)
            let row = r.store.sessionActivity(for: S.daySession([record]))
            let longest = row?.phases.filter { $0.activity == .purpose(.coding) }
                .map { $0.end.timeIntervalSince($0.start) }.max() ?? 0
            expect(longest <= 600, "no coding phase is longer than the ten recorded minutes, got \(longest / 60) min", &problems)
            expect(row?.fidelity == .appsOnly, "the row reads its apps, got \(String(describing: row?.fidelity))", &problems)
            r.store.writeActivitySnapshots()
            expect(S.kept(r, record) == nil, "and no summary is kept that the row would read once the beats expire", &problems)
            return problems
        }
    }

    static func appsOnlyRespectsPauses() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            // A half-hour stretch paused by hand from minute 10 to 20, the editor in front throughout, no beats.
            var record = S.record(from: S.t0, seconds: 1_800,
                                  paused: [DateInterval(start: S.t0.addingTimeInterval(600), duration: 600)])
            record.workSeconds = 1_200
            r.engine.archive.append(record)
            let session = S.daySession([record])
            let apps = RecordedActivity(segments: [TimelineSegment(id: UUID(), bundleID: S.coding, appName: "Xcode",
                                                                   start: S.t0, end: S.t0.addingTimeInterval(1_800))],
                                        spans: session.spans)
            let shape = r.store.sessionActivity(for: session, apps: apps)
            expect(shape?.fidelity == .appsOnly, "read from its apps, got \(String(describing: shape?.fidelity))", &problems)
            expect(abs((shape?.countedSeconds ?? 0) - 1_200) < 1 && abs((shape?.credited["coding"] ?? 0) - 1_200) < 1,
                   "20 minutes counted and credited, got \(String(describing: shape?.countedSeconds)) and \(String(describing: shape?.credited))", &problems)
            expect(shape?.phases.map(\.counted) == [true, false, true]
                    && shape?.phases.map(\.activity) == [.purpose(.coding), .away, .purpose(.coding)],
                   "the pause is an uncounted phase between two of coding, got \(String(describing: shape?.phases.map { "\($0.activity) \($0.counted)" }))", &problems)
            return problems
        }
    }

    static func runningRowHoldsItsReading() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Begun 160 s (under a phase) or 400 s (over it) before recording started.
            for (age, expected) in [(160.0, ShapeFidelity.beats), (400.0, ShapeFidelity.appsOnly)] {
                guard let r = ActivityEvidenceStoreChecks.rig(session: true, sessionAge: age) else {
                    return ["could not create isolated preferences"]
                }
                defer { r.close() }
                r.activate(S.coding)
                var seen: [String] = []
                r.run(120) { tick in
                    r.keys.value &+= 3
                    if tick >= 60, let row = S.liveSession(r) {
                        seen.append(String(describing: r.store.sessionActivity(for: row)?.fidelity))
                    }
                }
                expect(Set(seen) == [String(describing: Optional(expected))],
                       "begun \(Int(age)) s unrecorded, every second of two beats reads \(expected), got \(Set(seen))", &problems)
            }
            return problems
        }
    }

    static func joinMergesAway() -> [String] {
        var problems: [String] = []
        func phase(_ from: TimeInterval, _ to: TimeInterval, _ activity: PhaseActivity) -> SessionPhase {
            let counted = activity != .away
            return SessionPhase(start: S.t0.addingTimeInterval(from), end: S.t0.addingTimeInterval(to), activity: activity,
                                counted: counted, credited: counted ? ["coding": to - from] : [:])
        }
        func shape(_ phases: [SessionPhase]) -> SessionActivityShape {
            SessionActivityShape(algorithmVersion: ActivityConstants.algorithmVersion, fidelity: .beats,
                                 bounds: DateInterval(start: phases[0].start, end: phases[phases.count - 1].end),
                                 countedSeconds: 300, signals: [], phases: phases, depth: nil, label: .activity(.coding),
                                 credited: ["coding": 300], fingerprint: nil, splitCandidates: [])
        }
        // The first record ends in five minutes away; the next begins five minutes after it.
        let joined = SessionActivityShape.joined([shape([phase(0, 300, .purpose(.coding)), phase(300, 600, .away)]),
                                                  shape([phase(900, 1_200, .purpose(.coding))])])
        let middle = joined?.phases.count == 3 ? joined?.phases[1] : nil
        expect(joined?.phases.map(\.activity) == [.purpose(.coding), .away, .purpose(.coding)]
                && middle?.start == S.t0.addingTimeInterval(300) && middle?.end == S.t0.addingTimeInterval(900),
               "one away phase from minute 5 to 15, got \(String(describing: joined?.phases.map { "\($0.activity)" }))", &problems)
        return problems
    }

    static func missingRecordsCountWhole() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let record = S.record(from: S.t0, seconds: 600)   // never archived, so the row finds none of its records
            let session = S.daySession([record])
            let apps = RecordedActivity(segments: [TimelineSegment(id: UUID(), bundleID: S.coding, appName: "Xcode",
                                                                   start: S.t0, end: S.t0.addingTimeInterval(600))],
                                        spans: session.spans)
            let shape = r.store.sessionActivity(for: session, apps: apps)
            expect(abs((shape?.countedSeconds ?? 0) - 600) < 1 && shape?.phases.map(\.counted) == [true],
                   "its ten minutes count, got \(String(describing: shape?.countedSeconds))", &problems)
            return problems
        }
    }

    static func partlyRecordedSkipsSummary() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = S.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let record = S.record(from: S.t0, seconds: 190 * 60)
            S.beats(r.evidence.archive, from: S.t0.addingTimeInterval(180 * 60), seconds: 600)
            r.engine.archive.append(record)
            // A summary from before an edit that added the unrecorded time.
            let stale = S.shape(.activity(.design), credited: ["design": 600],
                                over: DateInterval(start: record.start, end: record.end))
            expect(r.store.metadataArchive.saveActivityShape(stale, for: record.id) == .saved, "a summary is saved", &problems)
            let row = r.store.sessionActivity(for: S.daySession([record]))
            expect(row != stale && row?.fidelity == .appsOnly,
                   "the row reads its apps, got \(String(describing: row?.fidelity)) \(String(describing: row?.label))", &problems)
            return problems
        }
    }
}
