import Foundation

/// Activity-aware sessions: deriving a session's working set, departures, phases,
/// depth, label and fingerprint from its credited beats.
enum ActivityDerivationChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An app joins the working set only when work returns to a member", joinsOnReturn),
        ("An idle pause is never a departure", idlePauseStays),
        ("A running session's open window is not yet a split", openWindowNotSplit),
        ("Watching counts inside for a category where watching is the work", watchingInside),
        ("The fingerprint buckets shares and names two apps", fingerprint),
        ("Phases cover the session with no gap or overlap", phasesCover),
        ("A short uncounted run between counted phases is kept", shortUncountedKept),
        ("A watching pause starts where the engine started it, not at its first idle beat", watchingPauseStart),
        ("An older session shows phases from its apps alone, with no depth", appsOnlyPhases),
        ("An older browser-only session is unsorted, not research", appsOnlyBrowserUnsorted),
        ("An older session with no recorded apps is one uncounted stretch away", appsOnlyEmpty),
        ("A gap between apps is away and uncounted in an older session", appsOnlyGap),
        ("An app the purpose map does not list takes its mapped purpose in an older session", appsOnlyUnlisted),
    ]

    private typealias T = ActivityTraces

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func workingSet(_ input: DerivationInput) -> (members: Set<String>, departures: [Date]) {
        ActivityWorkingSet.derive(ActivityCredit.credit(input.credit), beats: input.credit.beats,
                                  countsWhileWatching: input.countsWhileWatching)
    }

    /// The same session, still running at `now`, its bounds and counted time ending there.
    private static func running(_ input: DerivationInput, now: Date) -> DerivationInput {
        let bounds = DateInterval(start: input.bounds.start, end: now)
        return DerivationInput(credit: CreditInput(beats: input.credit.beats, counted: [bounds], signals: [],
                                                   purposeOverrides: [:]),
                               bounds: bounds, countsWhileWatching: false, isRunning: true, now: now)
    }

    private static func joinsOnReturn() -> [String] {
        var problems: [String] = []
        let back = T.session([T.step(T.editor, 10, .keys), T.step(T.browser, 14, .keys), T.step(T.editor, 10, .keys)])
        expect(workingSet(back).members == [T.editor, T.browser],
               "a return after 14 min makes the browser a member, got \(workingSet(back).members)", &problems)
        let late = T.session([T.step(T.editor, 10, .keys), T.step(T.browser, 16, .keys), T.step(T.editor, 10, .keys)])
        expect(workingSet(late).members == [T.editor],
               "a return after 16 min leaves the browser out, got \(workingSet(late).members)", &problems)
        let splits = ActivityDerivation.derive(late).splitCandidates
        expect(splits == [at(10)], "the split candidate sits at the browser's first engaged second, got \(splits)",
               &problems)
        return problems
    }

    private static func idlePauseStays() -> [String] {
        var problems: [String] = []
        let lunch = T.session([T.step(T.editor, 30, .keys), T.step(T.editor, 60, .none, presence: .paused),
                               T.step(T.editor, 20, .keys)], counted: [(0, 30), (90, 110)])
        let departures = workingSet(lunch).departures
        expect(departures.isEmpty, "the lunch trace has no departures, got \(departures)", &problems)
        return problems
    }

    private static func openWindowNotSplit() -> [String] {
        var problems: [String] = []
        for (minutes, expected) in [(10.0, [Date]()), (15.0, [at(30)])] {
            let trace = T.session([T.step(T.editor, 30, .keys), T.step(T.messaging, minutes, .keys)])
            let splits = ActivityDerivation.derive(running(trace, now: at(30 + minutes))).splitCandidates
            expect(splits == expected, "\(Int(minutes)) min after the departure: splits \(expected), got \(splits)",
                   &problems)
        }
        return problems
    }

    private static func watchingInside() -> [String] {
        var problems: [String] = []
        for watchingIsWork in [true, false] {
            let call = T.session([T.step(T.callApp, 30, .none, holder: T.callApp)], countsWhileWatching: watchingIsWork)
            let depth = ActivityDerivation.derive(call).depth
            expect(depth == (watchingIsWork ? .deep : .passive),
                   "a held call with countsWhileWatching \(watchingIsWork) has depth \(String(describing: depth))",
                   &problems)

            let meeting = T.session([T.step(T.editor, 10, .keys), T.step(T.callApp, 30, .none, holder: T.callApp)],
                                    countsWhileWatching: watchingIsWork)
            let departures = workingSet(meeting).departures
            let splits = ActivityDerivation.derive(meeting).splitCandidates
            expect(watchingIsWork ? departures.isEmpty && splits.isEmpty : departures.count == 1,
                   "a meeting with countsWhileWatching \(watchingIsWork): departures \(departures), splits \(splits)",
                   &problems)
        }
        return problems
    }

    private static func fingerprint() -> [String] {
        var problems: [String] = []
        let mixed = ActivityDerivation.derive(T.session([T.step(T.editor, 7, .keys), T.step(T.browser, 3, .keys)]))
        var shares = Array(repeating: 0, count: AppPurpose.allCases.count)
        shares[AppPurpose.allCases.firstIndex(of: .coding)!] = 3
        shares[AppPurpose.allCases.firstIndex(of: .research)!] = 1
        expect(mixed.fingerprint == ActivityFingerprint(shares: shares, topApps: [T.editor, T.browser], siteKind: "none"),
               "70% coding and 30% research, got \(String(describing: mixed.fingerprint))", &problems)
        let single = ActivityDerivation.derive(T.session([T.step(T.terminal, 30, .keys)]))
        expect(single.fingerprint?.topApps == [T.terminal, ""],
               "a single-app session pads topApps, got \(String(describing: single.fingerprint?.topApps))", &problems)
        return problems
    }

    private static func phasesCover() -> [String] {
        var problems: [String] = []
        for row in T.all {
            let phases = ActivityDerivation.derive(row.input).phases
            let joined = zip(phases, phases.dropFirst()).allSatisfy { $0.end == $1.start && $0.start < $0.end }
            expect(!phases.isEmpty && joined && phases.first?.start == row.input.bounds.start
                    && phases.last?.end == row.input.bounds.end,
                   "\(row.name): phases should tile the bounds, got \(phases.map { ($0.start, $0.end) })", &problems)
        }
        return problems
    }

    private static func shortUncountedKept() -> [String] {
        var problems: [String] = []
        let input = T.session([T.step(T.editor, 20, .keys), T.step(T.editor, 2, .none, presence: .paused),
                               T.step(T.editor, 20, .keys)], counted: [(0, 20), (22, 42)])
        let phases = ActivityDerivation.derive(input).phases.map(\.activity)
        expect(phases == [.purpose(.coding), .away, .purpose(.coding)],
               "two minutes paused between coding stay a phase, got \(phases)", &problems)
        return problems
    }

    private static func watchingPauseStart() -> [String] {
        var problems: [String] = []
        // The engine backdates the pause to minute 20, after writing the film's first ten
        // minutes as watched; no holder is read once the pause has begun.
        let film = T.session([T.step(T.editor, 20, .keys), T.step(T.mediaPlayer, 10, .none, holder: T.mediaPlayer),
                              T.step(T.mediaPlayer, 50, .none, presence: .watchPause)], counted: [(0, 20)],
                             edit: { if $0.presence == .watchPause { $0.watchedApps = nil } })
        let shape = ActivityDerivation.derive(film)
        expect(shape.phases.map(\.activity) == [.purpose(.coding), .purpose(.media)]
                && shape.phases.map(\.counted) == [true, false] && shape.phases.first?.end == at(20),
               "coding to minute 20, then the film uncounted, got \(shape.phases.map { ($0.activity, $0.counted, $0.end) })",
               &problems)
        expect(shape.splitCandidates == [at(20)], "the split sits at minute 20, got \(shape.splitCandidates)", &problems)
        return problems
    }

    // MARK: Sessions recorded before beats

    /// Foreground-app evidence as the store reads it: (app, from minute, to minute), spans as given.
    private static func older(_ apps: [(String, Double, Double)], spans: [(Double, Double)]) -> RecordedActivity {
        RecordedActivity(
            segments: apps.map { TimelineSegment(id: UUID(), bundleID: $0.0, appName: $0.0,
                                                 start: at($0.1), end: at($0.2)) },
            spans: spans.map { DateInterval(start: at($0.0), end: at($0.1)) })
    }

    private static func appsOnly(_ activity: RecordedActivity, minutes: Double,
                                 overrides: [String: String] = [:]) -> SessionActivityShape {
        ActivityDerivation.appsOnly(activity, bounds: DateInterval(start: at(0), end: at(minutes)),
                                    purposeOverrides: overrides)
    }

    private static func appsOnlyPhases() -> [String] {
        var problems: [String] = []
        let shape = appsOnly(older([(T.editor, 0, 40), (T.browser, 40, 50), (T.editor, 50, 80)], spans: [(0, 80)]),
                             minutes: 80)
        expect(shape.phases.map(\.activity) == [.purpose(.coding), .browsing, .purpose(.coding)]
                && shape.phases.map(\.counted) == [true, true, true],
               "coding, browsing, coding, got \(shape.phases.map { ($0.activity, $0.counted) })", &problems)
        expect(shape.phases.first?.start == at(0) && shape.phases.last?.end == at(80),
               "phases tile the bounds", &problems)
        expect(shape.depth == nil && shape.fidelity == .appsOnly && shape.fingerprint == nil
                && shape.signals.isEmpty && shape.splitCandidates.isEmpty
                && shape.algorithmVersion == ActivityConstants.algorithmVersion,
               "no depth, fingerprint, signals or splits, apps-only fidelity", &problems)
        expect(shape.label == .activity(.coding) && shape.credited == ["coding": 70 * 60],
               "coding leads and browsing credits nothing, got \(shape.label) \(shape.credited)", &problems)
        expect(shape.countedSeconds == 80 * 60, "counted seconds are the session's spans, got \(shape.countedSeconds)",
               &problems)
        return problems
    }

    private static func appsOnlyBrowserUnsorted() -> [String] {
        var problems: [String] = []
        let shape = appsOnly(older([(T.browser, 0, 30)], spans: [(0, 30)]), minutes: 30)
        expect(shape.label == .unsorted && shape.credited.isEmpty && shape.phases.map(\.activity) == [.browsing],
               "browser only: unsorted, nothing credited, one browsing phase, got \(shape.label) \(shape.phases.map(\.activity))",
               &problems)
        return problems
    }

    private static func appsOnlyEmpty() -> [String] {
        var problems: [String] = []
        let shape = appsOnly(older([], spans: []), minutes: 30)
        expect(shape.phases.map(\.activity) == [.away] && shape.phases.map(\.counted) == [false]
                && shape.label == .unsorted && shape.depth == nil && shape.countedSeconds == 0,
               "an empty record is one uncounted away phase, got \(shape.phases.map { ($0.activity, $0.counted) })",
               &problems)
        return problems
    }

    private static func appsOnlyGap() -> [String] {
        var problems: [String] = []
        let shape = appsOnly(older([(T.editor, 0, 20), (T.editor, 30, 50)], spans: [(0, 50)]), minutes: 50)
        expect(shape.phases.map(\.activity) == [.purpose(.coding), .away, .purpose(.coding)]
                && shape.phases.map(\.counted) == [true, false, true],
               "a ten-minute gap is an uncounted away phase, got \(shape.phases.map { ($0.activity, $0.counted) })",
               &problems)
        return problems
    }

    private static func appsOnlyUnlisted() -> [String] {
        var problems: [String] = []
        let viewer = appsOnly(older([(T.viewer, 0, 10)], spans: [(0, 10)]), minutes: 10)
        expect(viewer.phases.map(\.activity) == [.purpose(.utility)] && viewer.label == .activity(.utility),
               "an unlisted app is utility, got \(viewer.phases.map(\.activity)) \(viewer.label)", &problems)
        let overridden = appsOnly(older([(T.browser, 0, 10)], spans: [(0, 10)]), minutes: 10,
                                  overrides: [T.browser: AppPurpose.design.rawValue])
        expect(overridden.phases.map(\.activity) == [.purpose(.design)] && overridden.label == .activity(.design),
               "an overridden browser takes the override, got \(overridden.phases.map(\.activity))", &problems)
        return problems
    }
}
