import Foundation

/// A session is never kept open across time nobody was at it. Past the
/// long-away cap a stretch ends where it was left, whether the app watched
/// the absence or was closed through it. The 2026-09-29 record ran from
/// 22:46 to 11:02 because a paused stretch was carried across a quit and a
/// restart, and only a running one was ever measured against the cap.
enum LongAwayRestoreChecks {
    static let tests: [(String, () -> [String])] = [
        ("A pause carried across a long quit ends where the pause began", pausedAcrossRelaunch),
        ("A question left up across a long quit cannot carry work across it", awaitingAcrossRelaunch),
        ("A running stretch carried across a long quit still ends where it was left", runningAcrossRelaunch),
        ("A pressed pause past the cap ends the session; a shorter one resumes it", manualPausePastCap),
        ("A second absence past the cap while asked ends the session where it began", awaitingSecondAbsence),
        ("A refused long-away end stays paused with its Retry, never silently running", refusedLongAwayEnd),
        ("A break-app pause that turns into an absence past the cap ends where the pause began",
         distractionPausePastCap)
    ]

    private static let cap: TimeInterval = 3_600
    private static let night: TimeInterval = 10 * 3_600

    private final class Fixture {
        var time = Date(timeIntervalSince1970: 1_788_000_000)
        let suite = "fc.long-away-restore.\(UUID())"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-long-away-restore-\(UUID())")
        var journalFailure: (() -> String?)?
        lazy var defaults = UserDefaults(suiteName: suite)!
        var engine: SessionEngine!

        init() {
            engine = make()
            engine.store.longAwayCap = cap
        }

        func make() -> SessionEngine {
            SessionEngine(store: PersistenceStore(defaults: defaults),
                archive: SessionArchive(directory: directory, now: { self.time }),
                ownBundleID: "fc.long-away.fixture", schedulesDwell: false,
                correctionWriteOverride: { self.journalFailure?() }, now: { self.time })
        }

        /// Quit as `applicationWillTerminate` does, then relaunch through
        /// `AppCoordinator.restorePersistedEngine`'s one call. `stale` is a
        /// snapshot the next launch reads instead of the last one written.
        func relaunch(after offline: TimeInterval, awayAtLaunch: Bool = false, stale: PersistedState? = nil) {
            engine.persist()
            if let stale { engine.store.saveState(stale) }
            time.addTimeInterval(offline)
            engine = make()
            if let saved = engine.store.loadState() { engine.restore(from: saved, awayAtLaunch: awayAtLaunch) }
        }

        func at(_ seconds: TimeInterval, _ event: SessionEvent) {
            time.addTimeInterval(seconds)
            engine.transition(on: event)
        }

        /// Work, then a lock long enough to be asked about and short of the
        /// cap, then the unlock that raises the question.
        func asked(workFirst work: TimeInterval = 1_200) -> Bool {
            engine.start(workType: .deepWork, intent: "Coding")
            at(work, .awayBegan(trigger: .screenLock))
            at(1_800, .awayEnded)
            if case .awaitingUserDecision = engine.state { return true }
            return false
        }

        /// Problems for any record, or the live stretch, whose span holds time
        /// inside `gap` — the interval nobody was at the machine.
        func spanning(_ gap: DateInterval) -> [String] {
            var problems = engine.archive.records.filter { $0.start < gap.end && $0.end > gap.start }
                .map { "record \($0.name) \($0.start) – \($0.end) spans the absence \(gap.start) – \(gap.end)" }
            if engine.state != .idle, engine.sessionStartDate < gap.end {
                problems.append("the live stretch (\(engine.state)) began \(engine.sessionStartDate), before the absence ended")
            }
            return problems
        }

        func close() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func close(_ actual: TimeInterval, _ expected: TimeInterval) -> Bool {
        abs(actual - expected) < 0.001
    }

    /// The overnight record: a Pause-button pause, the app quit, the Mac off
    /// for the night. Ended at relaunch where the pause began.
    private static func pausedAcrossRelaunch() -> [String] {
        let f = Fixture(); defer { f.close() }
        let start = f.time
        f.engine.start(workType: .deepWork, intent: "Coding")
        f.at(1_200, .manualPause)
        let paused = f.time
        f.time.addTimeInterval(600)
        let quit = f.time
        f.relaunch(after: night)
        let relaunched = f.time
        var problems: [String] = []
        if f.engine.state != .idle {
            problems.append("the paused stretch survived a \(Int(night))s quit: \(f.engine.state)")
        }
        f.at(0, .manualResume)
        if let record = f.engine.archive.records.first(where: { $0.start == start }) {
            if record.end != paused || !close(record.workSeconds, 1_200) {
                problems.append("paused stretch ended \(record.end) with \(record.workSeconds)s; expected \(paused) and 1200s")
            }
        } else {
            problems.append("no record for the paused stretch")
        }
        return problems + f.spanning(DateInterval(start: quit, end: relaunched))
    }

    /// A question still up at the quit, answered the next morning; and the
    /// case where the answer landed but the launch reads the snapshot from
    /// before it, which replays the answer. Neither may carry the night.
    private static func awaitingAcrossRelaunch() -> [String] {
        var problems: [String] = []
        do {
            let f = Fixture(); defer { f.close() }
            guard f.asked() else { return ["the lock did not raise the question"] }
            f.time.addTimeInterval(300)
            let quit = f.time
            f.relaunch(after: night)
            let relaunched = f.time
            _ = f.engine.decide(.tookBreak)
            problems += f.spanning(DateInterval(start: quit, end: relaunched))
            let focus = f.engine.archive.records.filter { $0.workType.countsAsFocus }
                .reduce(0) { $0 + $1.workSeconds } + (f.engine.state == .idle ? 0 : f.engine.elapsed)
            if !close(focus, 1_500) {
                problems.append("unanswered question across a quit kept \(focus)s of focus; expected 1500")
            }
        }
        do {
            let f = Fixture(); defer { f.close() }
            guard f.asked() else { return problems + ["the lock did not raise the replayed question"] }
            let stale = f.engine.snapshot()
            f.time.addTimeInterval(60)
            guard f.engine.decide(.tookBreak) else { return problems + ["the break answer was refused"] }
            f.time.addTimeInterval(240)
            let quit = f.time
            f.relaunch(after: night, stale: stale)
            let relaunched = f.time
            problems += f.spanning(DateInterval(start: quit, end: relaunched)).map { "replayed answer: " + $0 }
            if !f.engine.archive.records.contains(where: { $0.workType == .breakTime && $0.name == "Break" }) {
                problems.append("replayed answer lost its recorded break")
            }
        }
        return problems
    }

    /// Control: the path that always ended at the cap keeps doing so.
    private static func runningAcrossRelaunch() -> [String] {
        var problems: [String] = []
        for locked in [false, true] {
            let f = Fixture(); defer { f.close() }
            let start = f.time
            f.engine.start(workType: .deepWork, intent: "Coding")
            f.time.addTimeInterval(1_200)
            let quit = f.time
            f.relaunch(after: night, awayAtLaunch: locked)
            if locked { f.at(3, .awayEnded) }
            let label = locked ? "locked relaunch" : "relaunch"
            if f.engine.state != .idle { problems.append("\(label): running stretch survived: \(f.engine.state)") }
            guard let record = f.engine.archive.records.first(where: { $0.start == start }) else {
                problems.append("\(label): no record for the running stretch"); continue
            }
            if record.end != quit || !close(record.workSeconds, 1_200) {
                problems.append("\(label): ended \(record.end) with \(record.workSeconds)s; expected \(quit) and 1200s")
            }
        }
        return problems
    }

    /// The Pause button past the cap ends the session where the pause began,
    /// as idle and away pauses already do; below the cap it resumes the same
    /// session, untouched.
    private static func manualPausePastCap() -> [String] {
        var problems: [String] = []
        do {
            let f = Fixture(); defer { f.close() }
            let start = f.time
            f.engine.start(workType: .deepWork, intent: "Coding")
            f.at(1_200, .manualPause)
            let paused = f.time
            f.at(cap + 60, .manualResume)
            if let record = f.engine.archive.records.first(where: { $0.start == start }) {
                if record.end != paused || !close(record.workSeconds, 1_200) {
                    problems.append("long pause ended \(record.end) with \(record.workSeconds)s; expected \(paused) and 1200s")
                }
            } else {
                problems.append("a pause past the cap resumed the old session instead of ending it")
            }
            if f.engine.state == .running, f.engine.sessionStartDate != f.time {
                problems.append("resuming past the cap kept the old stretch open from \(f.engine.sessionStartDate)")
            }
        }
        do {
            // Coming back to a work app instead of pressing Resume.
            let f = Fixture(); defer { f.close() }
            let start = f.time
            f.engine.start(workType: .deepWork, intent: "Coding")
            f.at(1_200, .manualPause)
            let paused = f.time
            f.at(cap + 60, .appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
            if let record = f.engine.archive.records.first(where: { $0.start == start }) {
                if record.end != paused || !close(record.workSeconds, 1_200) {
                    problems.append("work app: long pause ended \(record.end) with \(record.workSeconds)s; expected \(paused) and 1200s")
                }
            } else {
                problems.append("work app: a pause past the cap resumed the old session instead of ending it")
            }
            if f.engine.state != .idle, f.engine.sessionStartDate != f.time {
                problems.append("work app: the old stretch stayed open from \(f.engine.sessionStartDate)")
            }
        }
        do {
            let f = Fixture(); defer { f.close() }
            let start = f.time
            f.engine.start(workType: .deepWork, intent: "Coding")
            f.at(1_200, .manualPause)
            f.at(600, .manualResume)
            if f.engine.state != .running || f.engine.sessionStartDate != start
                || !f.engine.archive.records.isEmpty || !close(f.engine.elapsed, 1_200) {
                problems.append("a short pause did not resume the same session: \(f.engine.state), \(f.engine.elapsed)s")
            }
        }
        return problems
    }

    /// While the question is up, a second absence — quiet, locked, or still
    /// open when the answer comes — that reaches the cap ends the session where
    /// it began. The answer given afterwards is still kept: its break and its
    /// receipt are written, and only then is the stretch after the return
    /// ended. A shorter second absence is still banked and excluded from
    /// whichever stretch the answer continues.
    private static func awaitingSecondAbsence() -> [String] {
        var problems: [String] = []
        for variant in ["quiet", "locked", "open"] {
            let f = Fixture(); defer { f.close() }
            guard f.asked() else { return problems + ["the lock did not raise the question"] }
            f.time.addTimeInterval(300)
            let left = f.time
            switch variant {
            case "locked":
                f.at(0, .awayBegan(trigger: .screenLock))
                f.at(cap + 100, .awayEnded)
            case "quiet":
                f.at(600, .idleObserved(seconds: 600))
                f.at(cap, .idleObserved(seconds: 1))
            default:
                f.at(600, .idleObserved(seconds: 600))
                f.time.addTimeInterval(cap)
            }
            let returned = f.time
            let answered = f.engine.decide(.tookBreak, label: "dinner")
            problems += f.spanning(DateInterval(start: left, end: returned)).map { "\(variant): " + $0 }
            if !answered || f.engine.awayDecisionError != nil {
                problems.append("\(variant): the answer was refused: \(f.engine.awayDecisionError ?? "no error")")
            }
            if !f.engine.archive.records.contains(where: { $0.workType == .breakTime && $0.name == "Dinner" }) {
                problems.append("\(variant): the answered break was not recorded")
            }
            if !f.engine.awayDecisions.contains(where: { $0.decision == .tookBreak && $0.insertedRecord?.name == "Dinner" }) {
                problems.append("\(variant): the answer left no receipt")
            }
            if f.engine.state != .idle {
                problems.append("\(variant): the session outlived the second absence: \(f.engine.state)")
            }
            let focus = f.engine.archive.records.filter { $0.workType.countsAsFocus }
                .reduce(0) { $0 + $1.workSeconds } + (f.engine.state == .idle ? 0 : f.engine.elapsed)
            if !close(focus, 1_500) {
                problems.append("\(variant): kept \(focus)s of focus; expected 1500")
            }
        }
        do {
            let f = Fixture(); defer { f.close() }
            guard f.asked() else { return problems + ["the lock did not raise the question"] }
            let returned = f.time
            f.time.addTimeInterval(300)
            f.at(0, .awayBegan(trigger: .screenLock))
            f.at(600, .awayEnded)
            guard f.engine.decide(.tookBreak), f.engine.sessionStartDate == returned,
                  close(f.engine.elapsed, 300) else {
                return problems + ["a short second absence changed today's answer: \(f.engine.state), \(f.engine.elapsed)s"]
            }
        }
        return problems
    }

    /// A break-app pause is the user present, so the cap does not end it by
    /// itself. A lock, a sleep or input stopping past the cap while it stands
    /// is the user gone, and ends the session where the pause began — not
    /// resumed from the evening when a work app comes up in the morning.
    private static func distractionPausePastCap() -> [String] {
        var problems: [String] = []
        for variant in ["locked", "quiet"] {
            let f = Fixture(); defer { f.close() }
            let start = f.time
            f.engine.start(workType: .deepWork, intent: "Coding")
            f.at(1_200, .appActivated(bundleID: "com.netflix.Netflix", name: "Netflix"))
            f.at(20, .dwellExpired(bundleID: "com.netflix.Netflix"))
            let paused = f.time
            guard case .paused(.distractionApp) = f.engine.state else {
                return problems + ["\(variant): the break app did not pause the session: \(f.engine.state)"]
            }
            if variant == "locked" {
                f.at(600, .awayBegan(trigger: .screenLock))
                f.at(night, .awayEnded)
            } else {
                f.at(cap + 60, .idleObserved(seconds: cap + 60))
            }
            let returned = f.time
            f.at(5, .appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
            problems += f.spanning(DateInterval(start: paused.addingTimeInterval(600), end: returned))
                .map { "\(variant): " + $0 }
            if let record = f.engine.archive.records.first(where: { $0.start == start }) {
                if record.end != paused || !close(record.workSeconds, 1_220) {
                    problems.append("\(variant): ended \(record.end) with \(record.workSeconds)s; expected \(paused) and 1220s")
                }
            } else {
                problems.append("\(variant): no record for the stretch the break app paused")
            }
        }
        do {
            // Control: a short break-app pause still resumes the same session.
            let f = Fixture(); defer { f.close() }
            let start = f.time
            f.engine.start(workType: .deepWork, intent: "Coding")
            f.at(1_200, .appActivated(bundleID: "com.netflix.Netflix", name: "Netflix"))
            f.at(20, .dwellExpired(bundleID: "com.netflix.Netflix"))
            f.at(600, .awayBegan(trigger: .screenLock))
            f.at(600, .awayEnded)
            f.at(5, .appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
            if f.engine.state != .running || f.engine.sessionStartDate != start || !f.engine.archive.records.isEmpty {
                problems.append("a short break-app pause did not resume the same session: \(f.engine.state)")
            }
        }
        return problems
    }

    /// `resolve(away:)` ending past the cap used to leave the session running
    /// when the end could not be saved, the absence already banked and no
    /// Retry offered. It now fails the way every other long-away end does.
    private static func refusedLongAwayEnd() -> [String] {
        let f = Fixture(); defer { f.close() }
        // A committed answer makes the end a journalled checkpoint that the
        // fixture can refuse.
        guard f.asked(workFirst: 600), f.engine.decide(.continueSession) else { return ["setup answer failed"] }
        let successor = f.engine.sessionStartDate
        f.at(600, .awayBegan(trigger: .screenLock))
        let left = f.time
        f.journalFailure = { "Terminal journal unavailable" }
        f.at(cap + 60, .awayEnded)
        guard let result = f.engine.lastLongAwayTransition, case .refused = result.outcome else {
            return ["a refused end left the session \(f.engine.state) with no Retry"]
        }
        guard f.engine.state != .running, f.engine.awayDecisionError != nil,
              f.engine.sessionStartDate == successor, close(f.engine.elapsed, 600),
              !f.engine.archive.records.contains(where: { $0.start == successor }) else {
            return ["a refused end changed the stretch: \(f.engine.state), \(f.engine.elapsed)s"]
        }
        f.journalFailure = nil
        guard f.engine.retryLongAwayTransition(result.request).outcome.applied, f.engine.state == .idle,
              let record = f.engine.archive.records.first(where: { $0.start == successor }),
              record.end == left, close(record.workSeconds, 600) else {
            return ["Retry did not end the stretch where it was left"]
        }
        return []
    }
}
