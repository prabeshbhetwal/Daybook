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
}
