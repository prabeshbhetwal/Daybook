import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 84

    /// The popover must still fit a 13" screen after the hero grew a ring and
    /// the glance became cards. Measured with the real view: render the
    /// densest fixture at the 13" metrics and check its height against the
    /// screen's share, the same way the harness does.
    static func testPopoverStillFits13Inch() -> [String] {
        var problems: [String] = []
        let metrics = PopoverMetrics.fitting(CGSize(width: 1_440, height: 845))
        let height: CGFloat = MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .needsResolution)
            let defaults = MemoryDefaults.suite(named: suiteName) ?? .standard
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let settings = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let view = PopoverView(store: store, settings: settings,
                                   metricsOverride: metrics, scrolls: false)
                .frame(width: metrics.width)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return renderer.nsImage?.size.height ?? .infinity
        }
        expect(height <= metrics.maxHeight,
               "needs-resolution panel is \(Int(height))pt, budget \(Int(metrics.maxHeight))",
               &problems)
        return problems
    }

    // MARK: - 85

    /// Which prompt an absence gets is a pure rule, and "Never" must mean the
    /// quick one rather than none — the question is still asked.
    static func testAwayPromptTier() -> [String] {
        var problems: [String] = []
        expect(AwayPromptTier.tier(forAbsence: 20 * 60, fullPromptAfter: 30 * 60) == .quick,
               "under the threshold is quick", &problems)
        expect(AwayPromptTier.tier(forAbsence: 30 * 60, fullPromptAfter: 30 * 60) == .full,
               "at the threshold is full", &problems)
        expect(AwayPromptTier.tier(forAbsence: 3 * 3_600, fullPromptAfter: 30 * 60) == .full,
               "well over is full", &problems)
        expect(AwayPromptTier.tier(forAbsence: 3 * 3_600, fullPromptAfter: nil) == .quick,
               "Never means always quick", &problems)

        let defaults = MemoryDefaults.suite(named: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        expectClose(store.fullPromptAfter ?? -1, FocusConstants.defaultFullPromptAfter,
                    "missing key reads as the default", &problems)
        store.fullPromptAfter = nil
        expect(store.fullPromptAfter == nil, "Never round-trips as nil", &problems)
        store.fullPromptAfter = 3_600
        expectClose(store.fullPromptAfter ?? -1, 3_600, "a value round-trips", &problems)
        return problems
    }

    // MARK: - 86

    /// The card says when, not only how long. The range is derived from the
    /// return moment the engine already stamps, so it cannot disagree with the
    /// length beside it.
    static func testPendingAwayRange() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Range")
        expect(engine.pendingAwayRange == nil, "nothing pending while running", &problems)
        clock.advance(600)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(22 * 60)
        engine.transition(on: .awayEnded)
        guard let range = engine.pendingAwayRange else {
            return problems + ["a 22-minute lock should leave a pending range"]
        }
        expectClose(range.end.timeIntervalSince(range.start), 22 * 60,
                    "the range spans the absence", &problems)
        expectClose(range.end.timeIntervalSince(clock.value), 0,
                    "and ends when the user came back", &problems)

        // A relaunch three hours later must not move the absence: the card
        // still says when it was, not when the app came back up.
        let snapshot = engine.snapshot()
        let returned = clock.value
        clock.advance(3 * 3_600)
        let revived = makeEngine(clock)
        revived.restore(from: snapshot)
        guard let kept = revived.pendingAwayRange else {
            return problems + ["restored card should still carry its range"]
        }
        expectClose(kept.end.timeIntervalSince(returned), 0,
                    "the range still ends at the real return", &problems)
        expectClose(kept.end.timeIntervalSince(kept.start), 22 * 60,
                    "and still spans the absence", &problems)

        engine.transition(on: .decision(.continueSession))
        expect(engine.pendingAwayRange == nil, "answered means no range", &problems)
        return problems
    }

    // MARK: - 87

    /// After a break the clock must pick up where it left off: the running
    /// thread's earlier stretches today plus the live one, never a stretch
    /// alone, and never another thread's work.
    static func testThreadClock() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = MemoryDefaults.suite(named: suiteName) ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let archive = SessionArchive(directory: directory)
        let engine = SessionEngine(store: prefs, archive: archive,
                                   ownBundleID: "com.test", schedulesDwell: false)
        let thread = UUID()
        let now = anchoredNow()
        archive.append(SessionRecord(name: "Deep work", workType: .deepWork,
                                     start: now.addingTimeInterval(-3_000),
                                     end: now.addingTimeInterval(-1_200),
                                     workSeconds: 1_800, threadID: thread))
        archive.append(SessionRecord(name: "Deep work", workType: .deepWork,
                                     start: now.addingTimeInterval(-900),
                                     end: now.addingTimeInterval(-300),
                                     workSeconds: 600, threadID: thread))
        archive.append(SessionRecord(name: "Email", workType: .admin,
                                     start: now.addingTimeInterval(-2_400),
                                     end: now.addingTimeInterval(-2_100),
                                     workSeconds: 300))
        engine.start(workType: .deepWork, intent: "Deep work", threadID: thread)

        let store = SessionStore(engine: engine)
        store.refresh()
        expect(abs(store.threadElapsed - 2_400) < 5,
               "thread clock carries both earlier stretches, got \(Int(store.threadElapsed))",
               &problems)
        expect(store.threadSegments == 3, "three stretches, got \(store.threadSegments)", &problems)
        expect(store.continuationNote?.contains("Deep work continues") == true,
               "the card says which work carries on", &problems)

        engine.stop()
        store.refresh()
        expect(store.threadElapsed == 0 && store.threadSegments == 0,
               "idle means no thread clock", &problems)
        return problems
    }

    // MARK: - 88

    /// Back from the kitchen into the same app: the same thread, clock and
    /// all. Back into something unrelated: new work, and the old thread kept
    /// for Continue rather than stretched over it. "I was working" and "Start
    /// fresh" are unaffected — they already say what they mean.
    static func testAppAwareContinuity() -> [String] {
        var problems: [String] = []
        func scenario(returnTo app: String?, decision: UserDecision,
                      matcher: ((String?) -> Bool)?) -> (same: Bool, name: String) {
            let clock = TestClock(base)
            let engine = makeEngine(clock)
            engine.threadContextMatcher = matcher
            engine.transition(on: .appActivated(bundleID: "com.ide", name: "IDE"))
            engine.start(workType: .deepWork, intent: "Refactor")
            let thread = engine.activeThreadID
            clock.advance(1_800)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(22 * 60)
            engine.transition(on: .awayEnded)
            if let app {
                engine.transition(on: .appActivated(bundleID: app, name: app))
            }
            engine.transition(on: .decision(decision))
            return (engine.activeThreadID == thread, engine.sessionName)
        }
        let ideOnly: (String?) -> Bool = { $0 == "com.ide" }

        expect(scenario(returnTo: nil, decision: .tookBreak, matcher: ideOnly).same,
               "same app on return keeps the thread", &problems)
        expect(scenario(returnTo: "com.ide", decision: .continueSession, matcher: ideOnly).same,
               "re-activating the same app keeps it too", &problems)
        let switched = scenario(returnTo: "com.browser", decision: .tookBreak, matcher: ideOnly)
        expect(!switched.same, "a different app starts new work", &problems)
        expect(switched.name.isEmpty, "and the new work does not inherit the old name", &problems)
        expect(scenario(returnTo: "com.browser", decision: .tookBreak, matcher: nil).same,
               "without a matcher the thread is kept — callers without usage data", &problems)
        expect(scenario(returnTo: "com.browser", decision: .mergeTime, matcher: ideOnly).same,
               "'I was working' never re-threads", &problems)
        expect(!scenario(returnTo: nil, decision: .resetTimer, matcher: ideOnly).same,
               "'Start fresh' always does", &problems)
        return problems
    }

    // MARK: - 89

    /// The rhythm chart sums tracked seconds per hour, splitting a stretch that
    /// crosses the hour, colours the hour by the app that took most of it, and
    /// names the busiest run.
    static func testRhythm() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func seg(_ fromMinutes: Double, _ toMinutes: Double, color: Int) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: "b\(color)", appName: "A\(color)",
                            start: day.addingTimeInterval(fromMinutes * 60),
                            end: day.addingTimeInterval(toMinutes * 60), colorIndex: color)
        }
        // 9:00–10:30 app 0 (crosses 10:00), 10:20–10:40 app 1, 11:00–11:10 app 2.
        let segments = [seg(9 * 60, 10 * 60 + 30, color: 0),
                        seg(10 * 60 + 20, 10 * 60 + 40, color: 1),
                        seg(11 * 60, 11 * 60 + 10, color: 2)]
        let hours = Rhythm.hours(segments: segments,
                                 window: (day.addingTimeInterval(9 * 3_600),
                                          day.addingTimeInterval(12 * 3_600)),
                                 calendar: calendar)
        expect(hours.count == 3, "three hours in the window, got \(hours.count)", &problems)
        guard hours.count == 3 else { return problems }
        expectClose(hours[0].seconds, 3_600, "9am is a full hour of app 0", &problems)
        expect(hours[0].colorIndex == 0, "and coloured by it", &problems)
        expectClose(hours[1].seconds, 1_800 + 1_200, "10am sums both apps", &problems)
        expect(hours[1].colorIndex == 0, "app 0's 30m beats app 1's 20m", &problems)
        expectClose(hours[2].seconds, 600, "11am has ten minutes", &problems)
        let label = Rhythm.peakLabel(hours) { date in
            "\(calendar.component(.hour, from: date))h"
        }
        // The run covers the 9 and 10 o'clock hours, so it ends at 11 — the
        // same convention as "4–6am" for the hours 4 and 5.
        expect(label == "9h–11h", "peak run is 9–11, got \(label ?? "nil")", &problems)
        expect(Rhythm.peakLabel([]) { _ in "" } == nil, "no hours, no peak", &problems)
        return problems
    }
}
