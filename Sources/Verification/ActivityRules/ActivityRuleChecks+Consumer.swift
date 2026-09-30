import Foundation
import SwiftUI
import AppKit

extension ActivityRuleChecks {
    static func consumerStartAndReload() -> [String] {
        let context = makeConsumer(now: t0.addingTimeInterval(60))
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let start = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.value, version: version, generation: 11)
        guard let applied = context.store.applyAutomaticActivity(start),
              let snapshot = context.persistence.loadState() else {
            return ["Real SessionStore refused a valid automatic start"]
        }
        let reloaded = SessionEngine(store: context.persistence,
            archive: SessionArchive(directory: context.directory, now: { context.clock.value }),
            ownBundleID: "com.example.self", schedulesDwell: false, now: { context.clock.value })
        reloaded.restore(from: snapshot)
        let restoredStore = SessionStore(engine: reloaded, schedulesTicker: false,
                                         now: { context.clock.value })
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

    static func consumerSwitchAccounting() -> [String] {
        let context = makeConsumer(now: t0.addingTimeInterval(10 * 60))
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let first = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.value, version: version, generation: 1)
        guard let firstRecord = context.store.applyAutomaticActivity(first) else {
            return ["Could not seed automatic Coding"]
        }
        context.clock.value = context.clock.value.addingTimeInterval(5 * 60)
        let second = action(rule: researchID, name: "Research", type: .deepWork,
            start: t0.addingTimeInterval(10 * 60), end: context.clock.value,
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

    static func switchBackContinuesThread() -> [String] {
        let context = makeConsumer(now: t0.addingTimeInterval(10 * 60))
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        var failures: [String] = []

        // Coding, then Research, then Coding again: one Coding thread.
        let coding = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.value, version: version, generation: 41)
        guard let first = context.store.applyAutomaticActivity(coding) else {
            return ["Could not seed automatic Coding"]
        }
        let codingThread = context.engine.activeThreadID
        if context.engine.activeThreadWasContinued {
            failures.append("The first automatic Coding claimed to continue something")
        }
        context.clock.value = context.clock.value.addingTimeInterval(5 * 60)
        let research = action(rule: researchID, name: "Research", type: .deepWork,
            start: t0.addingTimeInterval(10 * 60), end: context.clock.value,
            version: version, generation: 42, expected: first.resultingRecordID)
        guard let second = context.store.applyAutomaticActivity(research) else {
            return ["Coding to Research switch was refused"]
        }
        if context.engine.activeThreadWasContinued {
            failures.append("The first automatic Research claimed to continue something")
        }
        context.clock.value = context.clock.value.addingTimeInterval(5 * 60)
        let back = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0.addingTimeInterval(15 * 60), end: context.clock.value,
            version: version, generation: 43, expected: second.resultingRecordID)
        guard context.store.applyAutomaticActivity(back) != nil else {
            return ["Research back to Coding switch was refused"]
        }
        if context.engine.activeThreadID != codingThread {
            failures.append("Switching back to Coding started a new thread instead of continuing")
        }
        if !context.engine.activeThreadWasContinued {
            failures.append("A continued Coding did not say so")
        }
        _ = context.engine.stop()
        let codingRecords = context.archive.records.filter { $0.name == "Coding" }
        if codingRecords.count != 2 || Set(codingRecords.map(\.threadID)).count != 1 {
            failures.append("Two Coding stretches did not share one thread: "
                            + "\(codingRecords.map(\.threadID))")
        }
        if Set(context.archive.records.map(\.id)).count != 3 {
            failures.append("Continuing reused a record identity instead of adding a stretch")
        }

        // A thread the user adopted is theirs: a later rule starts afresh.
        context.clock.value = context.clock.value.addingTimeInterval(60)
        let adoptedStart = context.clock.value
        context.clock.value = context.clock.value.addingTimeInterval(4 * 60)
        let again = action(rule: codingID, name: "Coding", type: .deepWork,
            start: adoptedStart, end: context.clock.value, version: version, generation: 44)
        guard context.store.applyAutomaticActivity(again) != nil else {
            return ["Automatic Coding after a stop was refused"]
        }
        if !context.engine.activeThreadWasContinued {
            failures.append("Coding a minute after its last stretch did not continue it")
        }
        context.engine.adopt(intent: "")
        _ = context.engine.stop()
        context.clock.value = context.clock.value.addingTimeInterval(60)
        let afterAdopt = context.clock.value
        context.clock.value = context.clock.value.addingTimeInterval(4 * 60)
        let onceMore = action(rule: codingID, name: "Coding", type: .deepWork,
            start: afterAdopt, end: context.clock.value, version: version, generation: 45)
        guard context.store.applyAutomaticActivity(onceMore) != nil else {
            return ["Automatic Coding after an adopted stretch was refused"]
        }
        if context.engine.activeThreadID == codingThread || context.engine.activeThreadWasContinued {
            failures.append("A rule extended a thread the user had adopted as their own")
        }
        _ = context.engine.stop()

        // Beyond the Continue affordance's window, a rule starts afresh too.
        let latestThread = context.archive.records.last?.threadID
        context.clock.value = context.clock.value.addingTimeInterval(ContinuationPolicy.maximumAge + 60)
        let lateStart = context.clock.value
        context.clock.value = context.clock.value.addingTimeInterval(4 * 60)
        let late = action(rule: codingID, name: "Coding", type: .deepWork,
            start: lateStart, end: context.clock.value, version: version, generation: 46)
        guard context.store.applyAutomaticActivity(late) != nil else {
            return ["Automatic Coding after a long gap was refused"]
        }
        if context.engine.activeThreadID == latestThread || context.engine.activeThreadWasContinued {
            failures.append("A rule continued a stretch older than the continuation window")
        }
        return failures
    }

    static func switchInterruptionRecovery() -> [String] {
        var writes = 0
        let context = makeConsumer(now: t0.addingTimeInterval(10 * 60),
            correctionFailure: {
                writes += 1
                return writes == 2 ? "Interrupted after archive commit" : nil
            })
        defer { clean(context) }
        let version = context.persistence.activityRuleVersion
        let first = action(rule: codingID, name: "Coding", type: .deepWork,
            start: t0, end: context.clock.value, version: version, generation: 21)
        guard let firstRecord = context.store.applyAutomaticActivity(first),
              let beforeSwitch = context.persistence.loadState() else {
            return ["Could not seed interruption fixture"]
        }
        context.clock.value = context.clock.value.addingTimeInterval(5 * 60)
        let second = action(rule: researchID, name: "Research", type: .deepWork,
            start: t0.addingTimeInterval(10 * 60), end: context.clock.value,
            version: version, generation: 22, expected: firstRecord.resultingRecordID)
        guard let secondRecord = context.store.applyAutomaticActivity(second) else {
            return ["Committed automatic switch was treated as an unapplied failure"]
        }
        // Emulate termination before the ordinary preference snapshot publish.
        context.persistence.saveState(beforeSwitch)
        let restored = SessionEngine(store: context.persistence,
            archive: SessionArchive(directory: context.directory, now: { context.clock.value }),
            ownBundleID: "com.example.self", schedulesDwell: false, now: { context.clock.value })
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
}
