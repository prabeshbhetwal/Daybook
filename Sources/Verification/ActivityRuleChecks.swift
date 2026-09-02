import Foundation
import SwiftUI
import AppKit

/// Behavioural checks for the activity-rule model, pure detector and the
/// one-shot automation consumer. These fixtures contain invented bundle IDs;
/// installed applications on the build Mac are never enumerated.
enum ActivityRuleChecks {
    static let tests: [(String, () -> [String])] = [
        ("Activity rules normalise identity and validate dwell choices", modelValidation),
        ("Shared applications remain one ambiguous qualifying run", sharedAmbiguity),
        ("Candidate intersections retain exclusive context but never relabel ambiguity", membershipIntersection),
        ("Each supported dwell fires at its literal boundary", dwellBoundaries),
        ("Established and manual activity ownership wins shared support apps", ownershipPrecedence),
        ("Exclusive automatic switches begin at the exclusive boundary", exclusiveSwitchBoundary),
        ("Rule deadlines fire once without another app activation", oneShotDeadline),
        ("Rule callbacks fail closed after edits, absence and tracking changes", staleDeadlineSafety),
        ("A Stop mid-dwell never re-credits archived time to a new start", stopMidDwell),
        ("An automatic start refuses evidence that overlaps archived work", overlapRefusal),
        ("Quiet choices freeze external evidence and reject stale selection", quietChoiceSafety),
        ("Activity rule preferences preserve legacy, opt-in and all-off modes", preferenceModes),
        ("Automatic actions retain exact reason and identity-bound Undo", exactActionIdentity),
        ("Session consumer persists exact automatic start provenance", consumerStartAndReload),
        ("Session consumer switches atomically without duplicate time", consumerSwitchAccounting),
        ("Automatic switch interruption restores one authoritative owner", switchInterruptionRecovery),
        ("Failed automatic switch preserves the established owner", switchFailureSafety),
        ("Stale Undo, cooldown and manual correction preserve newer work", undoCooldownAndCorrection),
        ("All-off activation records context without starting focus", allOffActivationGate),
        ("Quiet choice renders in both compact control surfaces", quietChoiceConsumers),
        ("Rule editor validates custom dwell and owns a scrollable injected picker", editorConsumer),
        ("Installed-app discovery deduplicates injected local sources", catalogDiscovery),
        ("Run-loop discovery turns the worker's loop rather than blocking it",
         catalogRunLoopWait),
        ("Installed-app picker renders a row per published application", pickerRows)
    ]

    private static let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private static let codingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private static let researchID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private static let recordID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    private static func rule(_ id: UUID, _ name: String, _ seconds: TimeInterval,
                             _ apps: Set<String>) -> ActivityRule {
        ActivityRule(id: id, name: name, workType: .deepWork,
                     bundleIDs: apps, isEnabled: true, startAfter: seconds)
    }

    private static var rules: [ActivityRule] {
        [rule(codingID, " Coding ", 60, ["com.example.code", "com.example.shared"]),
         rule(researchID, "Research", 180, ["com.example.research", "com.example.shared"])]
    }

    private static func input(at seconds: TimeInterval,
                              app: String? = "com.example.shared",
                              foreground: Bool = true,
                              presence: ActivityPresence = .present,
                              tracking: Bool = true,
                              version: UInt64 = 1,
                              ownership: ActivityOwnership = .none,
                              pending: Bool = false,
                              coverageStart: TimeInterval = 0,
                              customRules: [ActivityRule]? = nil,
                              foregroundGeneration: UInt64 = 0,
                              controlsAreForeground: Bool? = nil) -> ActivityRuleInput {
        ActivityRuleInput(timestamp: t0.addingTimeInterval(seconds),
                          foregroundBundleID: app,
                          foregroundIsActive: foreground,
                          controlsAreForeground: controlsAreForeground
                            ?? (app == FocusConstants.bundleIdentifier),
                          foregroundGeneration: foregroundGeneration,
                          presence: presence,
                          trackingEnabled: tracking,
                          automationEnabled: true,
                          ruleVersion: version,
                          rules: customRules ?? Self.rules,
                          ownership: ownership,
                          pendingManualState: pending,
                          recordingCoverage: DateInterval(
                            start: t0.addingTimeInterval(coverageStart),
                            end: t0.addingTimeInterval(seconds)))
    }

    private static func modelValidation() -> [String] {
        let item = ActivityRule(id: codingID, name: "  Coding  ", workType: .deepWork,
            bundleIDs: [" COM.Example.Code ", "com.example.code", ""],
            isEnabled: true, startAfter: 180)
        var failures: [String] = []
        if item.id != codingID || item.name != "Coding"
            || item.bundleIDs != ["com.example.code"] || item.startAfter != 180 {
            failures.append("Rule normalisation changed identity or retained duplicate membership")
        }
        if ActivityRule.defaultStartAfter != 180
            || ActivityRule.startAfterPresets != [30, 60, 180, 300] {
            failures.append("Default or preset dwell values differ from 180 and 30/60/180/300")
        }
        for text in ["29", "1801", "30.5", "three minutes", ""] {
            if case .success = ActivityRule.validateCustomStartAfter(text) {
                failures.append("Invalid custom dwell \(text.debugDescription) was accepted")
            }
        }
        for text in ["30", "60", "180", "300", "1800"] {
            guard case .success(let value) = ActivityRule.validateCustomStartAfter(text),
                  value == TimeInterval(Int(text)!) else {
                failures.append("Valid whole-second dwell \(text) was rejected"); continue
            }
        }
        return failures
    }

    private static func sharedAmbiguity() -> [String] {
        var detector = ActivityRuleDetector()
        let first = detector.evaluate(input(at: 0))
        let early = detector.evaluate(input(at: 60))
        let due = detector.evaluate(input(at: 180))
        var failures: [String] = []
        if first.deadline?.fireAt != t0.addingTimeInterval(180) || early.isMutation {
            failures.append("Shared membership used the shorter Coding dwell as a winner")
        }
        guard case .ambiguous(let choice) = due,
              choice.candidates.map(\.ruleID) == [codingID, researchID],
              choice.evidence.start == t0, choice.evidence.end == t0.addingTimeInterval(180)
        else { failures.append("Shared qualifying run did not produce one ordered quiet choice"); return failures }
        if choice.candidates.count != 2 { failures.append("Shared app produced duplicate clocks") }
        return failures
    }

    private static func membershipIntersection() -> [String] {
        var failures: [String] = []
        var exclusiveFirst = ActivityRuleDetector()
        _ = exclusiveFirst.evaluate(input(at: 0, app: "com.example.code"))
        let shared = exclusiveFirst.evaluate(input(at: 30, app: "com.example.shared"))
        if shared.deadline?.qualifyingStart != t0
            || shared.deadline?.fireAt != t0.addingTimeInterval(60) {
            failures.append("Exclusive Coding did not retain its boundary through shared Chrome")
        }
        let due = exclusiveFirst.evaluate(input(at: 60, app: "com.example.shared"))
        if case .start(let action) = due, action.ruleID == codingID, action.evidence.start == t0 {
            // expected
        } else { failures.append("Shared support app did not resolve to established Coding") }

        var ambiguousFirst = ActivityRuleDetector()
        _ = ambiguousFirst.evaluate(input(at: 0))
        let exclusive = ambiguousFirst.evaluate(input(at: 120, app: "com.example.code"))
        if exclusive.deadline?.qualifyingStart != t0.addingTimeInterval(120)
            || exclusive.deadline?.fireAt != t0.addingTimeInterval(180) {
            failures.append("Ambiguous run was retroactively labelled at the exclusive boundary")
        }
        return failures
    }

    private static func dwellBoundaries() -> [String] {
        var failures: [String] = []
        for seconds in ActivityRule.startAfterPresets {
            let only = [rule(codingID, "Coding", seconds, ["com.example.code"])]
            var detector = ActivityRuleDetector()
            let initial = detector.evaluate(input(at: 0, app: "com.example.code",
                                                  customRules: only))
            let early = detector.evaluate(input(at: seconds - 1, app: "com.example.code",
                                                customRules: only))
            let due = detector.evaluate(input(at: seconds, app: "com.example.code",
                                              customRules: only))
            if initial.deadline?.fireAt != t0.addingTimeInterval(seconds) || early.isMutation {
                failures.append("\(Int(seconds))s dwell fired before its literal deadline")
            }
            guard case .start(let action) = due, action.evidence.duration == seconds else {
                failures.append("\(Int(seconds))s dwell did not fire at its literal deadline")
                continue
            }
        }
        return failures
    }

    private static func ownershipPrecedence() -> [String] {
        var detector = ActivityRuleDetector()
        var failures: [String] = []
        let manual = detector.evaluate(input(at: 240,
            ownership: .manual(activityName: "Coding", workType: .deepWork)))
        if manual != .none { failures.append("Manual Coding was eligible for silent relabelling") }

        let automatic = ActivityOwnership.automatic(ruleID: codingID, recordID: recordID)
        let shared = detector.evaluate(input(at: 300, ownership: automatic))
        if shared != .none { failures.append("Shared support app displaced established Coding") }
        return failures
    }

    private static func exclusiveSwitchBoundary() -> [String] {
        var detector = ActivityRuleDetector()
        _ = detector.evaluate(input(at: 0))
        _ = detector.evaluate(input(at: 180))
        let automatic = ActivityOwnership.automatic(ruleID: codingID, recordID: recordID)
        let boundary = detector.evaluate(input(at: 300, app: "com.example.research",
                                               ownership: automatic))
        let due = detector.evaluate(input(at: 480, app: "com.example.research",
                                          ownership: automatic))
        var failures: [String] = []
        if boundary.deadline?.qualifyingStart != t0.addingTimeInterval(300) {
            failures.append("Exclusive Research qualification was backdated into earlier ambiguity")
        }
        guard case .switchActivity(let action) = due,
              action.ruleID == researchID,
              action.evidence.start == t0.addingTimeInterval(300),
              action.expectedRecordID == recordID else {
            failures.append("Exclusive Research did not produce an identity-bound switch"); return failures
        }
        return failures
    }

    private final class TestDeadline: ActivityDeadlineCancellation {
        var isCancelled = false
        func cancel() { isCancelled = true }
    }

    private final class TestScheduler: ActivityDeadlineScheduling {
        var scheduled: [(Date, TestDeadline, () -> Void)] = []
        func schedule(at date: Date, _ action: @escaping () -> Void) -> ActivityDeadlineCancellation {
            let token = TestDeadline(); scheduled.append((date, token, action)); return token
        }
        func fireLatest() { scheduled.last?.2() }
    }

    private static func oneShotDeadline() -> [String] {
        let scheduler = TestScheduler()
        var current = input(at: 0, app: "com.example.code")
        var actions: [ActivityRuleResult] = []
        let automation = ActivityAutomation(scheduler: scheduler,
            input: { current }, apply: { actions.append($0) })
        automation.observe(current)
        current = input(at: 60, app: "com.example.code")
        scheduler.fireLatest()
        var failures: [String] = []
        guard case .start(let action) = actions.last,
              action.evidence == DateInterval(start: t0, end: t0.addingTimeInterval(60))
        else { failures.append("One-shot deadline did not fire without another app switch"); return failures }
        if scheduler.scheduled.count != 1 { failures.append("Deadline consumer scheduled a repeating rule ticker") }
        return failures
    }

    private static func staleDeadlineSafety() -> [String] {
        let invalidations: [(String, (ActivityRuleInput) -> ActivityRuleInput)] = [
            ("rule edit", { value in value.replacing(ruleVersion: 2) }),
            ("lock", { value in value.replacing(presence: .locked) }),
            ("sleep", { value in value.replacing(presence: .sleeping) }),
            ("Away", { value in value.replacing(presence: .away) }),
            ("manual pause", { value in value.replacing(pendingManualState: true) }),
            ("tracking off", { value in value.replacing(trackingEnabled: false) }),
            ("background activation", { value in value.replacing(foregroundIsActive: false) })
        ]
        var failures: [String] = []
        for (label, mutate) in invalidations {
            let scheduler = TestScheduler()
            var current = input(at: 0, app: "com.example.code")
            var actions: [ActivityRuleResult] = []
            let automation = ActivityAutomation(scheduler: scheduler,
                input: { current }, apply: { actions.append($0) })
            automation.observe(current)
            current = mutate(input(at: 60, app: "com.example.code"))
            scheduler.fireLatest()
            if actions.contains(where: \.isMutation) {
                failures.append("A stale deadline mutated after \(label)")
            }
        }
        return failures
    }

    /// A qualifying run begun while an automatic session is live must not
    /// outlive that session's Stop. Time before the Stop is already archived;
    /// only a run begun after it may qualify.
    private static func stopMidDwell() -> [String] {
        let coding = ActivityRule(name: "Coding", workType: .deepWork,
                                  bundleIDs: ["com.example.code"], startAfter: 60)
        let research = ActivityRule(name: "Research", workType: .learning,
                                    bundleIDs: ["com.example.research"], startAfter: 60)
        let rules = [coding, research]
        let owner = UUID()
        var failures: [String] = []

        // Exclusive switch candidacy, then Stop before the dwell elapses.
        do {
            let scheduler = TestScheduler()
            var current = input(at: 0, app: "com.example.research",
                                ownership: .automatic(ruleID: coding.id, recordID: owner),
                                customRules: rules)
            var actions: [ActivityRuleResult] = []
            let automation = ActivityAutomation(scheduler: scheduler,
                input: { current }, apply: { actions.append($0) })
            automation.observe(current)
            guard let stale = scheduler.scheduled.first?.2 else {
                return ["The pre-Stop switch run scheduled no deadline"]
            }
            // Stop at t=30: ownership is gone, the app stays in front.
            current = input(at: 30, app: "com.example.research", ownership: .none,
                            customRules: rules)
            automation.observe(current)
            // The pre-Stop deadline fires anyway at its own time. It is stale.
            current = input(at: 60, app: "com.example.research", ownership: .none,
                            customRules: rules)
            stale()
            if let bad = actions.compactMap({ result -> ActivityAutomaticAction? in
                if case .start(let action) = result { return action }
                if case .switchActivity(let action) = result { return action }
                return nil
            }).first(where: { $0.evidence.start < t0.addingTimeInterval(30) }) {
                failures.append("A start after Stop credited time from before the Stop "
                    + "(evidence began \(bad.evidence.start.timeIntervalSince(t0))s)")
            }
            // The run begun after the Stop is legitimate and qualifies at its
            // own one-shot deadline, with evidence starting at the Stop.
            current = input(at: 90, app: "com.example.research", ownership: .none,
                            customRules: rules)
            scheduler.fireLatest()
            let post = actions.compactMap { result -> ActivityAutomaticAction? in
                if case .start(let action) = result { return action }
                return nil
            }
            if !post.contains(where: { $0.evidence.start >= t0.addingTimeInterval(30) }) {
                failures.append("A run begun after the Stop never qualified")
            }
        }

        // Ambiguous run pending, then Stop; the frozen choice must not credit
        // pre-Stop time either.
        do {
            let shared = ActivityRule(name: "Research", workType: .learning,
                                      bundleIDs: ["com.example.shared"], startAfter: 60)
            let both = [ActivityRule(name: "Coding", workType: .deepWork,
                                     bundleIDs: ["com.example.shared"], startAfter: 60), shared]
            let scheduler = TestScheduler()
            var current = input(at: 0, app: "com.example.shared",
                                ownership: .automatic(ruleID: UUID(), recordID: owner),
                                customRules: both)
            var actions: [ActivityRuleResult] = []
            let automation = ActivityAutomation(scheduler: scheduler,
                input: { current }, apply: { actions.append($0) })
            automation.observe(current)
            current = input(at: 30, app: "com.example.shared", ownership: .none,
                            customRules: both)
            automation.observe(current)
            // The run begun at the Stop qualifies at its own deadline (t=90),
            // and the choice it produces must begin at the Stop, not before.
            current = input(at: 90, app: "com.example.shared", ownership: .none,
                            customRules: both)
            scheduler.fireLatest()
            let choices = actions.compactMap { result -> ActivityQuietChoice? in
                if case .ambiguous(let choice) = result { return choice }
                return nil
            }
            guard let choice = choices.last else {
                failures.append("No ambiguous choice was produced after the Stop")
                return failures
            }
            if choice.evidence.start != t0.addingTimeInterval(30) {
                failures.append("An ambiguous choice after Stop froze evidence from "
                    + "\(choice.evidence.start.timeIntervalSince(t0))s, not the Stop at 30s")
            }
        }
        return failures
    }

    /// The engine is the last line: whatever the detector delivers, an
    /// evidence window that begins inside archived work is refused whole.
    private static func overlapRefusal() -> [String] {
        let context = makeConsumer(now: t0)
        defer { clean(context) }
        let ruleID = UUID()
        let archivedEnd = t0.addingTimeInterval(-60)
        context.archive.append(SessionRecord(name: "Coding", workType: .deepWork,
            start: t0.addingTimeInterval(-660), end: archivedEnd,
            workSeconds: 600, threadID: UUID()))
        var failures: [String] = []
        let overlapping = action(rule: ruleID, name: "Research", type: .learning,
            start: t0.addingTimeInterval(-120), end: t0.addingTimeInterval(-30),
            version: context.persistence.activityRuleVersion, generation: 1)
        if context.engine.startAutomatically(action: overlapping) {
            failures.append("An automatic start accepted evidence overlapping an archived record")
        }
        if context.engine.state != .idle {
            failures.append("A refused automatic start still changed engine state")
        }
        let clean = action(rule: ruleID, name: "Research", type: .learning,
            start: archivedEnd, end: t0.addingTimeInterval(-10),
            version: context.persistence.activityRuleVersion, generation: 2)
        if !context.engine.startAutomatically(action: clean) {
            failures.append("An automatic start beginning at the archived end was refused")
        }
        if context.engine.sessionStartDate != archivedEnd {
            failures.append("The accepted start did not begin at its evidence start")
        }
        return failures
    }

    private static func quietChoiceSafety() -> [String] {
        let scheduler = TestScheduler()
        var current = input(at: 0)
        var actions: [ActivityRuleResult] = []
        let automation = ActivityAutomation(scheduler: scheduler,
            input: { current }, apply: { actions.append($0) })
        automation.observe(current)
        current = input(at: 180)
        scheduler.fireLatest()
        let frozen = automation.freezeChoiceForControls(at: t0.addingTimeInterval(180))
        current = input(at: 240, app: FocusConstants.bundleIdentifier,
                        coverageStart: 180)
        let selected = automation.choose(ruleID: codingID, using: current)
        var failures: [String] = []
        if frozen?.evidence.end != t0.addingTimeInterval(180) {
            failures.append("Opening controls did not freeze the external evidence boundary")
        }
        guard case .start(let action)? = selected, action.evidence.end == t0.addingTimeInterval(180)
        else { failures.append("A valid quiet choice included FocusContinuity UI time"); return failures }

        current = input(at: 300, app: "com.example.code",
                        ownership: .manual(activityName: "Newer work", workType: .deepWork))
        if automation.choose(ruleID: researchID, using: current) != nil {
            failures.append("A stale choice backdated over newer manually owned work")
        }
        let scheduler2 = TestScheduler()
        var newer = input(at: 0, foregroundGeneration: 5)
        let automation2 = ActivityAutomation(scheduler: scheduler2,
            input: { newer }, apply: { _ in })
        automation2.observe(newer)
        newer = input(at: 180, foregroundGeneration: 5)
        scheduler2.fireLatest()
        _ = automation2.freezeChoiceForControls(at: newer.timestamp)
        newer = input(at: 181, app: "com.example.code", foregroundGeneration: 6,
                      controlsAreForeground: false)
        if automation2.choose(ruleID: codingID, using: newer) != nil {
            failures.append("A newer external transition did not invalidate the frozen choice")
        }
        return failures
    }

    private static func preferenceModes() -> [String] {
        let suite = "com.prabesh.focuscontinuity.activity-rules.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["Could not create defaults"] }
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        var failures: [String] = []
        if !persistence.autoSessionsEnabled || persistence.activityRuleAutomationEnabled {
            failures.append("Fresh preferences did not preserve legacy-on/rules-opt-in semantics")
        }
        persistence.activityRules = rules
        if persistence.activityRuleAutomationEnabled {
            failures.append("Editing rules enabled automatic mutation")
        }
        persistence.activityRuleAutomationEnabled = true
        if persistence.automationMode != .activityRules {
            failures.append("Enabled rule mode did not supersede the legacy heuristic")
        }
        persistence.activityRuleAutomationEnabled = false
        persistence.autoSessionsEnabled = false
        if persistence.automationMode != .off {
            failures.append("All-off preferences retained an automatic start path")
        }
        return failures
    }

    private static func exactActionIdentity() -> [String] {
        let action = ActivityAutomaticAction(ruleID: codingID, ruleName: "Coding",
            workType: .deepWork, evidence: DateInterval(start: t0, duration: 60),
            reason: "Coding after 60 seconds in Example Code", ruleVersion: 7,
            generation: 9, expectedRecordID: recordID)
        let record = AutomaticActivityRecord(action: action,
            resultingRecordID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!)
        var failures: [String] = []
        if record.reason != action.reason || record.expectedPreviousRecordID != recordID {
            failures.append("Automatic reason or expected prior identity was not retained")
        }
        if record.acceptsUndo(for: UUID()) || !record.acceptsUndo(for: record.resultingRecordID) {
            failures.append("Undo was not bound to the exact automatic stretch")
        }
        return failures
    }

    private final class TestClock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private struct ConsumerContext {
        let directory: URL
        let defaults: UserDefaults
        let suiteName: String
        let persistence: PersistenceStore
        let archive: SessionArchive
        let engine: SessionEngine
        let store: SessionStore
        let clock: TestClock
    }

    private static func makeConsumer(now: Date,
                                     archiveFailure: (([SessionRecord]) -> String?)? = nil,
                                     correctionFailure: (() -> String?)? = nil) -> ConsumerContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-rule-consumer-\(UUID().uuidString)", isDirectory: true)
        let suite = "com.prabesh.focuscontinuity.rule-consumer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        persistence.activityRules = rules
        persistence.activityRuleAutomationEnabled = true
        let clock = TestClock(now)
        let archive = SessionArchive(directory: directory, now: { clock.now },
                                     writeOverride: archiveFailure)
        let engine = SessionEngine(store: persistence, archive: archive,
            ownBundleID: "com.example.self", schedulesDwell: false,
            correctionWriteOverride: correctionFailure, now: { clock.now })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.now })
        return ConsumerContext(directory: directory, defaults: defaults, suiteName: suite,
            persistence: persistence, archive: archive, engine: engine, store: store, clock: clock)
    }

    private static func clean(_ context: ConsumerContext) {
        try? FileManager.default.removeItem(at: context.directory)
        context.defaults.removePersistentDomain(forName: context.suiteName)
    }

    private static func action(rule ruleID: UUID, name: String, type: WorkType,
                               start: Date, end: Date, version: UInt64,
                               generation: UInt64, expected: UUID? = nil) -> ActivityAutomaticAction {
        ActivityAutomaticAction(ruleID: ruleID, ruleName: name, workType: type,
            evidence: DateInterval(start: start, end: end),
            reason: "\(name) from exact foreground evidence", ruleVersion: version,
            generation: generation, expectedRecordID: expected)
    }

    private static func consumerStartAndReload() -> [String] {
        let context = makeConsumer(now: t0.addingTimeInterval(60))
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let start = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.now, version: version, generation: 11)
        guard let applied = context.store.applyAutomaticActivity(start),
              let snapshot = context.persistence.loadState() else {
            return ["Real SessionStore refused a valid automatic start"]
        }
        let reloaded = SessionEngine(store: context.persistence,
            archive: SessionArchive(directory: context.directory, now: { context.clock.now }),
            ownBundleID: "com.example.self", schedulesDwell: false, now: { context.clock.now })
        reloaded.restore(from: snapshot)
        let restoredStore = SessionStore(engine: reloaded, schedulesTicker: false,
                                         now: { context.clock.now })
        var failures: [String] = []
        if reloaded.activeRecordID != applied.resultingRecordID
            || reloaded.activeAutomaticAction?.reason != start.reason
            || reloaded.activeAutomaticAction?.generation != 11
            || restoredStore.automaticActivityRecord?.resultingRecordID != applied.resultingRecordID {
            failures.append("Automatic start provenance did not survive with its exact live record")
        }
        if reloaded.activeThreadID == context.archive.records.last?.threadID {
            failures.append("Automatic start implicitly continued an archived thread")
        }
        return failures
    }

    private static func consumerSwitchAccounting() -> [String] {
        let context = makeConsumer(now: t0.addingTimeInterval(10 * 60))
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let first = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.now, version: version, generation: 1)
        guard let firstRecord = context.store.applyAutomaticActivity(first) else {
            return ["Could not seed automatic Coding"]
        }
        context.clock.now = context.clock.now.addingTimeInterval(5 * 60)
        let second = action(rule: researchID, name: "Research", type: .deepWork,
            start: t0.addingTimeInterval(10 * 60), end: context.clock.now,
            version: version, generation: 2, expected: firstRecord.resultingRecordID)
        guard let secondRecord = context.store.applyAutomaticActivity(second) else {
            return ["Real automatic A-to-B switch was refused"]
        }
        _ = context.engine.stop()
        let total = context.archive.records.reduce(0) { $0 + $1.workSeconds }
        var failures: [String] = []
        if total != 15 * 60 {
            failures.append("10m Coding plus 5m Research totalled \(total)s instead of 900s")
        }
        if Set(context.archive.records.map(\.id)).count != 2
            || firstRecord.resultingRecordID == secondRecord.resultingRecordID {
            failures.append("Automatic switch did not preserve two stable stretch identities")
        }
        if context.archive.records[0].end != t0.addingTimeInterval(10 * 60)
            || context.archive.records[1].start != t0.addingTimeInterval(10 * 60) {
            failures.append("Automatic switch did not close and transfer at one exact boundary")
        }
        return failures
    }

    private static func switchInterruptionRecovery() -> [String] {
        var writes = 0
        let context = makeConsumer(now: t0.addingTimeInterval(10 * 60),
            correctionFailure: {
                writes += 1
                return writes == 2 ? "Interrupted after archive commit" : nil
            })
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let first = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.now, version: version, generation: 21)
        guard let firstRecord = context.store.applyAutomaticActivity(first),
              let beforeSwitch = context.persistence.loadState() else {
            return ["Could not seed interruption fixture"]
        }
        context.clock.now = context.clock.now.addingTimeInterval(5 * 60)
        let second = action(rule: researchID, name: "Research", type: .deepWork,
            start: t0.addingTimeInterval(10 * 60), end: context.clock.now,
            version: version, generation: 22, expected: firstRecord.resultingRecordID)
        guard let secondRecord = context.store.applyAutomaticActivity(second) else {
            return ["Committed automatic switch was treated as an unapplied failure"]
        }
        // Emulate termination before the ordinary preference snapshot publish.
        context.persistence.saveState(beforeSwitch)
        let restored = SessionEngine(store: context.persistence,
            archive: SessionArchive(directory: context.directory, now: { context.clock.now }),
            ownBundleID: "com.example.self", schedulesDwell: false, now: { context.clock.now })
        restored.restore(from: beforeSwitch)
        var failures: [String] = []
        if restored.activeRecordID != secondRecord.resultingRecordID
            || restored.activeAutomaticAction?.generation != 22
            || restored.activeAutomaticAction?.reason != second.reason {
            failures.append("Interrupted switch did not recover its new owner and exact provenance")
        }
        if restored.archive.records.reduce(0, { $0 + $1.workSeconds }) != 10 * 60 {
            failures.append("Interrupted switch duplicated or lost the closed Coding interval")
        }
        return failures
    }

    private static func switchFailureSafety() -> [String] {
        var blockArchive = false
        let context = makeConsumer(now: t0.addingTimeInterval(10 * 60),
            archiveFailure: { _ in blockArchive ? "Archive unavailable" : nil })
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let first = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.now, version: version, generation: 31)
        guard let owner = context.store.applyAutomaticActivity(first) else {
            return ["Could not seed failed-switch fixture"]
        }
        blockArchive = true
        context.clock.now = context.clock.now.addingTimeInterval(5 * 60)
        let second = action(rule: researchID, name: "Research", type: .deepWork,
            start: t0.addingTimeInterval(10 * 60), end: context.clock.now,
            version: version, generation: 32, expected: owner.resultingRecordID)
        let applied = context.store.applyAutomaticActivity(second)
        var failures: [String] = []
        if applied != nil || context.engine.activeRecordID != owner.resultingRecordID
            || context.engine.activeAutomaticAction?.generation != 31
            || !context.archive.records.isEmpty {
            failures.append("Failed switch changed ownership or partially archived time")
        }
        if context.store.activityAutomationError == nil {
            failures.append("Failed switch was not visible at the real consumer")
        }
        return failures
    }

    private static func undoCooldownAndCorrection() -> [String] {
        let context = makeConsumer(now: t0.addingTimeInterval(60))
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let start = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.now, version: version, generation: 41)
        guard let record = context.store.applyAutomaticActivity(start) else {
            return ["Could not seed Undo fixture"]
        }
        var failures: [String] = []
        if !context.store.undoAutomaticActivity(expectedRecordID: record.resultingRecordID) {
            failures.append("Exact automatic Undo was refused")
        }
        if context.store.applyAutomaticActivity(start) != nil {
            failures.append("Undo cooldown allowed the same guess to return immediately")
        }
        context.persistence.activityRuleCooldownUntil = nil
        context.clock.now = context.clock.now.addingTimeInterval(60)
        let newer = action(rule: codingID, name: "Coding", type: .deepWork,
            start: context.clock.now.addingTimeInterval(-60), end: context.clock.now,
            version: context.persistence.activityRuleVersion, generation: 42)
        guard let newerRecord = context.store.applyAutomaticActivity(newer) else {
            failures.append("Could not seed newer automatic work"); return failures
        }
        if context.store.undoAutomaticActivity(expectedRecordID: record.resultingRecordID) {
            failures.append("A stale HUD discarded a newer automatic stretch")
        }
        context.engine.adopt(intent: "Corrected by hand")
        context.persistence.activityRules = context.persistence.activityRules.map {
            ActivityRule(id: $0.id, name: $0.name, workType: .admin,
                         bundleIDs: $0.bundleIDs, isEnabled: $0.isEnabled,
                         startAfter: $0.startAfter)
        }
        context.store.refresh()
        if context.store.undoAutomaticActivity(expectedRecordID: newerRecord.resultingRecordID)
            || context.engine.sessionName != "Corrected by hand" {
            failures.append("Rule edit or stale Undo overrode a durable manual correction")
        }
        return failures
    }

    private static func allOffActivationGate() -> [String] {
        let context = makeConsumer(now: t0)
        defer { clean(context) }
        context.persistence.activityRuleAutomationEnabled = false
        context.persistence.autoSessionsEnabled = false
        context.engine.transition(on: .appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
        var failures: [String] = []
        if context.engine.state != .idle {
            failures.append("All-off app activation used the idle automatic-start back door")
        }
        if context.engine.currentAppBundleID != "com.apple.dt.Xcode" {
            failures.append("All-off mode stopped recording foreground context")
        }
        context.persistence.autoSessionsEnabled = true
        context.engine.transition(on: .appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
        if context.engine.state != .running {
            failures.append("Explicitly enabled legacy activation behaviour was not preserved")
        }
        return failures
    }

    /// Both compact surfaces must render the quiet choice when one is pending
    /// and omit it otherwise. The proof is the production branch's own render
    /// evidence: SwiftUI-only elements never appear to an in-process
    /// accessibility walk (an NSHostingView reports zero AX children), so a
    /// label search cannot observe this content either way.
    private static func quietChoiceConsumers() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.activityRuleStore(ambiguous: true)
            defer { FixtureFactory.cleanUp() }
            guard let pending = store.pendingActivityChoice else {
                return ["Ambiguous fixture did not present a quiet activity choice"]
            }
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                onChange: {}, onTrackingChanged: { _ in },
                installedAppCatalog: FixtureFactory.installedAppCatalog())
            let navigation = MainWindowModel(store: store)
            var failures: [String] = []

            func surfaces() -> [(String, AnyView, CGFloat)] {
                [("In-window session strip",
                  AnyView(SessionControlStrip(store: store, settings: settings,
                                              navigation: navigation)), 900),
                 ("Menu panel",
                  AnyView(PopoverView(store: store, settings: settings,
                      metricsOverride: PopoverMetrics.fitting(CGSize(width: 1_000, height: 680)),
                      scrolls: false)), 380)]
            }

            for (label, view, width) in surfaces() {
                let evidence = renderEvidence(view, width: width, height: 720)
                if !evidence.contains(.activityQuietChoice) {
                    failures.append("\(label) omitted the quiet activity choice")
                }
            }

            store.presentActivityChoice(nil)
            for (label, view, width) in surfaces() {
                let evidence = renderEvidence(view, width: width, height: 720)
                if evidence.contains(.activityQuietChoice) {
                    failures.append("\(label) rendered a quiet choice with none pending")
                }
            }
            store.presentActivityChoice(pending)
            return failures
        }
    }

    /// Renders offscreen and returns the production evidence preferences the
    /// tree reported. Mirrors the Story workspace proof so the two suites
    /// prove content the same way.
    @MainActor private static func renderEvidence(_ view: AnyView, width: CGFloat,
                                                  height: CGFloat) -> Set<StoryRenderEvidence> {
        final class Box { var values: Set<StoryRenderEvidence> = [] }
        let box = Box()
        let framed = view.frame(width: width, height: height, alignment: .topLeading)
            .background(Tokens.Colour.ground)
            .onPreferenceChange(StoryRenderEvidenceKey.self) { box.values = $0 }
        let host = NSHostingView(rootView: framed)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.displayIfNeeded()
        window.orderOut(nil)
        window.close()
        return box.values
    }

    private static func editorConsumer() -> [String] {
        MainActor.assumeIsolated {
            let state = ActivityRuleEditorState()
            state.beginNew(); state.name = "Coding"; state.bundleIDs = ["com.example.code"]
            state.dwell = -1; state.customDwell = "30.5"
            var failures: [String] = []
            if state.ruleForSaving() != nil || state.validationMessage == nil {
                failures.append("Editor accepted a fractional custom dwell without a visible error")
            }
            let suite = "com.prabesh.focuscontinuity.rule-editor.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            persistence.activityRules = [rule(codingID, "Coding", 180, ["com.example.code"])]
            var discoveries = 0
            let catalog = InstalledAppCatalog(discoverStandard: {
                discoveries += 1
                return (0..<40).map { InstalledApplication(
                    bundleID: "com.example.app\($0)", name: "Application \($0)", url: nil) }
            }, discoverSpotlight: { discoveries += 1; return [] },
               observed: { discoveries += 1; return [] })
            let model = SettingsModel(store: persistence, isTrackingEnabled: true,
                onChange: {}, onTrackingChanged: { _ in }, installedAppCatalog: catalog)
            let host = NSHostingView(rootView: ActivityRulesView(model: model)
                .frame(width: 680, height: 500))
            host.frame = NSRect(x: 0, y: 0, width: 680, height: 500)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            if descendantCount(NSScrollView.self, in: host) < 1 {
                failures.append("Long installed-app picker did not render a genuine scroll region")
            }
            if discoveries != 3 {
                failures.append("Fixture editor did not use only its three injected discovery sources")
            }
            return failures
        }
    }

    @MainActor private static func descendantCount<T: NSView>(_ type: T.Type,
                                                               in view: NSView) -> Int {
        (view is T ? 1 : 0) + view.subviews.reduce(0) { $0 + descendantCount(type, in: $1) }
    }

    /// One mutable value shared across the worker boundary. The semaphore
    /// below orders every write before the read.
    private final class Box {
        var flag = false
        var failures: [String] = []
    }

    /// The catalogue's Spotlight supplement is delivered through the run loop
    /// of whichever thread starts it — a GCD worker in production, which owns
    /// a run loop but never runs it. This proves the wait actually turns that
    /// loop, which a blocking wait cannot do, and that an unmet wait still
    /// honours its budget. It uses a synthetic run-loop delivery; no live
    /// Spotlight query is started and the user's applications are never
    /// enumerated.
    private static func catalogRunLoopWait() -> [String] {
        let box = Box()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue(label: "fc.catalog.runloop.check").async {
            // Only a turning run loop can ever execute this block.
            RunLoop.current.perform { box.flag = true }
            let satisfied = InstalledAppCatalog.turnRunLoop(until: { box.flag }, timeout: 2)
            if !satisfied || !box.flag {
                box.failures.append("A run-loop delivery never arrived on a worker thread")
            }

            let start = Date()
            let unmet = InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.2)
            let elapsed = Date().timeIntervalSince(start)
            if unmet {
                box.failures.append("An unmet condition reported success")
            }
            if elapsed > 1.5 {
                box.failures.append("An unmet wait overran its budget by \(elapsed - 0.2)s")
            }
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 15) == .success else {
            return ["The run-loop wait never returned"]
        }
        return box.failures
    }

    private final class CountBox { var value = 0 }

    /// The picker's rows are SwiftUI-only, so no NSView walk can see them —
    /// counting `NSButton` descendants returns zero however many applications
    /// are published. The production row-count preference is read instead, which
    /// proves a row exists for each application rather than only that a scroll
    /// region appeared. The catalogue is injected; no application is enumerated.
    private static func pickerRows() -> [String] {
        MainActor.assumeIsolated {
            @MainActor func render(_ count: Int, query: String = "") -> Int {
                let apps = (0..<count).map {
                    InstalledApplication(bundleID: "com.example.app\($0)",
                                         name: "Application \($0)", url: nil)
                }
                let catalog = InstalledAppCatalog(discoverStandard: { apps },
                                                  discoverSpotlight: { [] }, observed: { [] })
                catalog.refresh()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                let queryBox = TextBox(); queryBox.text = query
                let selectionBox = SetBox()
                let rows = CountBox()
                let view = InstalledAppPicker(
                    catalog: catalog,
                    query: Binding(get: { queryBox.text }, set: { queryBox.text = $0 }),
                    selection: Binding(get: { Set<String>() }, set: { _ in }))
                    .frame(width: 520, height: 400)
                    .onPreferenceChange(InstalledAppRowCountKey.self) { rows.value = $0 }
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                host.layoutSubtreeIfNeeded()
                window.orderOut(nil); window.contentView = nil
                _ = selectionBox
                return rows.value
            }
            var failures: [String] = []
            let empty = render(0)
            if empty != 0 {
                failures.append("An empty catalogue still rendered \(empty) picker rows")
            }
            // Four rows fit the picker's own 220-point viewport, so every
            // published application must appear.
            let four = render(4)
            if four != 4 {
                failures.append("Four published applications rendered \(four) rows")
            }
            // Eight exceed the viewport. The list is lazy by design, so more
            // rows must appear than for four, and never more than were published.
            let eight = render(8)
            if eight <= four || eight > 8 {
                failures.append("Eight published applications rendered \(eight) rows, "
                    + "outside the expected \(four + 1)...8")
            }
            let filtered = render(8, query: "Application 3")
            if filtered != 1 {
                failures.append("Searching one application name rendered \(filtered) rows")
            }
            return failures
        }
    }

    private static func catalogDiscovery() -> [String] {
        let duplicateA = InstalledApplication(bundleID: "COM.Example.Code", name: "Code", url: nil)
        let duplicateB = InstalledApplication(bundleID: "com.example.code", name: "Visual Studio Code", url: nil)
        let missing = InstalledApplication(bundleID: "com.example.missing", name: "Old App", url: nil,
                                           isInstalled: false)
        let catalog = InstalledAppCatalog(discoverStandard: { [duplicateA] },
                                          discoverSpotlight: { [duplicateB] },
                                          observed: { [missing] })
        let result = catalog.discoverSynchronouslyForVerification()
        var failures: [String] = []
        if result.map(\.bundleID) != ["com.example.code", "com.example.missing"] {
            failures.append("Injected catalog sources were not stably deduplicated")
        }
        if result.last?.displayName != "Old App — Missing" {
            failures.append("Missing observed application lacked an honest label")
        }
        return failures
    }
}
