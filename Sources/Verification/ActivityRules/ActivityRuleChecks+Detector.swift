import Foundation
import SwiftUI
import AppKit

extension ActivityRuleChecks {
    static func modelValidation() -> [String] {
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

    static func sharedAmbiguity() -> [String] {
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

    static func membershipIntersection() -> [String] {
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

    static func dwellBoundaries() -> [String] {
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

    static func ownershipPrecedence() -> [String] {
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

    /// Alternating between two rules' apps must not cut the work into a new
    /// session at every change: once a rule has started a session, another
    /// rule's apps neither schedule a deadline nor act, however long they stay.
    static func noAutomaticSwitch() -> [String] {
        var detector = ActivityRuleDetector()
        let automatic = ActivityOwnership.automatic(ruleID: codingID, recordID: recordID)
        var failures: [String] = []
        for seconds in [300.0, 480, 1_200, 3_600] {
            let result = detector.evaluate(input(at: seconds, app: "com.example.research",
                                                 ownership: automatic))
            if result != .none {
                failures.append("Research acted on running Coding at \(Int(seconds))s")
            }
        }
        return failures
    }

    static func oneShotDeadline() -> [String] {
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

    static func staleDeadlineSafety() -> [String] {
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
}
