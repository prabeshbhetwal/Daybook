import SwiftUI
import AppKit

/// Cross-feature regressions: each check exercises two features that own
/// separate state and asserts through consumer state, never source strings.
/// No live coordinator, app inventory, ticker or power observer is created.
enum StoryIntegrationChecks {
    static let tests: [(String, () -> [String])] = [
        ("Continuing after a saved note keeps the note on its own stretch", continueAfterNote),
        ("Undoing an older receipt leaves an open inline Month story in place", undoWithMonthChildOpen),
        ("Editing activity rules never collapses a pinned session strip", ruleEditWithPinnedStrip),
        ("Switching Insights scope leaves the Story selection untouched", insightsLeaveStory),
        ("Power and no-power fixtures render the same story with factual metadata", powerAndNoPower),
        ("Reduce Motion drops every product animation to instant", reduceMotionContract),
        ("An automatic start reaches the session controls once the main queue turns",
         automaticStartReachesControls),
        ("The week chart and its headline rank the same strongest day", weekChartMatchesHeadline)
    ]

    // MARK: - Fixture

    /// Injected time, so every duration is deterministic and no test sleeps.
    private final class Clock {
        var value: Date
        init(_ value: Date) { self.value = value }
        func advance(_ seconds: TimeInterval) { value = value.addingTimeInterval(seconds) }
    }

    private final class Fixture {
        let directory: URL
        let suite: String
        let clock: Clock
        let persistence: PersistenceStore
        let archive: SessionArchive
        let engine: SessionEngine
        let metadata: SessionMetadataArchive
        let store: SessionStore

        init(powerMonitor: PowerSourceMonitoring? = nil) {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("fc-integration-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            suite = "com.prabesh.focuscontinuity.integration.\(UUID().uuidString)"
            clock = Clock(Date(timeIntervalSince1970: 1_788_598_000))
            persistence = PersistenceStore(defaults: UserDefaults(suiteName: suite)!)
            archive = SessionArchive(directory: directory, now: { [clock] in clock.value })
            engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.integration", schedulesDwell: false,
                                   now: { [clock] in clock.value })
            metadata = SessionMetadataArchive(directory: directory)
            store = SessionStore(engine: engine, schedulesTicker: false,
                                 metadataArchive: metadata, powerMonitor: powerMonitor,
                                 now: { [clock] in clock.value })
            // Day entries and review rollups are computed only from an attached
            // usage archive while a surface shows them — the same shape the
            // production coordinator attaches, with idle observation disabled.
            let usage = AppUsageArchive(directory: directory, now: { [clock] in clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.integration",
                                          idle: .disabled, now: { [clock] in clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.setDashboardVisible(true)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }

        /// One absence past the question threshold, ended, so a decision is
        /// pending. Uses the engine's own events rather than a store shortcut.
        func absence() {
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(engine.breakThreshold + 120)
            engine.transition(on: .awayEnded)
        }

        func firstSession() -> DaySession? {
            for entry in store.daySessions {
                if case .session(let session) = entry { return session }
            }
            return nil
        }
    }

    private final class FakePowerMonitor: PowerSourceMonitoring {
        let sample: PowerObservation
        var handler: ((PowerObservation) -> Void)?
        init(sample: PowerObservation) { self.sample = sample }
        func observation(at timestamp: Date, boundary: PowerCoverageBoundary?) -> PowerObservation {
            PowerObservation(timestamp: timestamp, source: sample.source,
                             percentage: sample.percentage, charging: sample.charging,
                             boundary: boundary)
        }
        func start(_ handler: @escaping (PowerObservation) -> Void) { self.handler = handler }
        func stop() {}
    }

    // MARK: - Checks

    /// The headline names a strongest day; the chart draws a tallest bar. They
    /// must be the same day, or the screen answers "which day was best?" twice
    /// and disagrees with itself. The bar therefore plots the measure the
    /// headline ranks — logged focus — not recorded app use.
    private static func weekChartMatchesHeadline() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.setDashboardVisible(true)
            store.setReviewVisible(true)
            store.refreshReview(period: .week)
            var failures: [String] = []
            guard let best = store.reviewBestDay else {
                return ["The week fixture published no strongest day to compare"]
            }
            let facts = store.dayFacts(for: .week, containing: store.reviewPeriodStart)
            guard let tallest = facts.max(by: { $0.value.focused < $1.value.focused }) else {
                return ["The week fixture published no per-day facts"]
            }
            let calendar = Calendar.current
            if !calendar.isDate(tallest.key, inSameDayAs: best.day) {
                failures.append("The headline names \(Tokens.longDate(best.day)) but the tallest "
                                + "focus bar is \(Tokens.longDate(tallest.key))")
            }
            if abs(tallest.value.focused - best.focused) > 1 {
                failures.append("The headline says \(best.focused)s but the tallest bar draws "
                                + "\(tallest.value.focused)s")
            }
            // Being busy must not win the day: the most-tracked day only leads
            // when it also holds the most focus.
            if let busiest = store.reviewDays.max(by: { $0.tracked < $1.tracked }),
               !calendar.isDate(busiest.date, inSameDayAs: best.day) {
                let busiestFocus = facts[calendar.startOfDay(for: busiest.date)]?.focused ?? 0
                if busiestFocus > tallest.value.focused {
                    failures.append("The busiest day outranked the most focused one")
                }
            }
            return failures
        }
    }

    /// The engine's state reaches the store's mirror on the main queue. Every
    /// Focus surface reads that mirror, so a rule-started session must show as
    /// running there — not only in the story, which reads the engine directly.
    private static func automaticStartReachesControls() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.activityRuleStore(ambiguous: false)
            defer { FixtureFactory.cleanUp() }
            var failures: [String] = []
            if store.engine.state != .running {
                return ["the automatic fixture did not start a session"]
            }
            let composition = store.focusSurfaceComposition
            if composition.mode == .idle {
                failures.append("the Focus surfaces still present the idle hero after an automatic start")
            }
            if !composition.showsAutomaticSessionControls {
                failures.append("the automatic session did not expose its automatic controls")
            }
            if store.isIdle {
                failures.append("the chrome pill would still offer Start focus during an automatic session")
            }
            return failures
        }
    }

    /// A still capture cannot show motion and the system flag cannot be forced
    /// through the environment, so the Reduce Motion contract is verified on
    /// the one function every animated surface routes through.
    private static func reduceMotionContract() -> [String] {
        var failures: [String] = []
        let bases: [(String, Animation)] = [
            ("selection", Tokens.Motion.selection),
            ("rise", Tokens.Motion.rise),
            ("hover", Tokens.Motion.hover)
        ]
        for (name, base) in bases {
            if Tokens.Motion.animation(base, reduceMotion: true) != nil {
                failures.append("Reduce Motion left the \(name) animation in place")
            }
            if Tokens.Motion.animation(base, reduceMotion: false) == nil {
                failures.append("the \(name) animation vanished without Reduce Motion")
            }
        }
        return failures
    }

    private static func continueAfterNote() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            var failures: [String] = []
            f.engine.start(workType: .deepWork, intent: "Parser")
            f.store.refresh()
            let firstRecord = f.engine.activeRecordID
            f.store.beginNoteEditing(for: firstRecord)
            f.store.setNoteDraft("wrote the tokenizer", for: firstRecord)
            guard f.store.saveNote(for: firstRecord) else { return ["the note did not save"] }
            f.clock.advance(1_800)
            f.engine.stop()
            f.store.refresh()
            guard let session = f.firstSession() else { return ["the stretch did not reach the story"] }
            f.clock.advance(300)
            f.store.continueSession(session)
            f.store.refresh()
            if f.engine.state != .running || f.engine.activeThreadID != session.threadID {
                failures.append("continuing after a note did not resume the same thread")
            }
            if f.engine.activeRecordID == firstRecord {
                failures.append("continuing reused the noted stretch's identity instead of a new one")
            }
            if f.metadata.metadata(for: firstRecord)?.note != "wrote the tokenizer" {
                failures.append("the saved note left its original stretch after continuing")
            }
            if f.metadata.metadata(for: f.engine.activeRecordID)?.note != nil {
                failures.append("the new stretch inherited a note it never had")
            }
            return failures
        }
    }

    private static func undoWithMonthChildOpen() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser")
            f.absence()
            guard f.store.resolve(.tookBreak), let first = f.engine.lastAwayDecision else {
                return ["first answer setup failed"]
            }
            f.absence()
            guard f.store.resolve(.tookBreak), f.engine.lastAwayDecision != nil else {
                return ["second answer setup failed"]
            }
            f.clock.advance(300)
            f.engine.stop()
            f.store.refresh()
            let navigation = MainWindowModel(storyScope: .month, store: f.store)
            let today = f.clock.value
            navigation.selectStoryDay(today)
            navigation.openStoryDay(today)
            let scopeBefore = navigation.storyScope
            let selectedBefore = navigation.storySelectedDay
            guard navigation.expandedStoryDay != nil else {
                return ["the inline Month child did not open before the Undo"]
            }
            var failures: [String] = []
            guard f.store.undoAwayDecision(expectedID: first.id) else {
                return ["the older receipt was unavailable with the Month child open"]
            }
            f.store.refresh()
            if navigation.storyScope != scopeBefore {
                failures.append("Undo changed the Story scope")
            }
            if navigation.storySelectedDay != selectedBefore {
                let days = f.store.reviewDays.map { Tokens.longDate($0.date) }
                failures.append("Undo changed the selected Month day "
                    + "(selected \(Tokens.longDate(today)); review days \(days); "
                    + "anchor \(f.store.reviewAnchor.map(Tokens.longDate) ?? "nil"))")
            }
            if navigation.expandedStoryDay == nil {
                failures.append("Undo closed the inline Month child")
            }
            return failures
        }
    }

    private static func ruleEditWithPinnedStrip() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            let settings = SettingsModel(store: f.persistence, isTrackingEnabled: true,
                onChange: {}, onTrackingChanged: { _ in },
                installedAppCatalog: FixtureFactory.installedAppCatalog())
            let navigation = MainWindowModel(store: f.store)
            settings.sessionControlsPinned = true
            navigation.performSessionControlsAction(.commandOrMenu)
            let expandedBefore = navigation.sessionControlsExpanded
            var failures: [String] = []
            f.persistence.activityRules = [
                ActivityRule(name: "Coding", workType: .deepWork,
                             bundleIDs: ["com.example.code"], startAfter: 180)
            ]
            f.persistence.activityRuleAutomationEnabled = true
            f.store.refresh()
            if !SessionControlsVisibility.isVisible(expanded: navigation.sessionControlsExpanded,
                                                    pinned: settings.sessionControlsPinned) {
                failures.append("a rule edit hid the pinned session strip")
            }
            if navigation.sessionControlsExpanded != expandedBefore {
                failures.append("a rule edit changed the strip's expanded state")
            }
            if f.engine.state != .idle {
                failures.append("adding a rule started a session by itself")
            }
            if f.store.pendingActivityChoice != nil {
                failures.append("adding a rule presented a quiet choice with no evidence")
            }
            let reopened = SettingsModel(store: PersistenceStore(defaults: UserDefaults(suiteName: f.suite)!),
                isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in },
                installedAppCatalog: FixtureFactory.installedAppCatalog())
            if !reopened.sessionControlsPinned {
                failures.append("the pin did not survive alongside the rule edit")
            }
            return failures
        }
    }

    private static func insightsLeaveStory() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let navigation = MainWindowModel(storyScope: .week, store: store)
            guard let day = store.reviewDays.first?.date else { return ["no review day to select"] }
            navigation.selectStoryDay(day)
            var failures: [String] = []
            for range in InsightRange.allCases {
                navigation.selectInsightRange(range)
                if navigation.storyScope != .week {
                    failures.append("selecting Insights \(range) changed the Story scope")
                }
                if navigation.storySelectedDay != day {
                    failures.append("selecting Insights \(range) changed the selected Story day")
                }
            }
            return failures
        }
    }

    private static func powerAndNoPower() -> [String] {
        MainActor.assumeIsolated {
            let monitor = FakePowerMonitor(sample: PowerObservation(
                timestamp: Date(timeIntervalSince1970: 1_788_598_000),
                source: .battery, percentage: 78, charging: .notCharging))
            let powered = Fixture(powerMonitor: monitor)
            let plain = Fixture()
            defer { powered.cleanUp(); plain.cleanUp() }
            var failures: [String] = []
            for (label, f) in [("powered", powered), ("no-power", plain)] {
                f.engine.start(workType: .deepWork, intent: "Parser")
                f.store.refresh()
                let record = f.engine.activeRecordID
                f.clock.advance(1_200)
                f.engine.stop()
                f.store.refresh()
                let observations = f.metadata.metadata(for: record)?.power ?? []
                if label == "powered", observations.isEmpty {
                    failures.append("the powered fixture recorded no power observation")
                }
                if label == "no-power", !observations.isEmpty {
                    failures.append("the no-power fixture invented power observations")
                }
                if f.firstSession() == nil {
                    failures.append("the \(label) fixture's stretch did not reach the story")
                }
            }
            if plain.store.powerMonitor != nil {
                failures.append("the no-power fixture acquired a power monitor")
            }
            return failures
        }
    }
}
