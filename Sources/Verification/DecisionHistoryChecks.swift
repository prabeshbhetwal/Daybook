import Foundation

enum DecisionHistoryChecks {
    static let tests: [(String, () -> [String])] = [
        ("Two absence decisions retain targeted Undo of the older interval", olderUndo),
        ("Relaunch retains older absence Undo after a later decision", restoredOlderUndo),
        ("Equal credits in one archived stretch Undo independently through stale restoration", equalCredits),
        ("A live credit Undo survives stale restoration without debiting later work", liveCreditRecovery),
        ("Journal preparation and finalisation failures preserve retryable exact effects", journalFailures),
        ("An unrelated field correction retains older absence Undo", fieldAndAway),
        ("Field correction identities survive relaunch and reject conflicting newer edits", fieldHistory),
        ("Legacy sidecar-free receipt migration retains the action identity", migration),
        ("Legacy break reclassification has recoverable uncounted and explicit focus attribution", legacyClassification),
        ("A failed journal write while ending credited work cannot discard the live stretch", failedCreditStop),
        ("Failed credited Stop also refuses dependent Start and Reset", failedCreditReplacement),
        ("Journal interruptions preserve initial answers, re-answers and field corrections", operationInterruptions),
        ("A pending correction journal preserves newer ordinary sessions", newerWorkDuringPending),
        ("Credits linked to a split predecessor remain independently undoable", creditedPredecessor),
        ("Credit Undo and field Undo preserve each other's independently changed values", creditAndFields),
        ("A missing classified record is a visible conflict rather than invented recovery", missingRecordConflict),
        ("A stale Retry cannot finalise a different pending journal action", staleJournalRetry),
        ("Visible Retry completes failed legacy classifications and credited endings", visibleRetry),
        ("Field Undo preserves its receipt when its saved record is temporarily absent", missingFieldRecord),
        ("Every replacement control exposes committed archive finalisation failure and scoped Retry", controlFinalisationFailures),
        ("Ordinary durable capacity retirement removes only its corresponding correction history", ordinaryRetirement),
        ("Journalled capacity retirement survives stale preference restoration", journalledRetirement),
        ("Partial field retirement preserves Undo for the surviving stretch", partialFieldRetirement),
        ("Failed ordinary append cannot publish retirement and finalisation preserves live time", retirementFailures),
        ("Standalone archives with correction metadata refuse unjournalled retirement", standaloneRetirement),
        ("Unrelated capacity retirement retains temporarily removed original records", temporaryRecordRetention),
        ("Capacity archival of uncredited work retains its ending checkpoint across interruption", capacityEndingRecovery),
        ("Interrupted journalled eviction publishes retirement only after the archive commits", interruptedJournalledRetirement),
        ("Record-free intervals retire only beyond a proven retained-window boundary", recordFreeWindowRetention),
        ("Field Undo survives retirement of all original IDs while live or continued effects remain", continuedFieldRetention),
        ("Continuation and explicit-new consumers respect refused and unfinished replacement", continuationConsumerFailures)
    ]

    private final class Fixture {
        var time = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fc-decision-history-\(UUID())")
        let suite = "fc.decision-history.\(UUID())"
        lazy var defaults = UserDefaults(suiteName: suite)!
        var journalFailure: (() -> String?)?
        var capacity = FocusConstants.archiveCapacity
        var archiveFailure: (([SessionRecord]) -> String?)?
        lazy var archive = SessionArchive(directory: directory, now: { self.time }, capacity: capacity,
                                         writeOverride: { self.archiveFailure?($0) })
        lazy var engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
            ownBundleID: "fc.history.test", schedulesDwell: false,
            correctionWriteOverride: { self.journalFailure?() }, now: { self.time })
        var applicationRunning: (String) -> Bool = { _ in false }
        var appActivations: [(bundleID: String, thread: UUID)] = []
        lazy var store = SessionStore(engine: engine, schedulesTicker: false,
            applicationIsRunning: { self.applicationRunning($0) },
            activateApplication: { bundle, _ in self.appActivations.append((bundle, self.engine.activeThreadID)) },
            now: { self.time })
        func absence() {
            time.addTimeInterval(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            time.addTimeInterval(1_200)
            engine.transition(on: .awayEnded)
        }
        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func olderUndo() -> [String] { runOlderUndo(relaunch: false) }
    private static func restoredOlderUndo() -> [String] { runOlderUndo(relaunch: true) }
    private static func runOlderUndo(relaunch: Bool) -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser")
            f.absence()
            guard f.store.resolve(.tookBreak), let first = f.engine.lastAwayDecision else {
                return ["first answer setup failed"]
            }
            f.absence()
            guard f.store.resolve(.tookBreak), let second = f.engine.lastAwayDecision else {
                return ["second answer setup failed"]
            }
            f.time.addTimeInterval(300)
            f.engine.stop()
            let later = f.archive.records.filter { $0.id != first.insertedRecord?.id }
            let store: SessionStore
            if relaunch {
                let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                    archive: SessionArchive(directory: f.directory, now: { f.time }),
                    ownBundleID: "fc.history.test", schedulesDwell: false, now: { f.time })
                engine.restore(from: f.engine.snapshot())
                store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
            } else { store = f.store }
            guard store.undoAwayDecision(expectedID: first.id) else {
                return ["the first receipt is unavailable after answering a second absence"]
            }
            guard store.engine.archive.records == later else { return ["older Undo changed later work"] }
            guard store.storyTimelineItems.contains(where: {
                if case .decision(let receipt, _) = $0 { return receipt.id == second.id && receipt.isResolved }
                return false
            }) else { return ["the later decision lost its own confirmation row"] }
            return []
        }
    }

    private static func equalCredits() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser")
            f.absence(); guard f.store.resolve(.mergeTime), let first = f.engine.lastAwayDecision else { return ["first credit setup"] }
            f.absence(); guard f.store.resolve(.mergeTime), let second = f.engine.lastAwayDecision else { return ["second credit setup"] }
            f.time.addTimeInterval(300); f.engine.stop()
            let stale = f.engine.snapshot()
            guard f.store.undoAwayDecision(expectedID: first.id),
                  f.archive.records.first?.workSeconds == 2_700 else { return ["older equal credit did not subtract exactly 1,200 seconds"] }
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: SessionArchive(directory: f.directory, now: { f.time }), schedulesDwell: false, now: { f.time })
            engine.restore(from: stale)
            guard !engine.undoAwayDecision(expectedID: first.id),
                  engine.undoAwayDecision(expectedID: second.id),
                  engine.archive.records.first?.workSeconds == 1_500 else {
                return ["stale equal-credit restoration lost identity, debited twice or blocked the other valid Undo"]
            }
            return []
        }
    }

    private static func liveCreditRecovery() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser")
            f.absence(); guard f.store.resolve(.mergeTime), let id = f.engine.lastAwayDecision?.id else { return ["credit setup"] }
            let stale = f.engine.snapshot()
            guard f.store.undoAwayDecision(expectedID: id) else { return ["live Undo failed"] }
            f.time.addTimeInterval(300)
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: f.archive,
                schedulesDwell: false, now: { f.time })
            engine.restore(from: stale)
            guard !engine.undoAwayDecision(expectedID: id), engine.elapsed == 600 else {
                return ["live debit replayed or unobserved closed-app time became focus"]
            }
            engine.start(workType: .learning, intent: "Later")
            f.time.addTimeInterval(180)
            return engine.elapsed == 180 ? [] : ["old recovery rewound later work"]
        }
    }

    private static func journalFailures() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for failWrite in [1, 2] {
                let f = Fixture(); defer { f.cleanUp() }
                f.engine.start(workType: .deepWork, intent: "Parser")
                f.absence(); guard f.store.resolve(.mergeTime), let id = f.engine.lastAwayDecision?.id else { return ["credit setup"] }
                f.engine.stop()
                let stale = f.engine.snapshot()
                var calls = 0
                f.journalFailure = { calls += 1; return calls == failWrite ? "Injected journal failure" : nil }
                if f.store.undoAwayDecision(expectedID: id) { problems.append("journal failure was reported as saved") }
                f.journalFailure = nil
                let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                    archive: SessionArchive(directory: f.directory, now: { f.time }), schedulesDwell: false, now: { f.time })
                engine.restore(from: stale)
                if failWrite == 1 && !engine.undoAwayDecision(expectedID: id) { problems.append("prepared-write failure lost retry") }
                if failWrite == 2 && engine.undoAwayDecision(expectedID: id) { problems.append("finalisation failure repeated the debit") }
                if engine.archive.records.first?.workSeconds != 600 { problems.append("journal interruption changed exact focus total") }
            }
            return problems
        }
    }

    private static func row(_ record: SessionRecord) -> DaySession {
        DaySession(id: record.id, threadID: record.threadID, name: record.name, workType: record.workType,
            start: record.start, end: record.end, worked: record.workSeconds, stretches: 1,
            spans: [DateInterval(start: record.start, end: record.end)], isRunning: false)
    }
    private static func fieldAndAway() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser"); f.absence()
            guard f.store.resolve(.tookBreak), let id = f.engine.lastAwayDecision?.id else { return ["break setup"] }
            let other = SessionRecord(name: "Different", workType: .learning,
                start: f.time.addingTimeInterval(-7_200), end: f.time.addingTimeInterval(-6_600), workSeconds: 600)
            f.archive.append(other)
            guard f.store.renameSession(row(other), to: "Renamed"), f.store.undoAwayDecision(expectedID: id),
                  f.archive.records.first(where: { $0.id == other.id })?.name == "Renamed" else {
                return ["renaming another thread erased earlier Undo or older Undo reverted that name"]
            }
            return []
        }
    }
    private static func fieldHistory() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            let record = SessionRecord(name: "Original", workType: .deepWork,
                start: f.time.addingTimeInterval(-600), end: f.time, workSeconds: 600)
            f.archive.append(record)
            guard f.store.renameSession(row(record), to: "First"), let first = f.store.lastCorrection?.id,
                  f.store.renameSession(row(record), to: "Second"), let second = f.store.lastCorrection?.id else { return ["rename setup"] }
            guard !f.store.undoCorrection(expectedID: first), f.archive.records.first?.name == "Second" else {
                return ["older rename overwrote a newer same-field correction"]
            }
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: SessionArchive(directory: f.directory, now: { f.time }), schedulesDwell: false, now: { f.time })
            engine.restore(from: f.engine.snapshot())
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
            guard store.undoCorrection(expectedID: second), store.undoCorrection(expectedID: first),
                  engine.archive.records.first?.name == "Original" else { return ["durable field Undo stack was lost"] }
            return []
        }
    }
    private static func migration() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            let start = f.time.addingTimeInterval(-1_200)
            let record = SessionRecord(name: "Lunch", workType: .breakTime, start: start, end: f.time, workSeconds: 1_200)
            f.archive.append(record)
            var old = f.engine.snapshot()
            old.awayDecisions = nil; old.correctionGeneration = nil
            old.awayDecision = AwayDecisionReceipt(id: UUID(), range: DateInterval(start: start, end: f.time),
                name: "Parser", workType: .deepWork, threadID: UUID(), sessionStart: start.addingTimeInterval(-600),
                decision: .tookBreak, insertedRecord: record, creditedSeconds: 0)
            f.engine.restore(from: old)
            return f.engine.awayDecisions.count == 1 && f.engine.undoAwayDecision(expectedID: old.awayDecision!.id)
                && f.archive.records.isEmpty ? [] : ["legacy single receipt did not migrate with its ID intact"]
        }
    }

    private static func legacyClassification() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            let target = SessionRecord(name: "Research", workType: .learning,
                start: f.time.addingTimeInterval(-3_600), end: f.time.addingTimeInterval(-3_000), workSeconds: 600)
            let rest = SessionRecord(name: "Driving", workType: .breakTime,
                start: f.time.addingTimeInterval(-1_200), end: f.time, workSeconds: 1_200)
            f.archive.append(target); f.archive.append(rest)
            guard f.engine.reclassifyLegacyBreak(recordID: rest.id, decision: .continueSession),
                  f.archive.records == [target], let uncounted = f.engine.lastAwayDecision,
                  f.engine.undoAwayDecision(expectedID: uncounted.id), f.archive.records.contains(rest) else {
                return ["Leave uncounted did not retain an exact recoverable original break"]
            }
            guard !f.engine.reclassifyLegacyBreak(recordID: rest.id, decision: .mergeTime),
                  f.engine.reclassifyLegacyBreak(recordID: rest.id, decision: .mergeTime, focusTargetID: target.id),
                  let counted = f.engine.lastAwayDecision, counted.insertedRecord?.threadID == target.threadID,
                  counted.insertedRecord?.workSeconds == 1_200, counted.insertedRecord?.workType == .learning,
                  f.engine.undoAwayDecision(expectedID: counted.id), f.archive.records.contains(rest) else {
                return ["legacy focus credit did not require a target, retain scope or restore original break"]
            }
            return []
        }
    }

    private static func failedCreditStop() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.mergeTime)
            f.journalFailure = { "Injected journal preparation failure" }
            f.engine.stop()
            guard f.engine.state == .running, f.engine.elapsed == 1_800, f.archive.records.isEmpty else {
                return ["failed credit-stop journal discarded the unarchived live stretch"]
            }
            f.journalFailure = nil
            f.engine.stop()
            return f.engine.state == .idle && f.archive.records.first?.workSeconds == 1_800 ? [] : ["credit stop could not be retried"]
        }
    }

    private static func failedCreditReplacement() -> [String] {
        MainActor.assumeIsolated {
            for startsNew in [true, false] {
                let f = Fixture(); defer { f.cleanUp() }
                f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.mergeTime)
                let thread = f.engine.activeThreadID, start = f.engine.sessionStartDate
                f.journalFailure = { "Injected journal failure" }
                f.engine.stop()
                if startsNew { f.engine.start(workType: .learning, intent: "Replacement") }
                else { f.engine.transition(on: .resetSession) }
                guard f.engine.activeThreadID == thread, f.engine.sessionStartDate == start,
                      f.engine.sessionName == "Parser", f.engine.activeWorkType == .deepWork,
                      f.engine.state == .running, f.engine.elapsed == 1_800, f.archive.records.isEmpty else {
                    return ["failed Stop followed by \(startsNew ? "Start" : "Reset") discarded credited work"]
                }
            }
            return []
        }
    }

    private static func operationInterruptions() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for operation in ["initialBreak", "initialCredit", "reanswer", "rename"] {
                for failWrite in [1, 2] {
                    let f = Fixture(); defer { f.cleanUp() }
                    f.engine.start(workType: .deepWork, intent: "Parser"); f.absence()
                    if operation == "reanswer" || operation == "rename" {
                        f.store.resolve(.continueSession)
                        if operation == "reanswer" { f.store.undoLastCorrection() }
                        f.engine.stop()
                    }
                    let stale = f.engine.snapshot()
                    var calls = 0
                    f.journalFailure = { calls += 1; return calls == failWrite ? "Injected journal boundary failure" : nil }
                    let action: () -> Bool = {
                        switch operation {
                        case "initialBreak": return f.store.resolve(.tookBreak)
                        case "initialCredit": return f.store.resolve(.mergeTime)
                        case "reanswer": return f.store.applyAwayDecision(.mergeTime, reviewing: true)
                        default: return f.store.renameSession(row(f.archive.records.first!), to: "Changed")
                        }
                    }
                    if action() { problems.append("\(operation) journal failure claimed success") }
                    f.journalFailure = nil
                    let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                        archive: SessionArchive(directory: f.directory, now: { f.time }), schedulesDwell: false, now: { f.time })
                    engine.restore(from: stale)
                    let store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
                    if failWrite == 1 {
                        switch operation {
                        case "initialBreak": _ = store.resolve(.tookBreak)
                        case "initialCredit": _ = store.resolve(.mergeTime)
                        case "reanswer": _ = store.applyAwayDecision(.mergeTime, reviewing: true)
                        default: _ = store.renameSession(row(engine.archive.records.first!), to: "Changed")
                        }
                    }
                    let focus = engine.archive.records.filter { $0.workType.countsAsFocus }.reduce(0) { $0 + $1.workSeconds }
                        + (engine.state == .idle ? 0 : engine.elapsed)
                    let expected: Double = operation == "initialCredit" || operation == "reanswer" ? 1_800 : 600
                    if focus != expected { problems.append("\(operation) interruption lost or duplicated focus: \(focus)") }
                    if operation == "rename" && (store.corrections.count != 1 || engine.archive.records.first?.name != "Changed") {
                        problems.append("interrupted rename lost its identity or saved value")
                    }
                    if operation != "rename" && engine.awayDecisions.count != 1 { problems.append("\(operation) duplicated physical receipt") }
                }
            }
            return problems
        }
    }

    private static func newerWorkDuringPending() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.mergeTime); f.engine.stop()
            let id = f.engine.lastAwayDecision!.id
            var calls = 0
            f.journalFailure = { calls += 1; return calls >= 2 ? "Finalisation unavailable" : nil }
            _ = f.store.undoAwayDecision(expectedID: id)
            f.engine.start(workType: .learning, intent: "Later")
            f.time.addTimeInterval(180); f.engine.stop()
            let snapshot = f.engine.snapshot()
            f.journalFailure = nil
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: SessionArchive(directory: f.directory, now: { f.time }), schedulesDwell: false, now: { f.time })
            engine.restore(from: snapshot)
            return engine.state == .idle && engine.archive.records.count == 2
                && engine.archive.records.first?.workSeconds == 600 && engine.archive.records.last?.workSeconds == 180
                && engine.archive.records.last?.name == "Later" ? [] : ["pending journal rewound or removed later ordinary work"]
        }
    }

    private static func creditedPredecessor() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.mergeTime)
            let first = f.engine.lastAwayDecision!.id
            f.absence(); f.store.resolve(.mergeTime); let second = f.engine.lastAwayDecision!.id
            f.absence(); f.store.resolve(.continueSession)
            guard f.store.undoAwayDecision(expectedID: first), f.store.undoAwayDecision(expectedID: second) else {
                return ["splitting the credited live stretch lost a receipt's exact predecessor identity"]
            }
            return f.archive.records.first?.workSeconds == 1_800 ? [] : ["predecessor credit subtraction changed real work"]
        }
    }

    private static func creditAndFields() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.mergeTime); f.engine.stop()
            let awayID = f.engine.lastAwayDecision!.id
            let record = f.archive.records.first!
            guard f.store.renameSession(row(record), to: "Renamed"), let nameID = f.store.lastCorrection?.id,
                  f.store.setWorkType(.learning, for: row(record)), let typeID = f.store.lastCorrection?.id,
                  f.store.undoAwayDecision(expectedID: awayID), f.archive.records.first?.name == "Renamed",
                  f.archive.records.first?.workType == .learning, f.archive.records.first?.workSeconds == 600,
                  f.store.undoCorrection(expectedID: nameID), f.archive.records.first?.workType == .learning,
                  f.store.undoCorrection(expectedID: typeID), f.archive.records.first?.workSeconds == 600 else {
                return ["independent name, type and credited-seconds corrections overwrote one another"]
            }
            return []
        }
    }

    private static func missingRecordConflict() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.tookBreak)
            let receipt = f.engine.lastAwayDecision!
            _ = f.archive.edit(removing: [receipt.insertedRecord!])
            return !f.store.undoAwayDecision(expectedID: receipt.id) && f.store.correctionError != nil
                && f.engine.awayDecision(id: receipt.id)?.isResolved == true ? []
                : ["a missing source record was silently treated as a completed Undo"]
        }
    }

    private static func staleJournalRetry() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.tookBreak)
            let oldID = f.engine.lastAwayDecision!.id
            f.absence(); f.store.resolve(.tookBreak)
            let newID = f.engine.lastAwayDecision!.id
            var calls = 0
            f.journalFailure = { calls += 1; return calls == 2 ? "Final journal write unavailable" : nil }
            _ = f.engine.undoAwayDecision(expectedID: newID)
            f.journalFailure = nil
            f.store.correctionRetry = .awayUndo(oldID)
            let records = f.archive.records
            // The saved Retry belonged to the older resolved row. It must
            // neither report success for the newer transaction nor mutate it.
            let result = f.store.retryLastCorrection()
            return !result && f.archive.records == records
                && f.engine.awayDecision(id: oldID)?.isResolved == true ? []
                : ["stale Retry accepted another operation's pending journal"]
        }
    }

    private static func visibleRetry() -> [String] {
        MainActor.assumeIsolated {
            for legacy in [true, false] {
                for failWrite in [1, 2] {
                    let f = Fixture(); defer { f.cleanUp() }
                    let rest = SessionRecord(name: "Driving", workType: .breakTime,
                        start: f.time.addingTimeInterval(-1_200), end: f.time, workSeconds: 1_200)
                    if legacy { f.archive.append(rest) }
                    else { f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.mergeTime) }
                    var calls = 0
                    f.journalFailure = { calls += 1; return calls == failWrite ? "Journal boundary unavailable" : nil }
                    if legacy { _ = f.store.reclassifyLegacyBreak(recordID: rest.id, decision: .continueSession) }
                    else { f.store.stop() }
                    f.journalFailure = nil
                    guard f.store.correctionError != nil, f.store.retryLastCorrection(), f.store.correctionError == nil else {
                        return ["visible Retry could not finish \(legacy ? "legacy classification" : "credited ending") at journal boundary \(failWrite)"]
                    }
                    if legacy && (!f.archive.records.isEmpty || f.engine.awayDecisions.count != 1) { return ["legacy retry duplicated effects"] }
                    if !legacy && (f.engine.state != .idle || f.archive.records.first?.workSeconds != 1_800) { return ["ending retry lost live work"] }
                }
            }
            return []
        }
    }

    private static func missingFieldRecord() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.cleanUp() }
            let record = SessionRecord(name: "Parser", workType: .deepWork,
                start: f.time.addingTimeInterval(-600), end: f.time, workSeconds: 600)
            f.archive.append(record)
            guard f.store.setWorkType(.breakTime, for: row(record)), let id = f.store.lastCorrection?.id,
                  f.engine.reclassifyLegacyBreak(recordID: record.id, decision: .continueSession) else { return ["nested correction setup"] }
            let missing = f.archive.records
            guard !f.store.undoCorrection(expectedID: id), f.store.correctionError != nil,
                  f.store.corrections.contains(where: { $0.id == id }), f.archive.records == missing else {
                return ["Undo discarded a field receipt while its record was held by another reversible classification"]
            }
            guard f.engine.undoAwayDecision(), f.store.retryLastCorrection(), f.archive.records == [record] else {
                return ["restoring the classified record did not make its original field Undo retryable"]
            }
            return []
        }
    }

    private static func controlFinalisationFailures() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for route in ["hotkey", "start", "quick", "automatic"] {
                let f = Fixture(); defer { f.cleanUp() }
                f.engine.start(workType: .deepWork, intent: "Parser")
                f.absence(); f.store.resolve(.mergeTime)
                let oldThread = f.engine.activeThreadID, oldStart = f.engine.sessionStartDate
                let receiptID = f.engine.lastAwayDecision!.id
                var writes = 0
                f.journalFailure = { writes += 1; return writes == 2 ? "Finalisation unavailable" : nil }
                if route == "hotkey" { _ = f.store.performSessionHotKeyAction() }
                else if route == "start" { f.store.workType = .learning; f.store.intent = "Later"; f.store.start() }
                else if route == "quick" { f.store.startQuick(QuickStart(id: "later", name: "Later", workType: .learning)) }
                else { f.store.startAutomatically(workType: .learning, name: "Later", backdatedTo: f.time, because: "Fixture") }
                guard f.store.correctionError != nil,
                      case .ending(let retryThread, let retryStart)? = f.store.correctionRetry,
                      retryThread == oldThread, retryStart == oldStart else {
                    problems.append("\(route) concealed finalisation failure or bound Retry to replacement work")
                    continue
                }
                let laterThread = f.engine.activeThreadID
                f.time.addTimeInterval(180)
                let beforeRetry = f.engine.snapshot()
                f.journalFailure = nil
                guard f.store.retryLastCorrection(), f.store.correctionError == nil,
                      f.archive.records.count == 1, f.archive.records.first?.workSeconds == 1_800,
                      f.engine.awayDecision(id: receiptID)?.isResolved == true,
                      f.engine.activeThreadID == laterThread,
                      f.engine.snapshot() == beforeRetry else {
                    problems.append("\(route) Retry altered later work, replayed archival or lost receipt identity")
                    continue
                }
                if route != "hotkey" && (f.engine.elapsed != 180 || f.engine.sessionName != "Later") {
                    problems.append("\(route) Retry rewound the replacement clock")
                }
            }
            return problems
        }
    }

    private static func oldDecision(_ f: Fixture) -> (UUID, SessionRecord)? {
        f.engine.start(workType: .deepWork, intent: "Parser"); f.absence()
        guard f.store.resolve(.tookBreak), let receipt = f.engine.lastAwayDecision,
              let focus = f.archive.records.first(where: { $0.workType.countsAsFocus }) else { return nil }
        f.engine.stop()
        guard f.store.renameSession(row(focus), to: "Corrected") else { return nil }
        return (receipt.id, focus)
    }

    private static func laterRecord(_ f: Fixture, name: String = "Later", thread: UUID = UUID()) -> SessionRecord {
        SessionRecord(name: name, workType: .learning, start: f.time, end: f.time.addingTimeInterval(60),
                      workSeconds: 60, threadID: thread)
    }

    private static func ordinaryRetirement() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
            guard let (id, focus) = oldDecision(f), let fieldID = f.store.lastCorrection?.id else { return ["old decision setup"] }
            let stale = f.engine.snapshot()
            let retiredIDs = Set(f.archive.records.map(\.id))
            f.archive.append(laterRecord(f, name: "One"))
            guard f.engine.awayDecision(id: id) == nil, f.store.corrections.contains(where: { $0.id == fieldID }) else {
                return ["ordinary capacity eviction left the retired break receipt or removed an unrelated field receipt"]
            }
            f.archive.append(laterRecord(f, name: "Two"))
            guard f.store.corrections.isEmpty, f.engine.retainedCorrectionRecordIDs.isDisjoint(with: retiredIDs),
                  !f.archive.records.contains(where: { $0.id == focus.id }) else {
                return ["ordinary retirement retained field metadata for a genuinely evicted stretch"]
            }
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: SessionArchive(directory: f.directory, now: { f.time }, capacity: 2), schedulesDwell: false, now: { f.time })
            engine.restore(from: stale)
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
            return engine.awayDecisions.isEmpty && store.corrections.isEmpty
                && !store.storyTimelineItems.contains(where: { if case .decision = $0 { return true }; return false })
                ? [] : ["stale preferences resurrected retired correction rows"]
        }
    }

    private static func journalledRetirement() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
            guard let (oldID, _) = oldDecision(f) else { return ["old decision setup"] }
            let oldIDs = Set(f.archive.records.map(\.id)), stale = f.engine.snapshot()
            f.engine.start(workType: .learning, intent: "New research"); f.absence()
            guard f.store.resolve(.tookBreak), let newest = f.engine.lastAwayDecision else { return ["new decision setup"] }
            guard f.engine.awayDecision(id: oldID) == nil, f.store.corrections.isEmpty,
                  f.engine.retainedCorrectionRecordIDs.isDisjoint(with: oldIDs), f.archive.records.count == 2 else {
                return ["journalled capacity eviction left retired away or field metadata"]
            }
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: SessionArchive(directory: f.directory, now: { f.time }, capacity: 2), schedulesDwell: false, now: { f.time })
            engine.restore(from: stale)
            return engine.awayDecisions.map(\.id) == [newest.id] && engine.retainedCorrectionRecordIDs.isDisjoint(with: oldIDs)
                ? [] : ["relaunch resurrected metadata retired by a journalled answer"]
        }
    }

    private static func partialFieldRetirement() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
            let thread = UUID(), first = laterRecord(f, name: "Original")
            let a = SessionRecord(id: first.id, name: "Original", workType: .learning, start: first.start,
                                  end: first.end, workSeconds: 60, threadID: thread)
            let b = laterRecord(f, name: "Original", thread: thread)
            f.archive.append(a); f.archive.append(b)
            guard f.store.renameSession(row(a), to: "Changed"), let id = f.store.lastCorrection?.id else { return ["field setup"] }
            let stale = f.engine.snapshot(), newer = laterRecord(f)
            f.archive.append(newer)
            guard let field = f.store.corrections.first(where: { $0.id == id }),
                  field.archiveRecordIDs == [b.id], field.archiveSnapshot?.fields.map(\.recordID) == [b.id],
                  !f.engine.retainedCorrectionRecordIDs.contains(a.id) else {
                return ["partial retirement did not remove exactly the evicted field references"]
            }
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: SessionArchive(directory: f.directory, now: { f.time }, capacity: 2), schedulesDwell: false, now: { f.time })
            engine.restore(from: stale)
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
            return store.undoCorrection(expectedID: id) && engine.archive.records == [b, newer]
                ? [] : ["the surviving field correction could not be undone after relaunch"]
        }
    }

    private static func retirementFailures() -> [String] {
        MainActor.assumeIsolated {
            for phase in ["archive", "finalisation"] {
                let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
                guard let (id, _) = oldDecision(f) else { return ["old decision setup"] }
                f.engine.start(workType: .learning, intent: "Live later work")
                f.time.addTimeInterval(180)
                let before = f.archive.records, state = f.engine.snapshot(), added = laterRecord(f)
                let fieldIDs = f.store.corrections.map(\.id)
                if phase == "archive" { f.archiveFailure = { _ in "Archive unavailable" } }
                else {
                    var writes = 0
                    f.journalFailure = { writes += 1; return writes == 2 ? "Finalisation unavailable" : nil }
                }
                f.archive.append(added)
                if phase == "archive" {
                    guard f.archive.records == before, f.engine.awayDecision(id: id) != nil,
                          f.store.corrections.map(\.id) == fieldIDs else { return ["failed append published false retirement"] }
                } else {
                    guard f.archive.records == [before[1], added], f.engine.awayDecision(id: id) == nil else {
                        return ["committed capacity retirement was not journalled before finalisation failed"]
                    }
                }
                guard f.engine.elapsed == 180, f.engine.activeThreadID == state.threadID,
                      f.engine.sessionStartDate == state.sessionStart else { return ["metadata retirement rewound the live checkpoint"] }
                f.archiveFailure = nil; f.journalFailure = nil
                let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                    archive: SessionArchive(directory: f.directory, now: { f.time }, capacity: 2), schedulesDwell: false, now: { f.time })
                engine.restore(from: state)
                if (engine.awayDecision(id: id) != nil) != (phase == "archive") || engine.elapsed != 180 {
                    return ["\(phase) recovery chose the wrong retirement phase or rewound live work"]
                }
            }
            return []
        }
    }

    private static func standaloneRetirement() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
            guard oldDecision(f) != nil else { return ["old decision setup"] }
            let standalone = SessionArchive(directory: f.directory, now: { f.time }, capacity: 2)
            let before = standalone.records
            let error = standalone.append(laterRecord(f))
            let editError = standalone.edit(adding: [laterRecord(f, name: "Raw edit")], allowsEviction: true)
            let reloaded = SessionArchive(directory: f.directory, now: { f.time }, capacity: 2)
            return error != nil && editError != nil && standalone.records == before && reloaded.records == before ? []
                : ["a standalone archive silently evicted history without correction retirement proof"]
        }
    }

    private static func temporaryRecordRetention() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
            let original = laterRecord(f, name: "Original")
            f.archive.append(original)
            guard f.store.setWorkType(.breakTime, for: row(original)), let fieldID = f.store.lastCorrection?.id,
                  f.engine.reclassifyLegacyBreak(recordID: original.id, decision: .continueSession),
                  let awayID = f.engine.lastAwayDecision?.id else { return ["temporary removal setup"] }
            f.archive.append(laterRecord(f, name: "One")); f.archive.append(laterRecord(f, name: "Two"))
            f.archive.append(laterRecord(f, name: "Three"))
            return f.store.corrections.contains(where: { $0.id == fieldID }) && f.engine.awayDecision(id: awayID) != nil
                && f.engine.retainedCorrectionRecordIDs.contains(original.id) ? []
                : ["unrelated capacity retirement purged a temporarily held original record"]
        }
    }

    private static func capacityEndingRecovery() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
            guard oldDecision(f) != nil else { return ["old decision setup"] }
            f.engine.start(workType: .learning, intent: "Uncredited later work")
            f.time.addTimeInterval(180)
            let stale = f.engine.snapshot()
            var writes = 0
            f.journalFailure = { writes += 1; return writes == 2 ? "Finalisation unavailable" : nil }
            f.store.stop()
            f.journalFailure = nil
            guard f.engine.state == .idle, f.store.correctionError != nil, f.store.retryLastCorrection() else {
                return ["capacity ending Retry could not finish its original operation"]
            }
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: SessionArchive(directory: f.directory, now: { f.time }, capacity: 2), schedulesDwell: false, now: { f.time })
            engine.restore(from: stale)
            return engine.state == .idle && engine.archive.records.last?.workSeconds == 180
                && engine.archive.records.last?.name == "Uncredited later work" ? []
                : ["metadata-only checkpoint reopened a stretch already committed by End"]
        }
    }

    private static func interruptedJournalledRetirement() -> [String] {
        MainActor.assumeIsolated {
            for failsArchive in [true, false] {
                let f = Fixture(); f.capacity = 2; defer { f.cleanUp() }
                guard let (oldID, _) = oldDecision(f) else { return ["old decision setup"] }
                let oldIDs = Set(f.archive.records.map(\.id)), oldRecords = f.archive.records
                f.engine.start(workType: .learning, intent: "Replacement"); f.absence()
                let stale = f.engine.snapshot()
                if failsArchive { f.archiveFailure = { _ in "Archive unavailable" } }
                else {
                    var writes = 0
                    f.journalFailure = { writes += 1; return writes == 2 ? "Finalisation unavailable" : nil }
                }
                guard !f.store.resolve(.tookBreak) else { return ["interrupted retirement was reported fully saved"] }
                if failsArchive {
                    guard f.archive.records == oldRecords, f.engine.awayDecision(id: oldID) != nil,
                          !f.store.corrections.isEmpty else { return ["uncommitted retirement changed visible history"] }
                } else {
                    guard f.engine.awayDecision(id: oldID) == nil, f.store.corrections.isEmpty,
                          f.engine.retainedCorrectionRecordIDs.isDisjoint(with: oldIDs) else {
                        return ["committed retirement still publishes retired field references during finalisation"]
                    }
                }
                f.archiveFailure = nil; f.journalFailure = nil
                let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                    archive: SessionArchive(directory: f.directory, now: { f.time }, capacity: 2), schedulesDwell: false, now: { f.time })
                engine.restore(from: stale)
                let store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
                if failsArchive {
                    guard engine.archive.records == oldRecords, !store.corrections.isEmpty else { return ["relaunch published uncommitted retirement"] }
                } else if engine.awayDecision(id: oldID) != nil || !store.corrections.isEmpty
                    || !engine.retainedCorrectionRecordIDs.isDisjoint(with: oldIDs) {
                    return ["relaunch resurrected committed retirement metadata"]
                }
            }
            return []
        }
    }

    private static func recordFreeWindowRetention() -> [String] {
        MainActor.assumeIsolated {
            for scenario in ["inclusive", "crossing", "noEviction", "noBoundary", "live", "surviving", "held", "missingExplicit"] {
                let f = Fixture(); f.capacity = scenario == "noBoundary" ? 0 : 2; defer { f.cleanUp() }
                f.engine.start(workType: .deepWork, intent: "Brief start")
                let sourceThread = f.engine.activeThreadID, sourceStart = f.engine.sessionStartDate
                f.engine.transition(on: .awayBegan(trigger: .screenLock)); f.time.addTimeInterval(1_200)
                f.engine.transition(on: .awayEnded)
                guard f.store.resolve(scenario == "missingExplicit" ? .tookBreak : .continueSession),
                      let receipt = f.engine.lastAwayDecision else { return ["record-free interval setup failed"] }
                if scenario == "missingExplicit", let record = receipt.insertedRecord { _ = f.archive.edit(removing: [record]) }
                guard f.archive.records.isEmpty else { return ["record-free archive setup failed"] }
                if scenario != "live" { f.engine.stop() }
                let boundary = receipt.range.end.addingTimeInterval(scenario == "crossing" ? -1 : 0)
                let oldStart = scenario == "noEviction" ? receipt.range.end : sourceStart.addingTimeInterval(-600)
                let old = SessionRecord(name: "Old unrelated", workType: .learning,
                    start: oldStart, end: oldStart.addingTimeInterval(60), workSeconds: 60)
                let anchor = SessionRecord(name: "Source anchor", workType: scenario == "held" ? .breakTime : .deepWork,
                    start: receipt.range.end, end: receipt.range.end.addingTimeInterval(60), workSeconds: 60,
                    threadID: sourceThread)
                if scenario == "held" {
                    f.archive.append(anchor)
                    guard f.engine.reclassifyLegacyBreak(recordID: anchor.id, decision: .continueSession) else { return ["held anchor setup"] }
                }
                f.archive.append(old)
                if scenario == "surviving" { f.archive.append(anchor) }
                else { f.archive.append(SessionRecord(name: "Window start", workType: .learning,
                    start: boundary, end: boundary.addingTimeInterval(60), workSeconds: 60)) }
                if scenario != "noEviction" { f.archive.append(laterRecord(f, name: "New boundary")) }
                let expectedPresent = scenario != "inclusive"
                if (f.engine.awayDecision(id: receipt.id) != nil) != expectedPresent {
                    return ["record-free retirement violated \(scenario) boundary/anchor protection"]
                }
            }
            return []
        }
    }

    private static func continuedFieldRetention() -> [String] {
        MainActor.assumeIsolated {
            for live in [true, false] {
                let f = Fixture(); f.capacity = 1; defer { f.cleanUp() }
                let original = laterRecord(f, name: "Original")
                f.archive.append(original)
                guard f.store.renameSession(row(original), to: "Changed"), let id = f.store.lastCorrection?.id else { return ["field setup"] }
                f.engine.start(workType: .learning, intent: "Changed", threadID: original.threadID)
                f.time.addTimeInterval(120)
                if live { f.archive.append(laterRecord(f, name: "Unrelated")) }
                else { f.engine.stop() }
                guard let remaining = f.store.corrections.first(where: { $0.id == id }),
                      remaining.archiveRecordIDs.isEmpty, remaining.archiveSnapshot?.fields.isEmpty == true,
                      !f.engine.retainedCorrectionRecordIDs.contains(original.id),
                      f.store.undoCorrection(expectedID: id) else {
                    return ["retiring original IDs lost the correction's \(live ? "live" : "continued") effect"]
                }
                if live {
                    guard f.engine.sessionName == "Original", f.engine.elapsed == 120,
                          f.archive.records.first?.name == "Unrelated" else { return ["live field Undo changed timing or unrelated work"] }
                } else if f.archive.records.count != 1 || f.archive.records.first?.name != "Original"
                    || f.archive.records.first?.workSeconds != 120 || f.archive.records.first?.id == original.id {
                    return ["continued field Undo resurrected retirement or altered recorded work"]
                }
            }
            return []
        }
    }

    private static func continuationConsumerFailures() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for route in ["thread", "session", "new", "app", "automaticCorrection"] {
                for failWrite in [1, 2] {
                    let f = Fixture(); defer { f.cleanUp() }
                    f.time = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
                    f.engine.start(workType: .deepWork, intent: "Parser"); f.absence(); f.store.resolve(.mergeTime)
                    let target = SessionRecord(name: "Target activity", workType: .learning,
                        start: f.time.addingTimeInterval(-660), end: f.time.addingTimeInterval(-60), workSeconds: 600)
                    f.archive.append(target)
                    let thread = ThreadSummary(threadID: target.threadID, name: target.name, workType: target.workType,
                        totalWorked: 600, segments: 1, firstStart: target.start, lastEnd: target.end, isRunning: false)
                    let app = "fc.fixture.target"
                    f.applicationRunning = { $0 == app }
                    let usage = AppUsageArchive(directory: f.directory.appendingPathComponent("usage"), now: { f.time })
                    usage.record(AppUsageSession(bundleID: app, appName: target.name, start: target.start, end: target.end))
                    f.store.usage = usage
                    if route == "thread", f.store.threadApps(thread).primary?.bundleID != app { return ["thread activation setup failed"] }
                    if route == "automaticCorrection" {
                        var automatic = f.engine.snapshot(); automatic.isAuto = true
                        f.engine.restore(from: automatic); f.store.refresh()
                        guard f.store.isAutoSession else { return ["automatic correction setup failed"] }
                    }
                    let oldThread = f.engine.activeThreadID, oldStart = f.engine.sessionStartDate
                    let records = f.archive.records
                    var writes = 0
                    f.journalFailure = { writes += 1; return writes == failWrite ? "Injected control save failure" : nil }
                    switch route {
                    case "thread": f.store.continueThread(thread)
                    case "session": f.store.continueSession(row(target))
                    case "new": f.store.startNewSession(from: row(target))
                    case "app": f.store.continueApp(AppUsageSummary(bundleID: app, appName: target.name,
                        totalSeconds: 600, longestSeconds: 600, recent: usage.sessions))
                    default:
                        f.store.workType = .learning; f.store.intent = target.name
                        f.store.applyAutomaticSessionCorrection()
                    }
                    if failWrite == 1 && !f.appActivations.isEmpty { problems.append("\(route) activated an app after refused replacement") }
                    if failWrite == 1 && route == "automaticCorrection" && f.store.intent != target.name {
                        problems.append("automatic correction cleared the refused draft")
                    }
                    guard f.store.correctionError != nil, case .ending(let id, let start)? = f.store.correctionRetry,
                          id == oldThread, start == oldStart else {
                        problems.append("\(route) failed to expose or bind save phase \(failWrite)"); continue
                    }
                    if failWrite == 1 {
                        if f.engine.activeThreadID != oldThread || f.engine.elapsed != 1_800 || f.archive.records != records {
                            problems.append("\(route) changed work after refused replacement")
                        }
                    } else {
                        let replacement = f.engine.activeThreadID
                        guard replacement != oldThread else { problems.append("\(route) did not create the accepted replacement"); continue }
                        if route == "thread" || route == "app" {
                            if f.appActivations.count != 1 || f.appActivations.first?.thread != replacement {
                                problems.append("\(route) activation occurred before the successful replacement")
                            }
                        }
                        f.time.addTimeInterval(180); let beforeRetry = f.engine.snapshot()
                        f.journalFailure = nil
                        if !f.store.retryLastCorrection() || f.engine.snapshot() != beforeRetry || f.engine.elapsed != 180 {
                            problems.append("\(route) finalisation Retry altered replacement work")
                        }
                    }
                }
            }
            return problems
        }
    }
}
