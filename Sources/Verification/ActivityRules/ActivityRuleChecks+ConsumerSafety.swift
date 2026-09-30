import Foundation
import SwiftUI
import AppKit

extension ActivityRuleChecks {
    static func switchFailureSafety() -> [String] {
        var blockArchive = false
        let context = makeConsumer(now: t0.addingTimeInterval(10 * 60),
            archiveFailure: { _ in blockArchive ? "Archive unavailable" : nil })
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let first = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.value, version: version, generation: 31)
        guard let owner = context.store.applyAutomaticActivity(first) else {
            return ["Could not seed failed-switch fixture"]
        }
        blockArchive = true
        context.clock.value = context.clock.value.addingTimeInterval(5 * 60)
        let second = action(rule: researchID, name: "Research", type: .deepWork,
            start: t0.addingTimeInterval(10 * 60), end: context.clock.value,
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

    static func undoCooldownAndCorrection() -> [String] {
        let context = makeConsumer(now: t0.addingTimeInterval(60))
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let start = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.value, version: version, generation: 41)
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
        context.clock.value = context.clock.value.addingTimeInterval(60)
        let newer = action(rule: codingID, name: "Coding", type: .deepWork,
            start: context.clock.value.addingTimeInterval(-60), end: context.clock.value,
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

    static func allOffActivationGate() -> [String] {
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
}
