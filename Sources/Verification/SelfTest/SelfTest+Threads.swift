import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 46

    static func testInputDensityRing() -> [String] {
        var problems: [String] = []
        let density = InputDensity()
        let start = base

        // Far more samples than the ring holds; memory must not grow.
        var keys: UInt32 = 0
        for index in 0..<(FocusConstants.densityRingSize * 10) {
            keys += 8
            density.record(InputSample(at: start.addingTimeInterval(Double(index) * 20),
                                       keys: keys, clicks: 0, scrolls: 0, idleSeconds: 0))
        }
        expect(density.sampleCount == FocusConstants.densityRingSize,
               "the ring is capped at \(FocusConstants.densityRingSize), got "
               + "\(density.sampleCount)", &problems)
        expect(density.activity == .active, "sustained typing is still active", &problems)

        // An absent sample clears the ring: the counters may have advanced from
        // synthetic events while nobody was there, and a delta measured across
        // that gap would be a lie.
        density.record(InputSample(at: start.addingTimeInterval(10_000),
                                   keys: keys + 5_000, clicks: 0, scrolls: 0,
                                   idleSeconds: AppUsageTracker.idleCutoff + 1))
        expect(density.sampleCount == 0, "absence clears the ring, got "
               + "\(density.sampleCount)", &problems)
        expect(density.activity == .absent, "and reports absence", &problems)

        // Coming back, the first sample after the gap cannot claim activity.
        density.record(InputSample(at: start.addingTimeInterval(10_020),
                                   keys: keys + 5_000, clicks: 0, scrolls: 0,
                                   idleSeconds: 0))
        expect(density.activity == .passive,
               "the first sample after a gap is not proof of activity", &problems)

        return problems
    }

    // MARK: - 47

    static func testThreadIdentity() -> [String] {
        var problems: [String] = []

        // A record made the ordinary way gets its own thread.
        let a = SessionRecord(name: "Refactor", workType: .deepWork,
                              start: base, end: base.addingTimeInterval(600),
                              workSeconds: 600)
        let b = SessionRecord(name: "Refactor", workType: .deepWork,
                              start: base, end: base.addingTimeInterval(600),
                              workSeconds: 600)
        expect(a.threadID != b.threadID,
               "two independent records are two threads", &problems)

        let thread = UUID()
        let joined = SessionRecord(name: "Refactor", workType: .deepWork,
                                   start: base, end: base.addingTimeInterval(600),
                                   workSeconds: 600, threadID: thread)
        expect(joined.threadID == thread, "an explicit thread is kept", &problems)

        guard let encoded = try? JSONEncoder().encode(joined),
              let decoded = try? JSONDecoder().decode(SessionRecord.self, from: encoded) else {
            problems.append("a record with a thread must round-trip")
            return problems
        }
        expect(decoded.threadID == thread, "the thread survives a round-trip", &problems)

        // Legacy JSON written before threads existed must still decode, each
        // record becoming its own single-segment thread — the truth about it.
        func legacyBlob() -> Data {
            Data("""
            {"id":"\(UUID().uuidString)","name":"Old","workType":"deepWork",
             "start":0,"end":600,"workSeconds":600}
            """.utf8)
        }
        guard let old = try? JSONDecoder().decode(SessionRecord.self, from: legacyBlob()),
              let otherOld = try? JSONDecoder().decode(SessionRecord.self,
                                                       from: legacyBlob()) else {
            problems.append("legacy JSON without threadID must decode")
            return problems
        }
        expect(old.name == "Old", "legacy fields still decode", &problems)
        expect(old.threadID != otherOld.threadID,
               "each legacy record is its own thread", &problems)

        return problems
    }

    // MARK: - 48

    static func testThreadContinuity() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Refactor")
        let first = engine.activeThreadID
        clock.value = base.addingTimeInterval(600)
        engine.stop()

        guard let firstRecord = engine.archive.records.last else {
            problems.append("the first session must be archived")
            return problems
        }
        expect(firstRecord.threadID == first,
               "the archived record carries the engine's thread", &problems)

        // Continuing reuses the thread.
        clock.value = base.addingTimeInterval(3_600)
        engine.start(workType: .deepWork, intent: "Refactor", threadID: first)
        expect(engine.activeThreadID == first, "continuing adopts the thread", &problems)
        clock.value = base.addingTimeInterval(4_200)
        engine.stop()
        expect(engine.archive.records.last?.threadID == first,
               "the second segment joins the thread", &problems)
        expect(engine.archive.records.count == 2,
               "two segments, two records — the gap is never worked time", &problems)

        // Starting fresh does not.
        clock.value = base.addingTimeInterval(7_200)
        engine.start(workType: .admin, intent: "Email")
        expect(engine.activeThreadID != first,
               "an unrelated session is a new thread", &problems)
        clock.value = base.addingTimeInterval(7_800)
        engine.stop()

        // Restarting mid-session must not lose the link: the thread has to
        // survive the snapshot, not merely live in memory.
        clock.value = base.addingTimeInterval(10_000)
        engine.start(workType: .deepWork, intent: "Refactor", threadID: first)
        guard let blob = try? JSONEncoder().encode(engine.snapshot()),
              let snapshot = try? JSONDecoder().decode(PersistedState.self, from: blob) else {
            problems.append("the snapshot must round-trip")
            return problems
        }
        let restored = SessionEngine(store: engine.store,
                                     archive: engine.archive,
                                     ownBundleID: FocusConstants.bundleIdentifier,
                                     schedulesDwell: false,
                                     now: { clock.value })
        restored.restore(from: snapshot)
        expect(restored.activeThreadID == first,
               "the thread survives a relaunch mid-session", &problems)

        return problems
    }

    // MARK: - 49

    static func testThreadSummaries() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let sessionDir = scratchDirectory(), usageDir = scratchDirectory()
        let archive = SessionArchive(directory: sessionDir, now: { clock.value })
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)
        let thread = UUID()
        // 3 pm on the day, after every session below and within the window
        // to continue them. `base` alone lands at a different hour in each
        // time zone: 9 am in Sydney, 10 pm in UTC, past the window.
        clock.value = today.addingTimeInterval(15 * 3_600)

        // Two segments of one thread, plus an unrelated session between them.
        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: today.addingTimeInterval(9 * 3_600),
                                     end: today.addingTimeInterval(9 * 3_600 + 3_600),
                                     workSeconds: 3_600, threadID: thread))
        archive.append(SessionRecord(name: "Email", workType: .admin,
                                     start: today.addingTimeInterval(11 * 3_600),
                                     end: today.addingTimeInterval(11 * 3_600 + 600),
                                     workSeconds: 600))
        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: today.addingTimeInterval(13 * 3_600),
                                     end: today.addingTimeInterval(13 * 3_600 + 1_800),
                                     workSeconds: 1_800, threadID: thread))

        // A recorded break is not a thread to continue.
        archive.append(SessionRecord(name: "Break", workType: .breakTime,
                                     start: today.addingTimeInterval(12 * 3_600),
                                     end: today.addingTimeInterval(12 * 3_600 + 900),
                                     workSeconds: 900))

        let stats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        let threads = stats.threads(on: base, running: nil)

        expect(threads.count == 2, "two threads today, got \(threads.count)", &problems)
        expect(!threads.contains { $0.workType == .breakTime },
               "a break is never offered to continue", &problems)
        guard let refactor = threads.first(where: { $0.threadID == thread }) else {
            problems.append("the refactor thread must be present")
            return problems
        }
        expect(refactor.segments == 2, "two segments, got \(refactor.segments)", &problems)
        expectClose(refactor.totalWorked, 5_400,
                    "worked time sums across segments", &problems)
        expect(refactor.name == "Refactor", "the thread takes the segment name", &problems)
        expect(!refactor.isRunning, "nothing is running", &problems)

        // Ordered by last end, newest first: refactor ended at 13:30, email 11:10.
        expect(threads.first?.threadID == thread,
               "the most recently touched thread comes first", &problems)

        // The running session is included and marked, the same rule
        // `sessionsToday` already follows — one surface must never disagree
        // with another.
        clock.value = today.addingTimeInterval(15 * 3_600 + 900)
        let live = RunningThread(threadID: thread, name: "Refactor",
                                 workType: .deepWork,
                                 start: today.addingTimeInterval(15 * 3_600),
                                 worked: 900)
        let withRunning = stats.threads(on: base, running: live)
        guard let merged = withRunning.first(where: { $0.threadID == thread }) else {
            problems.append("the running thread must be present")
            return problems
        }
        expect(merged.segments == 3, "the running segment counts, got \(merged.segments)",
               &problems)
        expectClose(merged.totalWorked, 6_300, "and its time counts", &problems)
        expect(merged.isRunning, "and it is marked running", &problems)

        // A running session on a brand-new thread appears as its own thread.
        let fresh = RunningThread(threadID: UUID(), name: "Design", workType: .deepWork,
                                  start: today.addingTimeInterval(16 * 3_600), worked: 300)
        expect(stats.threads(on: base, running: fresh).count == 3,
               "a new running thread is a third thread", &problems)

        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }
}
