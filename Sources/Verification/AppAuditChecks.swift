import Foundation

/// App-layer fixes from the production audit of 13 November 2026: what keeps
/// the ticker, what a quit saves, what the shortcut and the detector report,
/// what the power queue keeps, and how Ask and the name suggester end.
enum AppAuditChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An idle or watching pause keeps the ticker with recording off, until the cap ends it",
         unattendedPauseKeepsTicker),
        ("A quit saves notes being written, and never empties or creates a blank one", quitSavesNoteDrafts),
    ]

    /// A store over its own engine, metadata sidecar and preferences.
    @MainActor
    private static func noteStore(failing: Bool, suite: String) -> (SessionStore, SessionMetadataArchive)? {
        let folder = SelfTest.scratchDirectory()
        guard let engine = SessionMetadataChecks.engine(at: SelfTest.base, directory: folder, suite: suite) else {
            return nil
        }
        let metadata = SessionMetadataArchive(directory: folder,
                                              writeOverride: failing ? { _ in "The note could not be saved." } : nil)
        return (SessionStore(engine: engine, schedulesTicker: false, metadataArchive: metadata,
                             now: { SelfTest.base }), metadata)
    }

    private static func quitSavesNoteDrafts() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let suite = "fc-selftest-audit-notes-\(UUID().uuidString)"
            let failingSuite = "fc-selftest-audit-notes-failing-\(UUID().uuidString)"
            defer { MemoryDefaults.remove(named: suite); MemoryDefaults.remove(named: failingSuite) }
            guard let good = noteStore(failing: false, suite: suite),
                  let failing = noteStore(failing: true, suite: failingSuite)?.0
            else { return ["could not create isolated preferences"] }
            let (store, metadata) = good

            let written = UUID(), emptied = UUID(), blank = UUID(), unchanged = UUID()
            _ = metadata.saveNote("Kept note", for: emptied)
            _ = metadata.saveNote("Same note", for: unchanged)
            store.beginNoteEditing(for: written)
            store.setNoteDraft("Written before quitting", for: written)
            store.beginNoteEditing(for: emptied)
            store.setNoteDraft("  ", for: emptied)
            store.beginNoteEditing(for: blank)
            store.beginNoteEditing(for: unchanged)
            expect(store.saveNoteDraftsBeforeQuit(), "every draft saves", &problems)
            expect(metadata.metadata(for: written)?.note == "Written before quitting",
                   "the draft is saved, got \(String(describing: metadata.metadata(for: written)?.note))", &problems)
            expect(store.noteDraft(for: written).isEmpty, "a saved draft is closed", &problems)
            expect(metadata.metadata(for: emptied)?.note == "Kept note",
                   "a blank draft leaves the saved note, got \(String(describing: metadata.metadata(for: emptied)?.note))",
                   &problems)
            expect(metadata.metadata(for: blank) == nil, "a blank draft creates no note", &problems)
            expect(metadata.metadata(for: unchanged)?.note == "Same note", "an unchanged draft stays as it was", &problems)

            let lost = UUID()
            failing.beginNoteEditing(for: lost)
            failing.setNoteDraft("Cannot be written", for: lost)
            expect(!failing.saveNoteDraftsBeforeQuit(), "a refused write reports false", &problems)
            expect(failing.noteDraft(for: lost) == "Cannot be written" && failing.noteError(for: lost) != nil,
                   "a refused draft keeps its text and error, got \(failing.noteDraft(for: lost))", &problems)
            return problems
        }
    }

    private static func unattendedPauseKeepsTicker() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // No tracker: app-use recording is off, so only the session can keep the ticker.
            guard let f = BreakStoreChecks.make(ticker: true, prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            let threshold = f.persistence.idlePauseThreshold, cap = f.persistence.longAwayCap
            f.engine.transition(on: .idleObserved(seconds: threshold))
            f.store.refresh()
            expect(f.engine.state == .paused(reason: .idle), "quiet pauses the session, got \(f.engine.state)", &problems)
            expect(f.store.hasScheduledTicker, "an idle pause keeps the ticker that resumes it", &problems)
            f.engine.transition(on: .idleObserved(seconds: 1))
            f.store.refresh()
            expect(f.engine.state.isRunning, "input resumes the idle pause, got \(f.engine.state)", &problems)

            // Nobody comes back: past the cap the session ends, and nothing is left to tick for.
            f.engine.transition(on: .idleObserved(seconds: threshold))
            f.clock.advance(cap)
            f.engine.transition(on: .idleObserved(seconds: threshold + cap))
            f.store.refresh()
            expect(f.engine.state == .idle, "the cap ends an abandoned idle pause, got \(f.engine.state)", &problems)
            expect(!f.store.hasScheduledTicker, "the ticker stops once the session has ended", &problems)

            guard let g = BreakStoreChecks.make(ticker: true, prepare: BreakStoreChecks.running) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { g.close() }
            g.engine.transition(on: .watchingObserved(seconds: threshold))
            g.store.refresh()
            expect(g.engine.state == .paused(reason: .watching), "a film pauses the session, got \(g.engine.state)", &problems)
            expect(g.store.hasScheduledTicker, "a watching pause keeps the ticker that ends it", &problems)
            return problems
        }
    }
}
