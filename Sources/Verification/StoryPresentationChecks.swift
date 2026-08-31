import Foundation

enum StoryPresentationChecks {
    static let tests: [(String, () -> [String])] = [
        ("Story grouping preserves observed seconds through gaps and overlaps", observedIntervalGrouping),
        ("Month duration intensity distinguishes long days and keeps labels legible", heatmap),
        ("Story chronology preserves resumed stretches, observed use and unknown gaps", chronology),
        ("Story app detail clips the requested app without changing source evidence", appEvidence),
        ("Sparse Story narratives distinguish rest, app use and focus", sparseNarratives),
        ("Named snapshot scenarios route to their actual production surfaces", snapshotRoutes),
        ("A continued legacy thread keeps distinct Story row identities", legacyRowIdentity),
        ("Story chronology never bridges observed use through focus or rest", chronologyHonoursOccupiedSeparators)
    ]

    private static func observedIntervalGrouping() -> [String] {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_782_000_000))
        let start = day.addingTimeInterval(9 * 3_600)
        var failures: [String] = []
        let cases: [(String, [(Double, Double)])] = [
            ("gap", [(0, 600), (630, 1_230)]),
            ("overlap", [(0, 600), (300, 900)]),
            ("nested", [(0, 900), (300, 600)]),
            ("identical", [(0, 600), (0, 600)]),
            ("adjacent", [(0, 600), (600, 1_200)])
        ]
        for (name, spans) in cases {
            let usage = spans.enumerated().map { index, span in
                AppUsageSession(bundleID: "app\(index)", appName: "App \(index)",
                                start: start.addingTimeInterval(span.0),
                                end: start.addingTimeInterval(span.1))
            }
            let moments = StoryChronology.build(records: [], running: nil, usage: usage,
                                                 day: day, now: start.addingTimeInterval(3_600))
            let observed = moments.reduce(0.0) { total, moment in
                if case .appUse(_, let seconds) = moment { return total + seconds }
                return total
            }
            // Preserve the canonical sum, including qualified legacy overlaps;
            // a grouping envelope never creates extra recorded time.
            if observed != usage.reduce(0, { $0 + $1.seconds }) {
                failures.append("\(name): grouped \(observed)s differs from the source's 1200s")
            }
            if moments.count != 1 { failures.append("\(name): connected visits did not form one group") }
        }
        return failures
    }

    private static func heatmap() -> [String] {
        var failures: [String] = []
        for dark in [false, true] {
            let oneHour = StoryHeatmap.paint(seconds: 3_600, peak: 8 * 3_600, dark: dark)
            let eightHours = StoryHeatmap.paint(seconds: 8 * 3_600, peak: 8 * 3_600, dark: dark)
            if oneHour.intensity >= eightHours.intensity {
                failures.append("One and eight hours saturate to the same intensity")
            }
            for minutes in stride(from: 0, through: 480, by: 5) {
                let paint = StoryHeatmap.paint(seconds: Double(minutes * 60), peak: 8 * 3_600, dark: dark)
                func luminance(_ hex: UInt32) -> Double {
                    let r = Double((hex >> 16) & 255) / 255
                    let g = Double((hex >> 8) & 255) / 255
                    let b = Double(hex & 255) / 255
                    func linear(_ c: Double) -> Double {
                        c < 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
                    }
                    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
                }
                let light = max(luminance(paint.background), luminance(paint.foreground))
                let darkValue = min(luminance(paint.background), luminance(paint.foreground))
                if (light + 0.05) / (darkValue + 0.05) < 4.5 {
                    failures.append("\(minutes)m cell in \(dark ? "dark" : "light") has illegible date text")
                }
            }
        }
        return failures
    }

    private static func chronology() -> [String] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_782_000_000))
        let morning = day.addingTimeInterval(9 * 3_600)
        let thread = UUID()
        let records = [
            SessionRecord(name: "Parser", workType: .deepWork, start: morning,
                          end: morning.addingTimeInterval(1_800), workSeconds: 1_800, threadID: thread),
            SessionRecord(name: "Parser", workType: .deepWork, start: morning.addingTimeInterval(3_600),
                          end: morning.addingTimeInterval(5_400), workSeconds: 1_800, threadID: thread)
        ]
        let usage = [AppUsageSession(bundleID: "test.editor", appName: "Editor",
                                     start: morning.addingTimeInterval(-900), end: morning)]
        let result = StoryChronology.build(records: records, running: nil, usage: usage, day: day,
                                            now: morning.addingTimeInterval(6_000))
        var failures: [String] = []
        let sessions = result.compactMap { item -> DaySession? in
            if case .entry(.session(let session)) = item { return session }; return nil
        }
        if sessions.count != 2 || sessions.reduce(0, { $0 + $1.worked }) != 3_600 {
            failures.append("Chronology collapsed separate stretches or changed credited work")
        }
        let gaps = result.compactMap { item -> DateInterval? in
            if case .unrecorded(let span) = item { return span }; return nil
        }
        if gaps.count != 1 || gaps[0].duration != 1_800 {
            failures.append("The half-hour unknown interval was hidden or inflated")
        }
        let appOnly = StoryChronology.build(records: [], running: nil, usage: usage, day: day,
                                             now: morning.addingTimeInterval(6_000))
        if appOnly.count != 1 { failures.append("An app-only day did not show its observed use") }
        if case .appUse(_, let seconds) = appOnly.first, seconds == 900 { }
        else { failures.append("App-only story misreported its fifteen observed minutes") }
        if result.map(\.start) != result.map(\.start).sorted() {
            failures.append("The story is not chronological")
        }
        return failures
    }

    private static func appEvidence() -> [String] {
        let start = Date(timeIntervalSince1970: 1_782_000_000)
        let window = DateInterval(start: start, duration: 600)
        let sources = [
            AppUsageSession(bundleID: "editor", appName: "Editor", start: start.addingTimeInterval(-600),
                            end: start.addingTimeInterval(120)),
            AppUsageSession(bundleID: "editor", appName: "Editor", start: start.addingTimeInterval(300),
                            end: start.addingTimeInterval(900)),
            AppUsageSession(bundleID: "browser", appName: "Browser", start: start, end: window.end)
        ]
        let evidence = StoryAppEvidence.clipped(sources, bundleID: "editor", to: window)
        var failures: [String] = []
        if evidence.total != 420 || evidence.visits.count != 2 {
            failures.append("App detail included another app or the unselected interval")
        }
        if evidence.visits.first?.id != sources[1].id || evidence.visits.last?.start != start {
            failures.append("Clipping lost identity, bounds or newest-first ordering")
        }
        if sources[0].start != start.addingTimeInterval(-600) || sources[1].end != start.addingTimeInterval(900) {
            failures.append("Projection altered source evidence")
        }
        return failures
    }

    private static func legacyRowIdentity() -> [String] {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_782_000_000))
        let start = day.addingTimeInterval(9 * 3_600)
        let identity = UUID()
        // Older archive records used their record ID as the initial thread ID.
        let record = SessionRecord(id: identity, name: "Legacy work", workType: .deepWork,
                                   start: start, end: start.addingTimeInterval(600),
                                   workSeconds: 600, threadID: identity)
        let running = RunningThread(threadID: identity, name: "Legacy work", workType: .deepWork,
                                     start: start.addingTimeInterval(1_200), worked: 600)
        let moments = StoryChronology.build(records: [record], running: running, usage: [], day: day,
                                             now: start.addingTimeInterval(1_800))
        return Set(moments.map(\.id)).count == moments.count ? []
            : ["The archived and running portions shared an ID, so one row/disclosure can replace the other"]
    }

    /// Catches the short-gap grouping pass joining two outside-use fragments
    /// across a real 30-second focus/rest boundary and reintroducing its use.
    private static func chronologyHonoursOccupiedSeparators() -> [String] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_782_000_000))
        let start = day.addingTimeInterval(9 * 3_600)
        let focus = DateInterval(start: start.addingTimeInterval(1_200), duration: 30)
        let rest = DateInterval(start: start.addingTimeInterval(1_800), duration: 30)
        let records = [
            SessionRecord(name: "Quick focus", workType: .deepWork,
                          start: focus.start, end: focus.end, workSeconds: 30),
            SessionRecord(name: "Water", workType: .breakTime,
                          start: rest.start, end: rest.end, workSeconds: 0)
        ]
        let usage = [AppUsageSession(bundleID: "editor", appName: "Editor",
                                     start: start, end: start.addingTimeInterval(3_600))]
        let moments = StoryChronology.build(records: records, running: nil, usage: usage,
                                             day: day, now: start.addingTimeInterval(3_600))
        let outside = moments.compactMap { item -> (DateInterval, TimeInterval)? in
            if case .appUse(let span, let seconds) = item { return (span, seconds) }
            return nil
        }
        var failures: [String] = []
        if outside.reduce(0, { $0 + $1.1 }) != 3_540 {
            failures.append("Outside-use total included occupied focus or rest evidence")
        }
        if outside.contains(where: {
            ($0.0.end > focus.start && $0.0.start < focus.end)
                || ($0.0.end > rest.start && $0.0.start < rest.end)
        }) {
            failures.append("Outside-use span bridged through a known focus or rest boundary")
        }
        if outside.count != 3 {
            failures.append("Occupied short separators did not retain three outside-use fragments")
        }
        return failures
    }

    private static func sparseNarratives() -> [String] {
        var failures: [String] = []
        let appDay = StoryNarrative.day(focused: 0, tracked: 900, sessions: 0, rest: 0, isToday: false)
        let restDay = StoryNarrative.day(focused: 0, tracked: 0, sessions: 0, rest: 600, isToday: false)
        let appWeek = StoryNarrative.period(activeDays: 0, totalDays: 7, focused: 0,
                                            tracked: 900, best: nil, unit: "week")
        if !appDay.contains("15m") || !appDay.contains("app use") || !appWeek.contains("15m") {
            failures.append("Observed app-only evidence was presented as an empty record")
        }
        if !restDay.contains("10m") || !restDay.contains("rest") {
            failures.append("A rest-only day lost its named recording")
        }
        return failures
    }

    private static func snapshotRoutes() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            for (scenario, scope) in [(SnapshotScenario.reviewWeek, StoryScope.week),
                                      (.reviewMonth, .month)] {
                let store = Snapshotter.store(for: scenario)
                let route = Snapshotter.navigation(for: scenario, store: store)
                if route.storyScope != scope || route.sheet != nil {
                    failures.append("\(scenario) rendered a different production surface")
                }
            }
            let history = Snapshotter.store(for: .reviewHistorySelection)
            let route = Snapshotter.navigation(for: .reviewHistorySelection, store: history)
            if route.sheet != .history || route.reviewSelectedDate == nil {
                failures.append("History selection snapshot did not actually present a selected History day")
            }
            let past = Snapshotter.store(for: .todayPast)
            _ = Snapshotter.navigation(for: .todayPast, store: past)
            if past.isToday { failures.append("Past-day snapshot unexpectedly shows today") }
            return failures
        }
    }
}
