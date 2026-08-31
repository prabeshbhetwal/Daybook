import Foundation

/// Screenshot-driven interaction regressions. These fixtures never load the
/// application's real defaults, running session or history.
enum StoryInteractionChecks {
    static let tests: [(String, () -> [String])] = [
        ("A custom activity is reusable even after a short session and relaunch", rememberedActivity),
        ("Story presents the current stretch before earlier work and rest", newestFirst),
        ("Undoing a break decision preserves work recorded afterwards", undoBreak),
        ("Undoing credited away time preserves subsequent live work", undoCreditedAway),
        ("A failed away undo preserves its records and remains retryable", failedAwayUndo),
        ("A restored decision can be undone without touching a newer session", restoredAwayUndo),
        ("An undone absence can be reclassified without replaying the session", reviseAway),
        ("A failed decision does not partially save or leave the pending state", failedDecision),
        ("Away Undo refuses to overwrite a subsequent record edit", newerEditSurvivesUndo),
        ("Activity suggestions deduplicate names without inventing categories", activitySuggestions),
        ("Shape bars retain unknown intervals and clip recorded coverage", shapeBars),
        ("Opening the application reveals its Story without a session sheet", revealApplication),
        ("Interrupted archived Undo cannot debit the same absence twice", interruptedUndo),
        ("Restoring a pending absence keeps its original interval", restoredInterval),
        ("Historical reclassification cannot evict unrelated work", historicalCapacity),
        ("A stale decision retry cannot answer a different absence", staleRetry),
        ("A saved decision occupies one chronological row beside current work", inlineDecision),
        ("Meeting evidence does not claim every minute was counted", meetingEvidence),
        ("Interrupted re-answer does not insert the absence twice", interruptedReanswer),
        ("Interrupted initial resolution does not insert duplicate stretches", interruptedResolution),
        ("Visual fixtures exercise real shapes, meetings, live work and contextual Undo", visualInteractionFixtures),
        ("Recovered decisions preserve presence gating while the Mac remains locked", recoveredDecisionWhileLocked),
        ("A recovered answer cannot credit an interval whose predecessor was already archived", incompatibleRecoveredAnswer),
        ("A named away answer keeps its draft until storage succeeds", retainedAwayReason),
        ("Cross-day Undo declares the complete interval before activation", crossDayUndoScope),
        ("An away prompt retry cannot save an unrelated failed correction", scopedAwayRetry)
    ]

    private final class Clock {
        var value = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))!
        func advance(_ seconds: TimeInterval) { value.addTimeInterval(seconds) }
    }

    private final class Fixture {
        let clock = Clock()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-story-interaction-\(UUID().uuidString)")
        let suite = "fc.story.interaction.\(UUID().uuidString)"
        let defaults: UserDefaults
        let engine: SessionEngine
        let store: SessionStore

        init(capacity: Int = FocusConstants.archiveCapacity,
             writeOverride: (([SessionRecord]) -> String?)? = nil) {
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Could not create isolated interaction defaults")
            }
            self.defaults = defaults
            let clock = self.clock
            let archive = SessionArchive(directory: directory, now: { clock.value }, capacity: capacity,
                                         writeOverride: writeOverride)
            engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "fc.interaction.test", schedulesDwell: false,
                                   now: { clock.value })
            store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        }

        func close() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        func awaitDecision() {
            engine.start(workType: .deepWork, intent: "Parser")
            clock.advance(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(1_200)
            engine.transition(on: .awayEnded)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private static func rememberedActivity() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            f.store.intent = "  Analyse invoices  "
            f.store.workType = .admin
            f.store.start()
            f.clock.advance(1)
            f.store.stop()
            let reloaded = SessionEngine(store: PersistenceStore(defaults: f.defaults),
                archive: f.engine.archive, ownBundleID: "fc.interaction.test", schedulesDwell: false,
                now: { f.clock.value })
            let store = SessionStore(engine: reloaded, now: { f.clock.value })
            guard f.engine.archive.records.isEmpty else { return ["fixture must not depend on a saved session"] }
            return store.quickStarts.contains { $0.name == "Analyse invoices" && $0.workType == .admin }
                ? [] : ["the typed activity disappeared instead of being offered after relaunch"]
        }
    }

    private static func newestFirst() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let start = f.clock.value
            f.engine.archive.append(SessionRecord(name: "Earlier", workType: .deepWork,
                start: start, end: start.addingTimeInterval(600), workSeconds: 600))
            f.engine.archive.append(SessionRecord(name: "Tea", workType: .breakTime,
                start: start.addingTimeInterval(600), end: start.addingTimeInterval(900), workSeconds: 300))
            f.clock.advance(1_200)
            f.engine.start(workType: .learning, intent: "Current")
            f.clock.advance(120)
            let moments = f.store.storyMoments
            guard case .entry(.session(let first))? = moments.first, first.isRunning else {
                return ["current work is below earlier entries"]
            }
            guard moments.map(\.start) == moments.map(\.start).sorted(by: >) else {
                return ["rest or recording gaps are out of reverse chronological order"]
            }
            return abs(f.store.storyFocusedSeconds(on: start) - 720) < 0.01
                ? [] : ["presentation order changed the focused total"]
        }
    }

    private static func undoBreak() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.tookBreak, label: "Lunch")
            f.clock.advance(300)
            f.engine.stop()
            let work = f.engine.archive.records.filter { $0.workType.countsAsFocus }
            guard f.store.undoLastCorrection() else { return ["the recorded break decision has no Undo"] }
            guard f.engine.archive.records == work else {
                return ["away Undo removed or rewrote work after the decision"]
            }
            return []
        }
    }

    private static func undoCreditedAway() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.mergeTime)
            f.clock.advance(300)
            guard f.store.undoLastCorrection() else { return ["credited absence cannot be undone"] }
            return f.engine.state == .running && abs(f.engine.elapsed - 900) < 0.01
                ? [] : ["Undo failed to remove only the twenty-minute absence credit"]
        }
    }

    private static func failedAwayUndo() -> [String] {
        MainActor.assumeIsolated {
            var blocked = false
            let f = Fixture(writeOverride: { _ in blocked ? "Fixture storage unavailable" : nil })
            defer { f.close() }; f.awaitDecision()
            f.store.resolve(.tookBreak)
            let before = f.engine.archive.records
            blocked = true
            if f.store.undoLastCorrection() || f.engine.archive.records != before {
                return ["failed Undo changed durable evidence or claimed success"]
            }
            guard f.store.correctionError != nil && f.store.canUndoCorrection else {
                return ["failed Undo has no visible, retained recovery action"]
            }
            blocked = false
            return f.store.retryLastCorrection() ? [] : ["Undo could not be retried after storage recovered"]
        }
    }

    private static func restoredAwayUndo() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.mergeTime)
            f.clock.advance(300)
            f.engine.stop()
            let snapshot = f.engine.snapshot()
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: f.engine.archive,
                ownBundleID: "fc.interaction.test", schedulesDwell: false, now: { f.clock.value })
            engine.restore(from: snapshot)
            let store = SessionStore(engine: engine, now: { f.clock.value })
            guard store.canUndoCorrection else { return ["the restored receipt has no visible Undo"] }
            engine.start(workType: .learning, intent: "New work")
            f.clock.advance(180)
            guard store.undoLastCorrection() else { return ["archived away credit could not be undone"] }
            guard abs(engine.elapsed - 180) < 0.01,
                  abs(engine.archive.records.reduce(0) { $0 + $1.workSeconds } - 900) < 0.01 else {
                return ["Undo rewound newer work or failed to remove the original absence credit"]
            }
            return []
        }
    }

    private static func reviseAway() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.tookBreak)
            f.clock.advance(300)
            let thread = f.engine.activeThreadID
            for _ in 0..<2 {
                guard f.store.undoLastCorrection(),
                      f.store.applyAwayDecision(.mergeTime, reviewing: true) else {
                    return ["Undo did not allow the same interval to be answered again"]
                }
                guard abs(f.engine.elapsed - 300) < 0.01, f.engine.activeThreadID == thread,
                      abs(f.engine.archive.records.reduce(0) { $0 + $1.workSeconds } - 1_800) < 0.01,
                      f.engine.archive.records.allSatisfy({ $0.workType.countsAsFocus }) else {
                    return ["re-answering duplicated the interval or replayed the running-session transition"]
                }
            }
            return []
        }
    }

    private static func failedDecision() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(writeOverride: { _ in "Fixture storage unavailable" })
            defer { f.close() }; f.awaitDecision()
            let state = f.engine.snapshot()
            f.store.resolve(.tookBreak, label: "Lunch")
            guard f.engine.snapshot() == state, f.engine.archive.records.isEmpty,
                  f.store.correctionError != nil, !f.store.canUndoCorrection else {
                return ["failed decision published a partial record, success or changed live state"]
            }
            return []
        }
    }

    private static func newerEditSurvivesUndo() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.tookBreak)
            guard let rest = f.engine.archive.records.first(where: { $0.workType == .breakTime }) else {
                return ["expected a recorded break"]
            }
            f.engine.archive.rename(thread: rest.threadID, to: "Later correction")
            let records = f.engine.archive.records
            return !f.store.undoLastCorrection() && f.engine.archive.records == records
                && f.store.correctionError != nil ? []
                : ["Undo erased a newer edit to its former record"]
        }
    }

    private static func activitySuggestions() -> [String] {
        let result = ActivityChoices.merging([
            QuickStart(id: "bad", name: "  Invoice review  ", workType: .admin),
            QuickStart(id: "duplicate", name: "INVOICE REVIEW", workType: .deepWork),
            QuickStart(id: "empty", name: "   ", workType: .deepWork),
            QuickStart(id: "rest", name: "Lunch", workType: .breakTime)
        ], [QuickStart(id: "history", name: "Read chapter", workType: .learning)])
        return result.map(\.name) == ["Invoice review", "Read chapter"]
            && result.map(\.workType) == [.admin, .learning] ? []
            : ["choices duplicate names, include rest/empty entries, or lose the saved work type"]
    }

    private static func shapeBars() -> [String] {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func segment(_ app: String, _ a: Double, _ b: Double) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: app, appName: app,
                start: start.addingTimeInterval(a), end: start.addingTimeInterval(b),
                colorIndex: 0, endReason: .appSwitch)
        }
        let bins = SessionShape.bins(segments: [
            segment("Editor", -300, 900), segment("Editor", 0, 450),
            segment("Browser", 1_350, 1_800), segment("Editor", 3_150, 3_900)
        ], in: DateInterval(start: start, duration: 3_600))
        guard bins.map(\.recordedSeconds) == [450, 450, 0, 450, 0, 0, 0, 450] else {
            return ["shape bars count overlap, data outside the session, or unknown time as activity"]
        }
        let empty = SessionShape.bins(segments: [], in: DateInterval(start: start, duration: 3_600))
        return empty.count == 8 && empty.allSatisfy { $0.recordedSeconds == 0 && $0.dominantBundleID == nil }
            ? [] : ["a session without recording acquired an invented activity shape"]
    }

    private static func revealApplication() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let navigation = MainWindowModel(storyScope: .month, store: f.store)
            navigation.openStoryDay(f.clock.value.addingTimeInterval(-86_400))
            let day = f.store.selectedDay
            navigation.selectScope(.month)
            navigation.openSheet(.focus)
            navigation.revealApplication()
            guard navigation.sheet == nil, navigation.storyScope == .month,
                  Calendar.current.isDate(f.store.selectedDay, inSameDayAs: day) else {
                return ["Open FocusContinuity forced a session sheet or discarded the selected Story"]
            }
            navigation.openSheet(.focus)
            return navigation.sheet == nil && navigation.sessionControlsExpanded
                ? [] : ["explicit in-window session controls became unreachable"]
        }
    }

    private static func interruptedUndo() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.mergeTime)
            f.clock.advance(900)
            f.engine.stop()
            let stale = f.engine.snapshot()
            guard f.store.undoLastCorrection() else { return ["initial Undo failed"] }
            let archive = SessionArchive(directory: f.directory, now: { f.clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: archive,
                ownBundleID: "fc.interaction.test", schedulesDwell: false, now: { f.clock.value })
            engine.restore(from: stale)
            _ = engine.undoAwayDecision()
            return abs(archive.records.reduce(0) { $0 + $1.workSeconds } - 1_500) < 0.01
                ? [] : ["stale persisted receipt debited already-undone credit a second time"]
        }
    }

    private static func restoredInterval() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            let shown = f.engine.pendingAwayRange!
            f.clock.advance(300)
            let snapshot = f.engine.snapshot()
            f.clock.advance(10_800)
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: f.engine.archive,
                ownBundleID: "fc.interaction.test", schedulesDwell: false, now: { f.clock.value })
            engine.restore(from: snapshot)
            guard engine.decide(.continueSession), engine.undoAwayDecision(),
                  engine.reviseAwayDecision(.mergeTime), let record = engine.lastAwayDecision?.insertedRecord else {
                return ["the restored interval could not be reviewed"]
            }
            guard record.start == shown.start, record.end == shown.end else {
                return ["receipt/reclassification moved the absence to the relaunch time"]
            }
            guard abs(engine.elapsed - 300) < 0.01,
                  abs(engine.archive.records.reduce(0) { $0 + $1.workSeconds } - 1_800) < 0.01 else {
                return ["restored resolution misplaced or lost work done before relaunch"]
            }
            return []
        }
    }

    private static func historicalCapacity() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(capacity: 2); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.continueSession)
            _ = f.store.undoLastCorrection()
            f.clock.advance(60); f.engine.stop()
            f.engine.start(workType: .learning, intent: "Later work")
            f.clock.advance(60); f.engine.stop()
            let records = f.engine.archive.records
            let revised = f.store.applyAwayDecision(.tookBreak, reviewing: true)
            return !revised && f.engine.archive.records == records && f.store.correctionError != nil
                ? [] : ["an old interval silently displaced newer records at capacity"]
        }
    }

    private static func staleRetry() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.tookBreak, label: "Lunch")
            f.store.resolve(.tookBreak, label: "Lunch") // a duplicate click is not a storage failure
            f.clock.advance(60)
            f.engine.transition(on: .awayBegan(trigger: .screenLock))
            f.clock.advance(1_800)
            f.engine.transition(on: .awayEnded)
            let before = f.engine.snapshot()
            let retried = f.store.retryLastCorrection()
            return !retried && f.engine.snapshot() == before ? []
                : ["a retry for the old absence classified the new question"]
        }
    }

    private static func inlineDecision() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.tookBreak)
            f.clock.advance(300)
            let items = f.store.storyTimelineItems
            let decisions = items.filter { if case .decision = $0 { return true }; return false }
            let rests = items.filter { if case .moment(.entry(.rest)) = $0 { return true }; return false }
            guard items.first?.isLive == true, decisions.count == 1, rests.isEmpty,
                  Set(items.map(\.id)).count == items.count else {
                return ["the decision is duplicated, detached from its chronology, or above current work"]
            }
            f.store.selectDay(offset: 1)
            return f.store.storyTimelineItems.contains { if case .decision = $0 { return true }; return false }
                ? ["the receipt leaked into an unrelated historical day"] : []
        }
    }

    private static func meetingEvidence() -> [String] {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let text = SessionShape.paragraph(.init(segments: [TimelineSegment(id: UUID(), bundleID: "zoom",
            appName: "Zoom", start: start, end: start.addingTimeInterval(1_800), colorIndex: 0,
            endReason: .idle)], workType: .meetings, stretches: 1, worked: 600)) ?? ""
        return text.lowercased().contains("counted in full")
            ? ["a ten-minute logged meeting is described as counted in full for a thirty-minute span"] : []
    }

    private static func interruptedReanswer() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            f.store.resolve(.continueSession)
            _ = f.store.undoLastCorrection()
            f.engine.stop()
            let stale = f.engine.snapshot()
            guard f.engine.reviseAwayDecision(.mergeTime) else { return ["first re-answer failed"] }
            let archive = SessionArchive(directory: f.directory, now: { f.clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: archive,
                ownBundleID: "fc.interaction.test", schedulesDwell: false, now: { f.clock.value })
            engine.restore(from: stale)
            _ = engine.reviseAwayDecision(.mergeTime)
            guard abs(archive.records.reduce(0) { $0 + $1.workSeconds } - 1_800) < 0.01 else {
                return ["recovered re-answer appended the same twenty-minute absence twice"]
            }
            guard engine.undoAwayDecision(), abs(archive.records.reduce(0) { $0 + $1.workSeconds } - 600) < 0.01 else {
                return ["one Undo did not restore the pre-answer six hundred seconds"]
            }
            return []
        }
    }

    private static func interruptedResolution() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            let stale = f.engine.snapshot()
            f.store.resolve(.tookBreak, label: "Lunch")
            let original = f.engine.archive.records
            let archive = SessionArchive(directory: f.directory, now: { f.clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: archive,
                ownBundleID: "fc.interaction.test", schedulesDwell: false, now: { f.clock.value })
            engine.restore(from: stale)
            _ = engine.decide(.tookBreak, label: "Lunch")
            return archive.records == original ? []
                : ["restoring the pre-answer state duplicated already-saved work or rest"]
        }
    }

    private static func visualInteractionFixtures() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for name in ["storyShape", "storyMeeting", "storyLive", "storyDecision"] {
                guard let scenario = SnapshotScenario(rawValue: name) else {
                    problems.append("Missing reference-matched visual fixture: \(name)")
                    continue
                }
                let store = Snapshotter.store(for: scenario)
                if store.hasScheduledTicker {
                    problems.append("The injected fixture clock is still being driven by live idle sampling")
                }
                let sessions = store.storyMoments.compactMap { moment -> DaySession? in
                    if case .entry(.session(let session)) = moment { return session }
                    return nil
                }
                if name == "storyShape", let session = sessions.first {
                    let detail = store.storySessionDetail(session)
                    if detail.apps.count < 3 || detail.bins.count != 8
                        || Set(detail.bins.map { Int($0.recordedSeconds) }).count < 3 {
                        problems.append("The shape fixture does not contain varied, recorded app coverage")
                    }
                } else if name == "storyMeeting" {
                    if sessions.first?.workType != .meetings {
                        problems.append("The meeting fixture does not lead with the amber meeting card")
                    }
                } else if name == "storyLive" {
                    if sessions.first?.isRunning != true {
                        problems.append("The live fixture does not put the current session first")
                    }
                } else if name == "storyDecision" {
                    if store.engine.lastAwayDecision?.isResolved != true || !store.canUndoCorrection {
                        problems.append("The saved-decision fixture has no actionable contextual Undo")
                    }
                }
            }
            return problems
        }
    }

    private static func recoveredDecisionWhileLocked() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }; f.awaitDecision()
            let stale = f.engine.snapshot()
            f.store.resolve(.tookBreak, label: "Lunch")
            f.clock.advance(600)
            let archive = SessionArchive(directory: f.directory, now: { f.clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: archive,
                ownBundleID: "fc.interaction.test", schedulesDwell: false, now: { f.clock.value })
            engine.restore(from: stale, awayAtLaunch: true)
            guard engine.snapshot().awayStart == f.clock.value, engine.state == .running else {
                return ["recovering a saved decision discarded the fact that the Mac is still locked"]
            }
            f.clock.advance(1_200)
            engine.transition(on: .awayEnded)
            guard case .awaitingUserDecision(let away, _) = engine.state,
                  abs(away - 1_200) < 0.01, engine.elapsed == 0 else {
                return ["the true return did not exclude the complete locked tail"]
            }
            if case .awaitingUserDecision = engine.state {
                _ = engine.decide(.tookBreak, label: "Lunch")
            }
            let focus = archive.records.filter { $0.workType.countsAsFocus }.reduce(0) { $0 + $1.workSeconds }
            return abs(focus + engine.elapsed - 600) < 0.01 ? []
                : ["the twenty minutes still locked after relaunch became session work"]
        }
    }

    private static func incompatibleRecoveredAnswer() -> [String] {
        MainActor.assumeIsolated {
            for original in [UserDecision.continueSession, .resetTimer] {
                let f = Fixture(); defer { f.close() }; f.awaitDecision()
                let stale = f.engine.snapshot()
                f.store.resolve(original)
                let records = f.engine.archive.records
                let archive = SessionArchive(directory: f.directory, now: { f.clock.value })
                let engine = SessionEngine(store: PersistenceStore(defaults: f.defaults), archive: archive,
                    ownBundleID: "fc.interaction.test", schedulesDwell: false, now: { f.clock.value })
                engine.restore(from: stale)
                guard !engine.decide(.mergeTime), engine.awayDecisionError != nil,
                      archive.records == records else {
                    return ["a conflicting recovered answer duplicated work already saved before the absence"]
                }
                guard engine.decide(original), archive.records == records else {
                    return ["the original saved answer could not be safely completed after the conflict"]
                }
            }
            return []
        }
    }

    private static func retainedAwayReason() -> [String] {
        MainActor.assumeIsolated {
            var blocked = true
            let f = Fixture(writeOverride: { _ in blocked ? "Fixture storage unavailable" : nil })
            defer { f.close() }; f.awaitDecision()
            let draft = AwayReasonDraft()
            draft.text = "  Lunch with a friend  "
            let answer: (String) -> Bool = {
                f.store.applyAwayDecision(.tookBreak, label: $0, reviewing: false)
            }
            guard !draft.submit(using: answer), draft.text == "  Lunch with a friend  ",
                  f.store.pendingAwaySaveError != nil, f.store.hasUnresolvedAwayDecision else {
                return ["a failed named answer erased its draft or made the question look resolved"]
            }
            blocked = false
            guard draft.submit(using: answer), draft.text.isEmpty, f.store.pendingAwaySaveError == nil,
                  f.engine.lastAwayDecision?.insertedRecord?.name == "Lunch with a friend" else {
                return ["successful resubmission did not preserve and then clear the entered name"]
            }
            return []
        }
    }

    private static func crossDayUndoScope() -> [String] {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        let full = DateInterval(start: midnight.addingTimeInterval(-3_600),
                                end: midnight.addingTimeInterval(3_600))
        let visible = DateInterval(start: midnight, end: full.end)
        guard let note = StoryDecisionScope.note(visible: visible, full: full),
              note.contains(Tokens.preciseDuration(full.duration)), note.contains("both days") else {
            return ["the saved row hides that Undo changes both calendar days"]
        }
        return StoryDecisionScope.note(visible: full, full: full) == nil ? []
            : ["same-day confirmations gained an unnecessary scope disclaimer"]
    }

    private static func scopedAwayRetry() -> [String] {
        MainActor.assumeIsolated {
            var blocked = false
            let f = Fixture(writeOverride: { _ in blocked ? "Fixture storage unavailable" : nil })
            defer { f.close() }
            let earlier = SessionRecord(name: "Earlier work", workType: .learning,
                start: f.clock.value.addingTimeInterval(-1_800),
                end: f.clock.value.addingTimeInterval(-1_200), workSeconds: 600)
            f.engine.archive.append(earlier)
            f.awaitDecision()
            let expectedID = f.engine.pendingDecisionID
            blocked = true
            f.store.resolve(.tookBreak)
            guard let session = f.store.storyMoments.compactMap({ moment -> DaySession? in
                if case .entry(.session(let session)) = moment, session.threadID == earlier.threadID { return session }
                return nil
            }).first, !f.store.renameSession(session, to: "Edited work") else {
                return ["fixture did not install the newer failed field correction"]
            }
            let records = f.engine.archive.records
            blocked = false
            guard !f.store.retryPendingAwayDecision(expectedID: expectedID),
                  f.engine.archive.records == records, f.store.hasUnresolvedAwayDecision else {
                return ["the away prompt's retry saved a different action or dismissed its unanswered interval"]
            }
            return f.store.retryLastCorrection() ? [] : ["the unrelated correction lost its own retry"]
        }
    }
}
