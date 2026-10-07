import Foundation

/// A launch whose preferences hold no snapshot — set aside as unreadable, or
/// out of reach of a process started from a sandboxed shell — still resumes
/// from the correction journal beside the archive. On 2026-10-07 such a launch
/// started blank, generations behind its own journal, and answering the away
/// question swapped the journal's checkpoint in under it: the answer was
/// refused with "This interval changed", then "That interval was retired or
/// changed" on every try after.
enum BlankPreferencesLaunchChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A launch with blank preferences resumes from the correction journal and saves the next away answer",
         { answerAfterBlankLaunch(finalised: true) }),
        ("A launch with blank preferences resumes from a journal whose only answer is still pending",
         { answerAfterBlankLaunch(finalised: false) }),
        ("An engine behind its correction journal loads it where the day can see, and refuses the answer with a reason",
         laggingEngineRefusesVisibly),
        ("An answer refused because newer saved history replaced its interval closes the card and offers no Retry",
         replacedAnswerOffersNoRetry),
        ("An answer saved but not finalised keeps the Retry that finalises it", unfinalisedAnswerKeepsRetry),
    ]

    private final class Fixture {
        var time = Date(timeIntervalSince1970: 1_788_000_000)
        let directory = SelfTest.scratchDirectory()
        var suites: [String] = []
        var journalWrites = 0
        var failJournalWrite: Int?

        /// A launch on fresh, empty preferences beside the same data folder.
        func blankLaunch() -> SessionEngine {
            let suite = "fc-selftest-blank-prefs-\(UUID().uuidString)"
            suites.append(suite)
            return SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
                archive: SessionArchive(directory: directory, now: { self.time }),
                ownBundleID: "fc.blank-prefs.fixture", schedulesDwell: false,
                correctionWriteOverride: {
                    self.journalWrites += 1
                    return self.journalWrites == self.failJournalWrite ? "probe: finalisation refused" : nil
                }, now: { self.time })
        }

        /// Work, then a lock long enough to be asked about, then the unlock.
        func asked(_ engine: SessionEngine) -> Bool {
            if engine.state == .idle { engine.start(workType: .deepWork, intent: "") }
            time.addTimeInterval(1_200)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            time.addTimeInterval(1_800)
            engine.transition(on: .awayEnded)
            if case .awaitingUserDecision = engine.state { return true }
            return false
        }

        /// One answered break in the journal, then the app quits. With
        /// `finalised` false the journal keeps it as a pending transaction:
        /// its second write, the finalisation, is refused.
        func journalOneAnswer(finalised: Bool) {
            let engine = blankLaunch()
            engine.start(workType: .deepWork, intent: "Coding")
            _ = asked(engine)
            if !finalised { failJournalWrite = journalWrites + 2 }
            _ = engine.decide(.tookBreak, label: "Lunch")
            failJournalWrite = nil
            engine.persist()
            time.addTimeInterval(300)
        }

        func close() {
            for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func answerAfterBlankLaunch(finalised: Bool) -> [String] {
        var problems: [String] = []
        let f = Fixture(); defer { f.close() }
        f.journalOneAnswer(finalised: finalised)
        let engine = f.blankLaunch()
        expect(AppCoordinator.restorePersistedEngine(engine, awayAtLaunch: false),
               "blank preferences should restore from the correction journal", &problems)
        expect(f.asked(engine), "the next absence should be asked about, got \(engine.state)", &problems)
        expect(engine.decide(.tookBreak, label: "Brunch"), "the answer after a blank launch should save; error: "
               + "\(engine.awayDecisionError ?? "none"), state \(engine.state)", &problems)
        let names = engine.archive.records.map(\.name)
        expect(names.contains("Brunch"), "the Brunch break should be recorded, got \(names)", &problems)
        expect(names.contains("Lunch"), "the earlier Lunch break should survive the relaunch, got \(names)", &problems)
        return problems
    }

    /// Never restored, as every launch on blank preferences once was.
    private static func laggingEngineRefusesVisibly() -> [String] {
        var problems: [String] = []
        let f = Fixture(); defer { f.close() }
        f.journalOneAnswer(finalised: true)
        let engine = f.blankLaunch()
        expect(f.asked(engine), "the absence should be asked about, got \(engine.state)", &problems)
        var published: [SessionState] = []
        engine.onStateChanged = { published.append($0) }
        let saved = engine.decide(.tookBreak, label: "Brunch")
        expect(!saved, "an answer to a question the journal has replaced should not save", &problems)
        expect(engine.awayDecisionError != nil, "the refusal should give a reason, got none", &problems)
        let closed = published.last.map { state -> Bool in
            if case .awaitingUserDecision = state { return false }
            return true
        } ?? false
        expect(closed, "the loaded state should be published so the card closes, got \(published)", &problems)
        return problems
    }

    /// The store's side of the same refusal: a reason, no question left for
    /// the card, and no Retry that could only fail.
    private static func replacedAnswerOffersNoRetry() -> [String] {
        var problems: [String] = []
        let f = Fixture(); defer { f.close() }
        f.journalOneAnswer(finalised: true)
        let engine = f.blankLaunch()
        expect(f.asked(engine), "the absence should be asked about, got \(engine.state)", &problems)
        MainActor.assumeIsolated {
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
            store.catchUpWithEngine()
            let saved = store.resolve(.tookBreak, label: "Brunch", expectedID: engine.pendingDecisionID)
            store.catchUpWithEngine()
            expect(!saved, "an answer to a replaced interval should not save", &problems)
            expect(store.correctionError != nil, "the refusal should be shown with a reason, got none", &problems)
            expect(store.correctionRetry == nil,
                   "no Retry should be offered for a replaced interval, got \(String(describing: store.correctionRetry))",
                   &problems)
            expect(store.pendingAway == nil,
                   "the card's question should be gone, got \(String(describing: store.pendingAway))", &problems)
        }
        return problems
    }

    /// The other way an answered question leaves: its records landed and only
    /// the journal's finalisation was refused. That Retry can still land.
    private static func unfinalisedAnswerKeepsRetry() -> [String] {
        var problems: [String] = []
        let f = Fixture(); defer { f.close() }
        let engine = f.blankLaunch()
        expect(f.asked(engine), "the absence should be asked about, got \(engine.state)", &problems)
        MainActor.assumeIsolated {
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { f.time })
            store.catchUpWithEngine()
            f.failJournalWrite = f.journalWrites + 2
            let saved = store.resolve(.tookBreak, label: "Brunch", expectedID: engine.pendingDecisionID)
            f.failJournalWrite = nil
            expect(!saved, "an answer whose finalisation was refused should report it", &problems)
            expect(store.correctionRetry != nil, "its Retry should still be offered, got none", &problems)
            expect(store.retryLastCorrection(), "the Retry should finalise the answer; error: "
                   + "\(store.correctionError ?? "none")", &problems)
            expect(engine.decisionHistory.document.pending == nil,
                   "the journal should hold no pending answer after the Retry", &problems)
        }
        return problems
    }
}
