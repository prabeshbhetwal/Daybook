import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Automatic correction is an App-boundary operation: Core knows how to
    /// resume/adopt/discard a session, while only SessionStore can also notify
    /// the coordinator to resume background usage tracking after declared Away.
    static func testDeclaredAwayAutomaticCorrectionRoutes() -> [String] {
        var problems: [String] = []

        func makeAutomatic(_ pause: PauseReason?, declaredAwayFor: TimeInterval = 0)
            -> (store: SessionStore, engine: SessionEngine,
                archive: SessionArchive, clock: TestClock) {
            let clock = TestClock(base)
            let archive = SessionArchive(directory: scratchDirectory(), now: { clock.value })
            let persistence = PersistenceStore(
                defaults: MemoryDefaults.suite(named: suiteName) ?? .standard)
            persistence.removeAll()
            persistence.breakThreshold = FocusConstants.defaultThreshold
            persistence.longAwayCap = FocusConstants.defaultLongAwayCap
            let engine = SessionEngine(
                store: persistence,
                archive: archive,
                ownBundleID: "com.test",
                schedulesDwell: false,
                now: { clock.value })
            engine.start(workType: .deepWork, intent: "Detected coding", isAuto: true)
            clock.advance(12 * 60)
            if let pause {
                switch pause {
                case .away:
                    engine.transition(on: .markedAway)
                case .watching:
                    engine.transition(on: .watchingObserved(
                        seconds: FocusConstants.idlePauseThreshold))
                default:
                    engine.transition(on: .manualPause)
                }
            }
            // Exercise the real persisted automatic ownership that can survive
            // into every paused state without adding a test-only engine setter.
            var snapshot = engine.snapshot()
            snapshot.isAuto = true
            engine.restore(from: snapshot)
            // The away runs on after the restore, in the live engine. Restoring
            // a snapshot already past the cap would end the stretch at launch,
            // which is a relaunch, not the live Undo this scenario exercises.
            clock.advance(declaredAwayFor)
            return (SessionStore(engine: engine, now: { clock.value }),
                    engine, archive, clock)
        }

        let adopted = makeAutomatic(.away)
        let adoptedThread = adopted.engine.activeThreadID
        var adoptTrackingResumes = 0
        var adoptResumedBeforeCorrection = false
        adopted.store.onAwayEnded = {
            adoptTrackingResumes += 1
            adoptResumedBeforeCorrection = adopted.engine.state == .running
                && adopted.store.isAutoSession
        }
        adopted.store.intent = "Owned coding"
        adopted.store.applyAutomaticSessionCorrection()
        expect(adoptTrackingResumes == 1 && adoptResumedBeforeCorrection,
               "declared-Away adoption resumes usage tracking exactly once, before correction",
               &problems)
        expect(adopted.engine.state == .running && !adopted.store.isAutoSession,
               "adoption resumes as a user-owned running session", &problems)
        expect(adopted.store.activeIntent == "Owned coding"
                   && adopted.engine.activeThreadID == adoptedThread,
               "same-type adoption retains the session thread and requested intent", &problems)
        expect(adopted.archive.records.isEmpty,
               "adoption does not create an artificial archive seam", &problems)

        let reclassified = makeAutomatic(.away)
        let oldThread = reclassified.engine.activeThreadID
        var reclassifyTrackingResumes = 0
        var reclassifyResumedBeforeCorrection = false
        reclassified.store.onAwayEnded = {
            reclassifyTrackingResumes += 1
            reclassifyResumedBeforeCorrection = reclassified.engine.state == .running
                && reclassified.store.isAutoSession
        }
        reclassified.store.intent = "Admin follow-up"
        reclassified.store.workType = .admin
        reclassified.store.applyAutomaticSessionCorrection()
        expect(reclassifyTrackingResumes == 1 && reclassifyResumedBeforeCorrection,
               "declared-Away reclassification resumes tracking once, before correction",
               &problems)
        expect(reclassified.engine.state == .running
                   && reclassified.engine.activeWorkType == .admin
                   && reclassified.store.activeIntent == "Admin follow-up"
                   && !reclassified.store.isAutoSession,
               "reclassification starts the requested user-owned work", &problems)
        expect(reclassified.engine.activeThreadID != oldThread
                   && reclassified.archive.records.last?.isAuto == true,
               "reclassification closes the detected work and starts a fresh thread", &problems)

        let undone = makeAutomatic(.away)
        var undoEvents: [String] = []
        undone.store.onAwayEnded = { undoEvents.append("tracking resumed") }
        undone.store.onAutoSessionUndone = { undoEvents.append("automatic session undone") }
        undone.store.undoAutomaticSessionCorrection()
        expect(undoEvents == ["automatic session undone", "tracking resumed"],
               "declared-Away Undo discards before resuming tracking exactly once", &problems)
        expect(undone.engine.state == .idle
                   && undone.archive.records.isEmpty,
               "Undo retains discard and detector-suppression semantics", &problems)

        for pause in [Optional<PauseReason>.none, .some(.manual), .some(.watching)] {
            let ordinary = makeAutomatic(pause)
            var trackingResumes = 0
            ordinary.store.onAwayEnded = { trackingResumes += 1 }
            ordinary.store.intent = "Ordinary correction"
            ordinary.store.applyAutomaticSessionCorrection()
            expect(trackingResumes == 0,
                   "\(String(describing: pause)) correction does not fake an away end",
                   &problems)
            expect(ordinary.engine.state == .running && !ordinary.store.isAutoSession,
                   "\(String(describing: pause)) keeps its existing adoption semantics",
                   &problems)
        }

        let undoBoundaries: [(label: String, seconds: TimeInterval)] = [
            ("just below break threshold", FocusConstants.defaultThreshold - 1),
            ("at break threshold", FocusConstants.defaultThreshold),
            ("above break threshold", FocusConstants.defaultThreshold + 1),
            ("beyond long-away cap", FocusConstants.defaultLongAwayCap + 1)
        ]
        for boundary in undoBoundaries {
            let scenario = makeAutomatic(.away, declaredAwayFor: boundary.seconds)
            var events: [String] = []
            scenario.store.onAutoSessionUndone = {
                events.append("automatic session undone")
            }
            scenario.store.onAwayEnded = { events.append("tracking resumed") }
            scenario.store.undoAutomaticSessionCorrection()
            expect(events == ["automatic session undone", "tracking resumed"],
                   "\(boundary.label) Undo emits discard then one tracking resume; got \(events)",
                   &problems)
            expect(scenario.engine.state == .idle && !scenario.store.isAutoSession,
                   "\(boundary.label) Undo ends idle without automatic ownership",
                   &problems)
            expect(scenario.archive.records.isEmpty,
                   "\(boundary.label) Undo retains no detected work or Away record",
                   &problems)
        }
        return problems
    }

    /// A pristine install has no Application Support directory yet. Reveal
    /// creates it before asking Finder, while both creation and Finder refusal
    /// produce deterministic, concrete diagnostics.
    static func testRevealDataFolderWorkflow() -> [String] {
        var problems: [String] = []
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pristine = root.appendingPathComponent("pristine/data", isDirectory: true)
        var opened: [URL] = []
        var logs: [String] = []

        let revealed = SettingsModel.revealDataFolder(
            at: pristine,
            open: { opened.append($0); return true },
            log: { logs.append($0) })
        expect(revealed, "a pristine data folder is created and revealed", &problems)
        expect(FileManager.default.fileExists(atPath: pristine.path),
               "the pristine data directory now exists", &problems)
        expect(opened == [pristine] && logs.isEmpty,
               "Finder receives the exact directory without a failure log", &problems)

        logs = []
        let refused = SettingsModel.revealDataFolder(
            at: pristine, open: { _ in false }, log: { logs.append($0) })
        expect(!refused, "Finder refusal is returned as failure", &problems)
        expect(logs.count == 1 && logs[0].contains(pristine.path)
               && logs[0].contains("could not reveal data folder"),
               "Finder refusal logs the concrete directory", &problems)

        let blocker = root.appendingPathComponent("not-a-directory")
        try? Data("blocked".utf8).write(to: blocker)
        let impossible = blocker.appendingPathComponent("child", isDirectory: true)
        logs = []
        var attemptedOpen = false
        let created = SettingsModel.revealDataFolder(
            at: impossible,
            open: { _ in attemptedOpen = true; return true },
            log: { logs.append($0) })
        expect(!created && !attemptedOpen,
               "a creation failure never asks Finder to open a missing path", &problems)
        expect(logs.count == 1 && logs[0].contains(impossible.path)
               && logs[0].contains("could not create data folder"),
               "creation failure logs the concrete directory", &problems)
        return problems
    }

    // MARK: - 83

    /// "vs last week" needs last week. The figure is the same rollup the chart
    /// uses, one period back, so it can never disagree with the bars.
    static func testPreviousPeriodTracked() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(base)
        let calendar = Calendar.current
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let stats = PeriodStats(sessions: SessionArchive(directory: directory,
                                                         now: { clock.value }),
                                usage: usage, now: { clock.value })

        let thisWeek = stats.bounds(for: .week, containing: clock.value)
        guard let lastWeekDay = calendar.date(byAdding: .day, value: -3, to: thisWeek.start),
              let twoWeeksDay = calendar.date(byAdding: .day, value: -10, to: thisWeek.start)
        else { return ["could not build the weeks"] }
        func record(_ day: Date, minutes: Double) {
            let start = calendar.startOfDay(for: day).addingTimeInterval(10 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start,
                                         end: start.addingTimeInterval(minutes * 60)))
        }
        record(clock.value, minutes: 30)       // this week
        record(lastWeekDay, minutes: 45)       // last week
        record(twoWeeksDay, minutes: 70)       // the week before — must not count

        expectClose(stats.previousPeriodTracked(for: .week, containing: clock.value),
                    45 * 60, "last week's tracked total", &problems)
        expectClose(stats.previousPeriodTracked(for: .week, containing: lastWeekDay),
                    70 * 60, "and the week before that, one step back", &problems)
        expectClose(PeriodStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                         now: { clock.value }),
                                usage: AppUsageArchive(directory: scratchDirectory(),
                                                       now: { clock.value }),
                                now: { clock.value })
                        .previousPeriodTracked(for: .month, containing: clock.value),
                    0, "nothing recorded reads as zero", &problems)
        return problems
    }
}
