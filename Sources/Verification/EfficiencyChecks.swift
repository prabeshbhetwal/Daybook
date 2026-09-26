import AppKit
import Foundation

/// The always-running path does only the work a person could see the result
/// of. Each check pins one saving to the behaviour it must not change.
enum EfficiencyChecks {
    static let tests: [(String, () -> [String])] = [
        ("Binding the window model at launch leaves the dashboard hidden", launchBindingStaysHidden),
        ("A live tail patched into the usage snapshot matches a full rebuild", patchedSnapshotMatchesRebuild),
        ("The menu bar label ignores changes it cannot show", menuBarIgnoresInvisibleChange)
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
}
