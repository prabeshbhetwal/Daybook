import Foundation

/// Regression checks for the action boundary shared by Story and Focus. These
/// fixtures use an injected clock and isolated storage, so no real history or
/// running application state can make a continuation appear eligible.
enum ContinuationChecks {
    static let tests: [(String, () -> [String])] = [
        ("Only the latest stretch of a thread can continue", latestStretchOnly),
        ("Continuation compares normalised activities across threads", latestActivityOnly),
        ("Continuation age has inclusive one-hour boundaries", continuationAgeBoundaries),
        ("Active and stale thread actions cannot revive older work", activeAndStaleActions),
        ("Pending absence blocks continuation and midnight preserves recency", pendingAndMidnight),
        ("Starting a different activity creates a new session", differentActivityStartsNewThread)
    ]

    private final class Clock {
        var value = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func advance(_ seconds: TimeInterval) { value.addTimeInterval(seconds) }
    }

    private final class Fixture {
        let clock = Clock()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-continuation-\(UUID().uuidString)")
        let suite = "fc.continuation.\(UUID().uuidString)"
        let defaults: UserDefaults
        let archive: SessionArchive
        let engine: SessionEngine
        let store: SessionStore

        init() {
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Could not create isolated continuation defaults")
            }
            self.defaults = defaults
            let clock = self.clock
            archive = SessionArchive(directory: directory, now: { clock.value })
            engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "fc.continuation.test", schedulesDwell: false,
                                   now: { clock.value })
            store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        }

        func close() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        func record(name: String = "Coding", workType: WorkType = .deepWork,
                    start: Date, end: Date, worked: TimeInterval,
                    threadID: UUID = UUID()) -> SessionRecord {
            let record = SessionRecord(name: name, workType: workType, start: start, end: end,
                                       workSeconds: worked, threadID: threadID)
            archive.append(record)
            return record
        }

        func row(for record: SessionRecord) -> DaySession {
            DaySession(id: record.id, threadID: record.threadID, name: record.name,
                       workType: record.workType, start: record.start, end: record.end,
                       worked: record.workSeconds, stretches: 1,
                       spans: [DateInterval(start: record.start, end: record.end)],
                       isRunning: false)
        }
    }

    private static func latestStretchOnly() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let thread = UUID()
            let a = f.record(start: f.clock.value, end: f.clock.value.addingTimeInterval(3_660),
                             worked: 3_600, threadID: thread)
            f.clock.advance(3_660)
            let aRow = f.row(for: a)
            var problems: [String] = []

            if !f.store.canContinue(aRow) {
                problems.append("the first completed stretch was not initially eligible")
                return problems
            }
            f.store.continueSession(aRow)
            f.clock.advance(60)
            f.store.stop()
            guard let b = f.archive.records.last else {
                return ["continuing the first stretch did not create B"]
            }
            let bRow = f.row(for: b)
            if f.store.canContinue(aRow) {
                problems.append("stale A remained eligible after B was recorded")
            }

            let beforeStaleAction = f.archive.records
            f.store.continueSession(aRow)
            if f.engine.state != .idle || f.archive.records != beforeStaleAction {
                problems.append("continuing stale A started or changed the session")
            }
            f.engine.discard()
            f.store.continueSession(aRow)
            if f.engine.state != .idle || f.archive.records != beforeStaleAction {
                problems.append("a repeated stale continuation callback started work")
            }
            f.engine.discard()

            f.store.continueSession(bRow)
            f.clock.advance(30)
            f.store.stop()
            guard let c = f.archive.records.last else { return problems + ["continuing B did not create C"] }
            let cRow = f.row(for: c)
            if f.store.canContinue(aRow) || f.store.canContinue(bRow) || !f.store.canContinue(cRow) {
                problems.append("only the newest completed stretch was not the sole continuation")
            }
            let worked = f.archive.records.reduce(0) { $0 + $1.workSeconds }
            if abs(worked - 3_690) > 0.01 || f.archive.records.count != 3 {
                problems.append("continuation changed session count or worked totals")
            }
            f.store.continueSession(cRow)
            f.clock.advance(30)
            f.store.stop()
            guard let d = f.archive.records.last else { return problems + ["continuing latest C did not create D"] }
            let dRow = f.row(for: d)
            if f.store.canContinue(cRow) || !f.store.canContinue(dRow)
                || abs(f.archive.records.reduce(0) { $0 + $1.workSeconds } - 3_720) > 0.01 {
                problems.append("the latest stretch could not continue repeatedly without gap credit")
            }
            f.clock.advance(3_570)
            if !f.store.canContinue(dRow) {
                problems.append("a 3,600-second-old stretch was rejected")
            }
            f.clock.advance(31)
            if f.store.canContinue(dRow) {
                problems.append("a 3,601-second-old stretch remained eligible")
            }
            return problems
        }
    }

    private static func latestActivityOnly() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let now = f.clock.value
            let first = f.record(name: "Coding", start: now.addingTimeInterval(-300),
                                 end: now.addingTimeInterval(-240), worked: 60)
            let second = f.record(name: "  coding  ", start: now.addingTimeInterval(-180),
                                  end: now.addingTimeInterval(-120), worked: 60)
            let third = f.record(name: "CODING", start: now.addingTimeInterval(-90),
                                 end: now.addingTimeInterval(-60), worked: 30)
            let browsing = f.record(name: "Browsing", start: now.addingTimeInterval(-80),
                                   end: now.addingTimeInterval(-20), worked: 60)
            var problems: [String] = []
            if f.store.canContinue(f.row(for: first)) || f.store.canContinue(f.row(for: second)) {
                problems.append("older normalised Coding threads remained eligible")
            }
            if !f.store.canContinue(f.row(for: third)) || !f.store.canContinue(f.row(for: browsing)) {
                problems.append("latest independent Coding or Browsing activity was rejected")
            }
            return problems
        }
    }

    private static func continuationAgeBoundaries() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let now = f.clock.value
            let fresh = f.record(name: "At 3599", start: now.addingTimeInterval(-3_659),
                                 end: now.addingTimeInterval(-3_599), worked: 60)
            let edge = f.record(name: "At 3600", start: now.addingTimeInterval(-3_660),
                                end: now.addingTimeInterval(-3_600), worked: 60)
            let expired = f.record(name: "At 3601", start: now.addingTimeInterval(-3_661),
                                   end: now.addingTimeInterval(-3_601), worked: 60)
            let future = f.record(name: "Future", start: now.addingTimeInterval(1),
                                  end: now.addingTimeInterval(60), worked: 59)
            var problems: [String] = []
            if !f.store.canContinue(f.row(for: fresh)) || !f.store.canContinue(f.row(for: edge)) {
                problems.append("3,599 or 3,600 second continuation boundary was rejected")
            }
            if f.store.canContinue(f.row(for: expired)) || f.store.canContinue(f.row(for: future)) {
                problems.append("expired or future-ended work remained eligible")
            }
            return problems
        }
    }

    private static func activeAndStaleActions() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let old = f.record(start: f.clock.value.addingTimeInterval(-120),
                               end: f.clock.value.addingTimeInterval(-60), worked: 60)
            let oldRow = f.row(for: old)
            f.engine.start(workType: .deepWork, intent: " coding ", threadID: UUID())
            var problems: [String] = []
            if f.store.canContinue(oldRow) {
                problems.append("an active same activity did not block an older stretch")
            }
            f.store.togglePause()
            if f.store.canContinue(oldRow) {
                problems.append("a paused same activity did not retain continuation ownership")
            }
            f.engine.discard()

            let staleThread = ThreadSummary(threadID: old.threadID, name: old.name,
                                            workType: old.workType, totalWorked: old.workSeconds,
                                            segments: 1, firstStart: old.start, lastEnd: old.end,
                                            isRunning: false)
            let newer = f.record(start: f.clock.value.addingTimeInterval(-30), end: f.clock.value,
                                 worked: 30, threadID: UUID())
            let before = f.archive.records
            f.store.continueThread(staleThread)
            if f.engine.state != .idle || f.archive.records != before ||
                !f.store.canContinue(f.row(for: newer)) {
                problems.append("a stale Focus continuation row crossed the action boundary")
            }
            f.engine.discard()
            return problems
        }
    }

    private static func pendingAndMidnight() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: f.clock.value)
            f.clock.value = midnight.addingTimeInterval(20)
            let overnight = f.record(name: "Night coding",
                                     start: midnight.addingTimeInterval(-40), end: midnight,
                                     worked: 40)
            var problems: [String] = []
            if !f.store.canContinue(f.row(for: overnight)) {
                problems.append("a latest stretch crossing midnight was rejected")
            }

            f.engine.start(workType: .deepWork, intent: "Other task")
            f.clock.advance(600)
            f.engine.transition(on: .awayBegan(trigger: .screenLock))
            f.clock.advance(1_200)
            f.engine.transition(on: .awayEnded)
            if !f.store.hasUnresolvedAwayDecision || f.store.canContinue(f.row(for: overnight)) {
                problems.append("a pending absence did not block continuation at the action boundary")
            }
            return problems
        }
    }

    private static func differentActivityStartsNewThread() -> [String] {
        MainActor.assumeIsolated {
            let f = Fixture(); defer { f.close() }
            let codingThread = UUID()
            f.engine.start(workType: .deepWork, intent: "Coding", threadID: codingThread)
            f.clock.advance(60)
            f.store.intent = "Browsing"
            f.store.workType = .deepWork
            f.store.start()
            let isNew = f.engine.activeThreadID != codingThread && f.engine.sessionName == "Browsing"
            f.clock.advance(60)
            f.store.stop()
            return isNew && Set(f.archive.records.map(\.threadID)).count == 2
                ? [] : ["starting Browsing adopted the active Coding thread by work type alone"]
        }
    }
}
