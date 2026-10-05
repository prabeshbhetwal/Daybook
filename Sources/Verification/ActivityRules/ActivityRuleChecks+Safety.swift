import Foundation
import SwiftUI
import AppKit

extension ActivityRuleChecks {
    /// A qualifying run begun while an automatic session is live must not
    /// outlive that session's Stop. Time before the Stop is already archived;
    /// only a run begun after it may qualify.
    static func stopMidDwell() -> [String] {
        let coding = ActivityRule(name: "Coding", workType: .deepWork,
                                  bundleIDs: ["com.example.code"], startAfter: 60)
        let research = ActivityRule(name: "Research", workType: .learning,
                                    bundleIDs: ["com.example.research"], startAfter: 60)
        let rules = [coding, research]
        let owner = UUID()
        var failures: [String] = []

        // Another rule's app in front of a running session, then Stop.
        do {
            let scheduler = TestScheduler()
            var current = input(at: 0, app: "com.example.research",
                                ownership: .automatic(ruleID: coding.id, recordID: owner),
                                customRules: rules)
            var actions: [ActivityRuleResult] = []
            let automation = ActivityAutomation(scheduler: scheduler,
                input: { current }, apply: { actions.append($0) })
            automation.observe(current)
            if !scheduler.scheduled.isEmpty {
                failures.append("A running session scheduled another rule's deadline")
            }
            // Stop at t=30: ownership is gone, the app stays in front.
            current = input(at: 30, app: "com.example.research", ownership: .none,
                            customRules: rules)
            automation.observe(current)
            current = input(at: 60, app: "com.example.research", ownership: .none,
                            customRules: rules)
            if let bad = actions.compactMap({ result -> ActivityAutomaticAction? in
                if case .start(let action) = result { return action }
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
    static func overlapRefusal() -> [String] {
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

    static func quietChoiceSafety() -> [String] {
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
        else { failures.append("A valid quiet choice included Daybook UI time"); return failures }

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

    static func preferenceModes() -> [String] {
        let suite = "com.prabesh.daybook.activity-rules.\(UUID().uuidString)"
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

    static func exactActionIdentity() -> [String] {
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
}
