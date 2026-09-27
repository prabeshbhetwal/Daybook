import AppKit
import Foundation
import SwiftUI

/// The always-running path does only the work a person could see the result
/// of. Each check pins one saving to the behaviour it must not change.
enum EfficiencyChecks {
    static let tests: [(String, () -> [String])] = [
        ("Binding the window model at launch leaves the dashboard hidden", launchBindingStaysHidden),
        ("A live tail patched into the usage snapshot matches a full rebuild", patchedSnapshotMatchesRebuild),
        ("The menu bar label ignores changes it cannot show", menuBarIgnoresInvisibleChange),
        ("A hidden window rests its content and shows the same view again", hiddenPanelRests),
        ("The break check reads only the latest run and agrees with a full sort", breakCheckReadsLatestRun),
        ("Day totals read only that day and agree with a full scan", dayTotalsReadOnlyTheDay),
        ("A day's story reads only that day's records and agrees with all of them", dayStoryReadsOnlyTheDay)
    ]

    private final class Clock {
        var value: Date
        init(_ value: Date) { self.value = value }
        func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
    }

    private struct Fixture {
        let store: SessionStore
        let usage: AppUsageArchive
        let tracker: AppUsageTracker
        let cleanUp: () -> Void
    }

    private static func makeFixture(_ clock: Clock) -> Fixture? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-efficiency-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "com.prabesh.focuscontinuity.efficiency.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        defaults.removePersistentDomain(forName: suiteName)
        let archive = SessionArchive(directory: directory, now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "com.example.efficiency", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.efficiency",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        return Fixture(store: store, usage: usage, tracker: tracker, cleanUp: {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        })
    }

    private static func noon(daysAgo: Int = 0) -> Date {
        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 12))!
        return calendar.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    /// The window model is built with the app, long before any window. It used
    /// to claim the dashboard as visible, which rebuilt it every second for as
    /// long as the app ran. The first recorded day must still be known then:
    /// Insights and the day stepper bound themselves by it.
    private static func launchBindingStaysHidden() -> [String] {
        MainActor.assumeIsolated {
            let clock = Clock(noon())
            guard let fixture = makeFixture(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            let first = noon(daysAgo: 3)
            fixture.usage.checkpoint(AppUsageSession(bundleID: "editor", appName: "Editor",
                                                     start: first, end: first.addingTimeInterval(600)))
            let navigation = MainWindowModel(selectedTab: .story, storyScope: .day, store: fixture.store)
            _ = navigation
            var problems: [String] = []
            if fixture.store.dashboardVisible {
                problems.append("Binding at launch marked the hidden dashboard visible")
            }
            let expected = Calendar.current.startOfDay(for: first)
            if fixture.store.earliestSelectableDay != expected {
                problems.append("A hidden dashboard left the first recorded day unknown: "
                                + "\(String(describing: fixture.store.earliestSelectableDay))")
            }
            return problems
        }
    }

    /// Each second only the open stretch's end moves. The snapshot patches it
    /// in place instead of copying the archive, and must read exactly as a
    /// snapshot built from scratch — including across the second a new
    /// stretch first becomes long enough to be shown.
    private static func patchedSnapshotMatchesRebuild() -> [String] {
        MainActor.assumeIsolated {
            let clock = Clock(noon())
            guard let fixture = makeFixture(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            for hour in 1...4 {
                let start = clock.value.addingTimeInterval(TimeInterval(-hour * 3_600))
                fixture.usage.checkpoint(AppUsageSession(bundleID: "app.\(hour)", appName: "App \(hour)",
                                                         start: start, end: start.addingTimeInterval(1_200)))
            }
            fixture.tracker.appActivated(bundleID: "editor", name: "Editor")
            var problems: [String] = []
            var builds: [Int] = []
            for _ in 0..<6 {
                clock.advance(1)
                guard let patched = fixture.store.effectiveUsageSnapshot?.sessions else {
                    return ["The fixture has no usage snapshot"]
                }
                let rebuilt = AppUsageSnapshot(archive: fixture.usage, tracker: fixture.tracker).sessions
                if patched != rebuilt {
                    problems.append("Second \(builds.count + 1) read \(patched.count) records, "
                                    + "a rebuild \(rebuilt.count), or their contents differ")
                }
                builds.append(fixture.store.usageSnapshotComputeCount)
            }
            if let last = builds.last, let third = builds.dropFirst(2).first, last != third {
                problems.append("An unchanged archive was rebuilt every second, not patched: \(builds)")
            }
            return problems
        }
    }

    /// The store publishes every second; the status item only when its text,
    /// ring, marks or spoken label would change. The ring is drawn once per
    /// state it shows.
    private static func menuBarIgnoresInvisibleChange() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let goal = GoalProgress(goal: 14_400, achieved: 7_200, typical: nil)
            let nudged = GoalProgress(goal: 14_400, achieved: 7_201, typical: nil)
            let early = MenuBarDisplay(state: .running, elapsed: 125, needsAttention: false,
                                       goal: goal, showsTime: true)
            let later = MenuBarDisplay(state: .running, elapsed: 170, needsAttention: false,
                                       goal: nudged, showsTime: true)
            let nextMinute = MenuBarDisplay(state: .running, elapsed: 185, needsAttention: false,
                                            goal: nudged, showsTime: true)
            let asked = MenuBarDisplay(state: .running, elapsed: 170, needsAttention: true,
                                       goal: nudged, showsTime: true)
            if early != later { problems.append("Seconds inside one shown minute changed the menu bar") }
            if later == nextMinute { problems.append("A new minute did not reach the menu bar") }
            if later == asked { problems.append("A waiting question did not reach the menu bar") }
            if early.time != "2m" || early.progress != 0.5 {
                problems.append("The menu bar reads \(early.time ?? "nothing") at \(early.progress)")
            }
            let first = MenuBarGlyph.image(progress: 0.5, paused: false, attention: false, isMet: false)
            let again = MenuBarGlyph.image(progress: 0.5, paused: false, attention: false, isMet: false)
            if first == nil || first !== again {
                problems.append("An unchanged ring was drawn again")
            }
            return problems
        }
    }

    private final class Beat: ObservableObject {
        @Published var value = 0
        var evaluations = 0
    }

    private struct BeatView: View {
        @ObservedObject var beat: Beat
        var body: some View {
            beat.evaluations += 1
            return Text("\(beat.value)").frame(width: 120, height: 60)
                .background(WindowDormancy())
        }
    }

    /// An ordered-out panel keeps its SwiftUI tree evaluating and drawing on
    /// every change. At rest nothing in it runs; shown again, the very same
    /// content view is back at the same size and following changes.
    private static func hiddenPanelRests() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let beat = Beat()
            let panel = NSPanel(contentRect: NSRect(x: -4_000, y: -4_000, width: 120, height: 60),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            let content = NSHostingView(rootView: BeatView(beat: beat))
            panel.contentView = content
            func spin(ticks: Int) {
                for _ in 0..<max(ticks, 1) {
                    if ticks > 0 { beat.value += 1 }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                }
            }
            panel.orderFront(nil)
            spin(ticks: 3)
            let size = panel.contentView?.frame.size
            let shown = beat.evaluations
            if shown == 0 { problems.append("The shown panel never evaluated its content") }

            panel.orderOut(nil)
            spin(ticks: 0)
            let resting = beat.evaluations
            spin(ticks: 5)
            if panel.contentView === content {
                problems.append("The hidden panel kept its content in the window")
            }
            if beat.evaluations != resting {
                problems.append("Resting content evaluated \(beat.evaluations - resting) times while hidden")
            }

            panel.orderFront(nil)
            spin(ticks: 0)
            if panel.contentView !== content {
                problems.append("Showing the panel did not bring back the same content view")
            }
            if panel.contentView?.frame.size != size {
                problems.append("The content came back at \(String(describing: panel.contentView?.frame.size)), "
                                + "not \(String(describing: size))")
            }
            let woken = beat.evaluations
            spin(ticks: 2)
            if beat.evaluations == woken { problems.append("Woken content stopped following changes") }
            panel.orderOut(nil)
            return problems
        }
    }

    /// Uncapped history made a full sort every five seconds grow without
    /// bound. Only the latest run is sorted now; an ordinary history, a run
    /// that never rests for longer than the look-back, and one that reaches
    /// just past it must all read exactly as a sort of everything does.
    private static func breakCheckReadsLatestRun() -> [String] {
        var problems: [String] = []
        let now = noon()
        let rest = BreakTier.allCases.map(\.restGap).max() ?? 0
        func run(from start: Date, gap: TimeInterval, restEvery: Int?) -> [AppUsageSession] {
            var stretches: [AppUsageSession] = []
            var moment = start
            var index = 0
            while moment < now {
                let length = TimeInterval(60 + (index * 37) % 900)
                stretches.append(AppUsageSession(bundleID: "app.\(index % 3)", appName: "App \(index % 3)",
                                                 start: moment, end: min(now, moment + length)))
                let rests = restEvery.map { index % $0 == $0 - 1 } ?? false
                moment += length + (rests ? rest + 60 : gap)
                index += 1
            }
            // Stored out of order, as recovered history is appended.
            return stretches.enumerated()
                .sorted { ($0.offset * 7_919) % stretches.count < ($1.offset * 7_919) % stretches.count }
                .map(\.element)
        }
        let scenarios: [(String, [AppUsageSession])] = [
            ("an ordinary three days", run(from: now.addingTimeInterval(-3 * 86_400), gap: 45, restEvery: 9)),
            ("a run with no rest for thirty hours", run(from: now.addingTimeInterval(-30 * 3_600),
                                                         gap: 60, restEvery: nil)),
            ("a run reaching just past a day", run(from: now.addingTimeInterval(-BreakReminder.runLookback - 600),
                                                    gap: 30, restEvery: nil))
        ]
        for (name, stretches) in scenarios {
            let result = BreakReminder.evaluate(stretches, now: now, last: nil)
            var done: [BreakTier: TimeInterval] = [:]
            for tier in BreakTier.allCases {
                done[tier] = BreakReminder.worked(stretches, now: now, restingAtLeast: tier.restGap)
            }
            let due = BreakTier.allCases.reversed().first { (done[$0] ?? 0) >= $0.workThreshold }
            var next: (tier: BreakTier, seconds: TimeInterval)?
            for tier in BreakTier.allCases {
                let remaining = max(0, tier.workThreshold - (done[tier] ?? 0))
                if let best = next, !(remaining < best.seconds || (remaining == best.seconds && tier > best.tier)) {
                    continue
                }
                next = (tier, remaining)
            }
            if result.due != due { problems.append("\(name): due \(String(describing: result.due)), full sort \(String(describing: due))") }
            if result.next?.tier != next?.tier || result.next?.seconds != next?.seconds {
                problems.append("\(name): next break differs from a full sort")
            }
            if let due {
                let leader = BreakReminder.dominant(stretches, now: now, within: due.restGap)
                if result.prompt?.worked != done[due] || result.prompt?.appName != leader?.name
                    || result.prompt?.appShare != (leader?.share ?? 0) {
                    problems.append("\(name): the prompt differs from a full sort")
                }
            } else if result.prompt != nil {
                problems.append("\(name): prompted with nothing due")
            }
        }
        return problems
    }

    /// Today's total and goal read the day's records only. Records stored out
    /// of order, one across midnight, and a live stretch patched in each second
    /// must give exactly what a scan of every record gives.
    private static func dayTotalsReadOnlyTheDay() -> [String] {
        MainActor.assumeIsolated {
            let clock = Clock(noon())
            guard let fixture = makeFixture(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: clock.value)
            let records = [
                (midnight.addingTimeInterval(-90_000), 1_800.0),
                (midnight.addingTimeInterval(3_600), 900.0),
                (midnight.addingTimeInterval(-600), 1_500.0),
                (midnight.addingTimeInterval(-172_000), 2_400.0),
                (midnight.addingTimeInterval(7_200), 3_000.0)
            ]
            for (index, record) in records.enumerated() {
                fixture.usage.checkpoint(AppUsageSession(bundleID: "app.\(index)", appName: "App \(index)",
                                                         start: record.0, end: record.0.addingTimeInterval(record.1)))
            }
            fixture.tracker.appActivated(bundleID: "editor", name: "Editor")
            var problems: [String] = []
            for second in 0..<4 {
                clock.advance(1)
                guard let snapshot = fixture.store.effectiveUsageSnapshot else { return ["No usage snapshot"] }
                for offset in 0...2 {
                    guard let day = calendar.date(byAdding: .day, value: -offset, to: clock.value),
                          let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { continue }
                    let full = snapshot.sessions.reduce(0.0) { total, session in
                        let start = max(session.start, bounds.start)
                        let end = min(session.end, bounds.end)
                        return end > start ? total + end.timeIntervalSince(start) : total
                    }
                    if snapshot.total(on: day) != full {
                        problems.append("Second \(second), \(offset) days back: \(snapshot.total(on: day)) not \(full)")
                    }
                    let touching = snapshot.sessions.filter { $0.end > bounds.start && $0.start < bounds.end }
                    if snapshot.sessions(touching: day) != touching {
                        problems.append("Second \(second), \(offset) days back: the day's records differ from a scan")
                    }
                }
            }
            return problems
        }
    }

    /// A day's story — its apps, timeline, goal credit and chronology — was
    /// built from every record ever kept, once more for each session in the
    /// day. It reads the day's records now, and must read exactly the same.
    private static func dayStoryReadsOnlyTheDay() -> [String] {
        MainActor.assumeIsolated {
            let clock = Clock(noon())
            guard let fixture = makeFixture(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: clock.value)
            for (index, offset) in [-90_000.0, 1_200, -900, 5_400, -172_000, 9_000, 2_000].enumerated() {
                let start = midnight.addingTimeInterval(offset)
                fixture.usage.checkpoint(AppUsageSession(bundleID: "app.\(index % 3)", appName: "App \(index % 3)",
                                                         start: start, end: start.addingTimeInterval(1_500)))
            }
            fixture.tracker.appActivated(bundleID: "editor", name: "Editor")
            clock.advance(30)
            let store = fixture.store
            guard let full = store.effectiveUsageSnapshot else { return ["No usage snapshot"] }
            var problems: [String] = []
            for offset in 0...1 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: clock.value) else { continue }
                let everything = DashboardStats(sessions: store.engine.archive, usage: fixture.usage,
                                                usageSnapshot: full)
                let dayOnly = DashboardStats(sessions: store.engine.archive, usage: fixture.usage,
                                             usageSnapshot: full.restricted(to: day))
                if dayOnly.timeline(for: day) != everything.timeline(for: day) {
                    problems.append("\(offset) days back: the day's timeline differs")
                }
                let projection = store.storyDayProjection(on: day)
                if projection.apps != everything.rankedApps(for: day) {
                    problems.append("\(offset) days back: the day's apps differ")
                }
                if projection.goalCredit != store.focusedActiveSeconds(on: day, usageSnapshot: full) {
                    problems.append("\(offset) days back: goal credit differs")
                }
                let moments = Array(StoryChronology.build(records: store.engine.archive.records, running: nil,
                                                          usage: full.sessions, day: day,
                                                          now: store.now()).reversed())
                if store.storyMoments(on: day) != moments {
                    problems.append("\(offset) days back: the chronology differs")
                }
            }
            return problems
        }
    }
}
