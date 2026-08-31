import Foundation

/// Actual-source reproductions from Task 3's independent recovery review.
enum DecisionRecoveryChecks {
    static let tests: [(String, () -> [String])] = [
        ("Declared-away capacity recovery cannot resurrect archived focus", declaredAwayRecovery),
        ("Watching capacity recovery cannot debit the same pause twice", watchingRecovery),
        ("Held continuations retain inherited field Undo after unrelated retirement", heldContinuation),
        ("A real live credit correction remains authoritative after metadata retirement", liveCorrectionBeforeMetadata),
        ("Metadata retirement cannot replace a newer ordinary paused or running snapshot", newerOrdinaryState),
        ("A later ordinary End supersedes the live correction it closes", endAfterCorrection),
        ("Short End and discard close recovery authority without manufacturing records", shortTerminalRecovery),
        ("Failed automatic discard preserves ownership and defers callbacks until commitment", refusedDiscard),
        ("Legacy sidecar and snapshot fields still recover a real live correction", legacyLiveAuthority),
        ("An older pending operation cannot impersonate a new short End", pendingShortEnd)
    ]

    private final class Fixture {
        var time = Date(timeIntervalSince1970: 1_788_000_000)
        let suite = "fc.decision-recovery.\(UUID())"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fc-decision-recovery-\(UUID())")
        let capacity: Int
        var journalFailure: (() -> String?)?
        lazy var defaults = UserDefaults(suiteName: suite)!
        lazy var archive = SessionArchive(directory: directory, now: { self.time }, capacity: capacity)
        lazy var engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
            ownBundleID: "fc.recovery.fixture", schedulesDwell: false,
            correctionWriteOverride: { self.journalFailure?() }, now: { self.time })
        lazy var store = SessionStore(engine: engine, schedulesTicker: false, now: { self.time })
        init(capacity: Int) { self.capacity = capacity }
        func close() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        func restored(_ state: PersistedState) -> SessionEngine {
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults),
                archive: SessionArchive(directory: directory, now: { self.time }, capacity: capacity),
                schedulesDwell: false, now: { self.time })
            engine.restore(from: state)
            return engine
        }
        func seed(_ count: Int? = nil) {
            for index in 0..<(count ?? capacity) {
                let start = time.addingTimeInterval(Double(-3_000 + index * 100))
                archive.append(SessionRecord(name: "Seed", workType: .breakTime,
                    start: start, end: start.addingTimeInterval(60), workSeconds: 60))
            }
        }
        func credit() -> Bool {
            engine.start(workType: .deepWork, intent: "Actual work")
            time.addTimeInterval(600); engine.transition(on: .awayBegan(trigger: .screenLock))
            time.addTimeInterval(1_200); engine.transition(on: .awayEnded)
            return store.resolve(.mergeTime)
        }
        func appendUnrelated() {
            archive.append(SessionRecord(name: "Unrelated", workType: .breakTime,
                start: time, end: time.addingTimeInterval(60), workSeconds: 60))
        }
    }

    private static func row(_ record: SessionRecord) -> DaySession {
        DaySession(id: record.id, threadID: record.threadID, name: record.name, workType: record.workType,
            start: record.start, end: record.end, worked: record.workSeconds, stretches: 1,
            spans: [DateInterval(start: record.start, end: record.end)], isRunning: false)
    }

    private static func declaredAwayRecovery() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 3); defer { f.close() }; f.seed()
            f.engine.start(workType: .deepWork, intent: "Actual work")
            f.time.addTimeInterval(600); f.engine.transition(on: .markedAway)
            let stale = f.engine.snapshot()
            f.time.addTimeInterval(1_200); f.engine.transition(on: .manualResume)
            let restored = f.restored(stale)
            restored.stop()
            let focused = restored.archive.records.filter { $0.workType.countsAsFocus }.reduce(0) { $0 + $1.workSeconds }
            return focused == 600 ? [] : ["declared-away recovery duplicated focus: expected 600, got \(focused)"]
        }
    }

    private static func watchingRecovery() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 3); defer { f.close() }; f.seed()
            f.engine.start(workType: .deepWork, intent: "Actual work")
            f.time.addTimeInterval(1_200)
            f.engine.transition(on: .watchingObserved(seconds: 600))
            let stale = f.engine.snapshot()
            f.time.addTimeInterval(1_200)
            f.engine.transition(on: .appActivated(bundleID: "fc.target", name: "Target"))
            guard f.engine.elapsed == 600 else { return ["Watching reproduction did not retain 600 seconds before recovery"] }
            let restored = f.restored(stale)
            return restored.elapsed == 600 ? [] : ["Watching recovery lost focus: expected 600, got \(restored.elapsed)"]
        }
    }

    private static func heldContinuation() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 1); defer { f.close() }
            let original = SessionRecord(name: "Original", workType: .learning,
                start: f.time.addingTimeInterval(-120), end: f.time, workSeconds: 120)
            f.archive.append(original)
            guard f.store.renameSession(row(original), to: "Changed"), let nameID = f.store.lastCorrection?.id else { return ["name setup failed"] }
            f.engine.start(workType: .learning, intent: "Changed", threadID: original.threadID)
            f.time.addTimeInterval(120); f.engine.stop()
            guard let continued = f.archive.records.first,
                  f.store.setWorkType(.breakTime, for: row(continued)), let typeID = f.store.lastCorrection?.id,
                  f.engine.reclassifyLegacyBreak(recordID: continued.id, decision: .continueSession) else { return ["held continuation setup failed"] }
            for _ in 0..<2 {
                f.time.addTimeInterval(120)
                f.archive.append(SessionRecord(name: "Unrelated", workType: .learning,
                    start: f.time.addingTimeInterval(-60), end: f.time, workSeconds: 60))
            }
            guard f.store.corrections.contains(where: { $0.id == nameID }) else {
                return ["inherited name Undo was lost while its continuation remained recoverably held"]
            }
            // Make room without changing the held record; historical Undo must
            // not evict unrelated history simply to demonstrate the recovery.
            guard f.archive.edit(removing: f.archive.records) == nil,
                  f.engine.undoAwayDecision(), f.store.undoCorrection(expectedID: typeID),
                  f.store.undoCorrection(expectedID: nameID), f.archive.records.count == 1,
                  f.archive.records.first?.id == continued.id, f.archive.records.first?.name == "Original",
                  f.archive.records.first?.workType == .learning, f.archive.records.first?.workSeconds == 120 else {
                return ["held field Undo failed to restore only the surviving continuation"]
            }
            return []
        }
    }

    private static func liveCorrectionBeforeMetadata() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 3); defer { f.close() }; f.seed()
            guard f.credit(), let oldID = f.engine.lastAwayDecision?.id else { return ["credit setup failed"] }
            let stale = f.engine.snapshot()
            guard f.engine.undoAwayDecision(expectedID: oldID) else { return ["credit Undo setup failed"] }
            f.appendUnrelated()
            let restored = f.restored(stale)
            return restored.elapsed == 600 && !restored.undoAwayDecision(expectedID: oldID) ? []
                : ["metadata retirement masked the actual live-credit correction or repeated its debit"]
        }
    }

    private static func newerOrdinaryState() -> [String] {
        MainActor.assumeIsolated {
            for resumed in [false, true] {
                let f = Fixture(capacity: 3); defer { f.close() }; f.seed()
                guard f.credit(), f.engine.undoAwayDecision() else { return ["credit Undo setup failed"] }
                f.engine.transition(on: .manualPause)
                if resumed { f.time.addTimeInterval(120); f.engine.transition(on: .manualResume) }
                let newer = f.engine.snapshot()
                f.time.addTimeInterval(120); f.appendUnrelated()
                let restored = f.restored(newer)
                guard restored.state == (resumed ? .running : .paused(reason: .manual)), restored.elapsed == 600 else {
                    return ["metadata retirement replaced newer ordinary \(resumed ? "running" : "paused") state: elapsed \(restored.elapsed)"]
                }
            }
            return []
        }
    }

    private static func endAfterCorrection() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 3); defer { f.close() }; f.seed(1)
            guard f.credit() else { return ["credit setup failed"] }
            let stale = f.engine.snapshot()
            guard f.engine.undoAwayDecision(), f.engine.stop() else { return ["ordinary ending setup failed"] }
            f.appendUnrelated(); f.appendUnrelated()
            let restored = f.restored(stale)
            restored.stop()
            let focused = restored.archive.records.filter { $0.workType.countsAsFocus }.reduce(0) { $0 + $1.workSeconds }
            return restored.state == .idle && focused == 600 ? []
                : ["an earlier credit checkpoint reopened work already closed by ordinary End"]
        }
    }

    private static func correctedShortStretch(_ f: Fixture) -> Bool {
        f.engine.start(workType: .learning, intent: "Original")
        f.time.addTimeInterval(5)
        let live = SessionRecord(name: "Original", workType: .learning, start: f.engine.sessionStartDate,
            end: f.time, workSeconds: 5, threadID: f.engine.activeThreadID)
        return f.store.renameSession(row(live), to: "Changed")
    }

    private static func shortTerminalRecovery() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for discard in [false, true] {
                let f = Fixture(capacity: 3); defer { f.close() }
                guard correctedShortStretch(f) else { return ["short correction setup failed"] }
                let stale = f.engine.snapshot()
                if discard { f.engine.discard() } else { f.engine.stop() }
                let restored = f.restored(stale)
                if restored.state != .idle || !restored.archive.records.isEmpty {
                    problems.append("\(discard ? "Discard" : "Short End") resurrected corrected work or manufactured a record")
                }
            }
            return problems
        }
    }

    private static func refusedDiscard() -> [String] {
        MainActor.assumeIsolated {
            for failWrite in [1, 2] {
                let f = Fixture(capacity: 3); defer { f.close() }
                let other = SessionRecord(name: "Historical", workType: .learning,
                    start: f.time.addingTimeInterval(-600), end: f.time.addingTimeInterval(-480), workSeconds: 120)
                f.archive.append(other)
                guard f.store.renameSession(row(other), to: "Historical corrected"),
                      let independentID = f.store.lastCorrection?.id, correctedShortStretch(f) else { return ["discard setup failed"] }
                var automatic = f.engine.snapshot(); automatic.isAuto = true
                f.engine.restore(from: automatic)
                f.engine.transition(on: .markedAway)
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                let before = f.engine.snapshot(), records = f.archive.records
                var stoppedAutomation = 0, resumedTracking = 0, writes = 0
                f.store.onAutoSessionUndone = { stoppedAutomation += 1 }
                f.store.onAwayEnded = { resumedTracking += 1 }
                f.journalFailure = { writes += 1; return writes == failWrite ? "Discard journal unavailable" : nil }
                f.store.undoAutomaticSessionCorrection()
                if failWrite == 1 {
                    guard f.engine.snapshot() == before, stoppedAutomation == 0, resumedTracking == 0,
                          f.store.correctionError != nil else { return ["refused discard abandoned live ownership or ran completion callbacks"] }
                } else {
                    guard f.engine.state == .idle, stoppedAutomation == 1, resumedTracking == 1,
                          f.store.correctionError != nil else { return ["committed discard concealed pending finalisation or lost callbacks"] }
                }
                f.journalFailure = nil
                guard f.store.retryLastCorrection(), f.engine.state == .idle, f.archive.records == records,
                      stoppedAutomation == 1, resumedTracking == 1,
                      f.store.corrections.contains(where: { $0.id == independentID }) else {
                    return ["discard Retry changed independent history or repeated completion callbacks"]
                }
            }
            return []
        }
    }

    private static func legacyLiveAuthority() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 3); defer { f.close() }
            guard f.credit(), let id = f.engine.lastAwayDecision?.id else { return ["legacy credit setup failed"] }
            let before = f.engine.snapshot()
            guard f.engine.undoAwayDecision(expectedID: id) else { return ["legacy Undo setup failed"] }
            func legacyValue(_ value: Any) -> Any {
                if let object = value as? [String: Any] {
                    return object.filter { !["metadataCheckpoint", "operation", "liveCorrectionGeneration", "retiredRecordIDs"].contains($0.key) }
                        .mapValues(legacyValue)
                }
                if let values = value as? [Any] { return values.map(legacyValue) }
                return value
            }
            do {
                let journal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f.engine.decisionHistory.document))
                try JSONSerialization.data(withJSONObject: legacyValue(journal)).write(
                    to: f.directory.appendingPathComponent("correction-history.json"), options: .atomic)
                let snapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(before))
                let oldState = try JSONDecoder().decode(PersistedState.self,
                    from: JSONSerialization.data(withJSONObject: legacyValue(snapshot)))
                let restored = f.restored(oldState)
                return restored.elapsed == 600 && !restored.undoAwayDecision(expectedID: id) ? []
                    : ["legacy optional-field defaults lost or duplicated the live correction"]
            } catch { return ["legacy fixture encoding failed: \(error)"] }
        }
    }

    private static func pendingShortEnd() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 3); defer { f.close() }
            guard correctedShortStretch(f) else { return ["short correction setup failed"] }
            var writes = 0
            f.journalFailure = { writes += 1; return writes >= 2 ? "Journal remains unavailable" : nil }
            let live = SessionRecord(name: "Changed", workType: .learning, start: f.engine.sessionStartDate,
                end: f.time, workSeconds: 5, threadID: f.engine.activeThreadID)
            guard !f.store.renameSession(row(live), to: "Newest"), f.engine.sessionName == "Newest" else {
                return ["pending field finalisation setup failed"]
            }
            let beforeEnd = f.engine.snapshot()
            guard !f.engine.stop(), f.engine.snapshot() == beforeEnd, f.archive.records.isEmpty else {
                return ["short End incorrectly borrowed commitment from the older pending field action"]
            }
            f.journalFailure = nil
            guard f.engine.stop(), f.restored(beforeEnd).state == .idle, f.archive.records.isEmpty else {
                return ["short End could not complete once its own journal became writable"]
            }
            return []
        }
    }
}
