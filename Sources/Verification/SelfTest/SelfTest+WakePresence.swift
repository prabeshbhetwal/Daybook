import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Waiting is an observation state, not a stopped tracker: the ticker must
    /// keep sampling until real presence is known. Suspension and disabling are
    /// terminal for that candidate, so an old confirmation cannot reopen it.
    static func testUsageWaitingStateLifecycle() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let tracker = AppUsageTracker(archive: AppUsageArchive(directory: directory,
                                                                 now: { clock.value }),
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled, now: { clock.value })

        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        expect(tracker.isObserving,
               "waiting for presence must keep the ticker observing", &problems)
        tracker.suspend()
        expect(!tracker.isObserving,
               "suspending a waiting tracker must stop observation", &problems)
        tracker.confirmPresence(at: clock.value)
        expect(tracker.currentBundleID == nil && !tracker.isObserving,
               "a stale confirmation after suspend must not reopen tracking", &problems)

        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        expect(tracker.isObserving,
               "a second waiting candidate must also keep the ticker alive", &problems)
        tracker.setEnabled(false)
        expect(!tracker.isObserving,
               "disabling a waiting tracker must stop observation", &problems)
        tracker.setEnabled(true)
        tracker.confirmPresence(at: clock.value)
        expect(tracker.currentBundleID == nil && !tracker.isObserving,
               "a stale confirmation after disable must not reopen tracking", &problems)
        return problems
    }

    /// A wake resets macOS's HID idle counter even when nobody touched the
    /// machine. The reset itself and its increasing tail must stay quiet; only
    /// an unlock or a second, downward reset is evidence of a person.
    static func testWakePresenceGate() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        var gate = PresenceGate()
        gate.confirm(at: clock.value)

        clock.advance(600)
        gate.noteMachineWake()
        for raw in [0.5, 1.5, 2.5] {
            let observation = gate.observe(rawIdleSeconds: raw,
                                           at: clock.value,
                                           displayAwake: true,
                                           screenLocked: false)
            if case .quiet(let seconds) = observation {
                expect(seconds >= 600,
                       "an increasing post-wake counter stays quiet, got \(seconds)s",
                       &problems)
            } else {
                problems.append("an increasing post-wake counter must not confirm presence")
            }
            clock.advance(1)
        }

        let resetAt = clock.value
        let reset = gate.observe(rawIdleSeconds: 0.25,
                                 at: resetAt,
                                 displayAwake: true,
                                 screenLocked: false)
        if case .active(let since) = reset {
            expectClose(since.timeIntervalSince(resetAt), -0.25,
                        "a downward reset confirms from the last input", &problems)
        } else {
            problems.append("a later downward reset should confirm presence")
        }

        var unlockGate = PresenceGate()
        unlockGate.noteMachineWake()
        clock.advance(60)
        let unlockedAt = clock.value
        unlockGate.confirm(at: unlockedAt)
        clock.advance(1)
        let afterUnlock = unlockGate.observe(rawIdleSeconds: 1,
                                             at: clock.value,
                                             displayAwake: true,
                                             screenLocked: false)
        if case .active(let since) = afterUnlock {
            expectClose(since.timeIntervalSince(unlockedAt), 0,
                        "unlock confirms presence immediately", &problems)
        } else {
            problems.append("an explicit unlock should clear wake suppression")
        }
        return problems
    }

    /// Preparing the frontmost app after wake is deliberately non-recording.
    /// The first real HID reset confirms the candidate and starts a new UUID at
    /// that confirmed return, never at the machine wake.
    static func testWakeDoesNotCreateUsage() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })
        var gate = PresenceGate()

        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        gate.noteMachineWake()
        for raw in [0.25, 1.25, 2.25] {
            clock.advance(1)
            if case .quiet(let seconds) = gate.observe(rawIdleSeconds: raw,
                                                       at: clock.value,
                                                       displayAwake: true,
                                                       screenLocked: false) {
                tracker.observeIdle(seconds: seconds)
            } else {
                problems.append("machine-wake idle must remain non-recording")
            }
        }
        tracker.flush()
        expect(usage.sessions.isEmpty && tracker.currentBundleID == nil,
               "a prepared wake candidate must record nothing before confirmation",
               &problems)

        clock.advance(1)
        let confirmedAt = clock.value.addingTimeInterval(-0.1)
        let presence = gate.observe(rawIdleSeconds: 0.1,
                                    at: clock.value,
                                    displayAwake: true,
                                    screenLocked: false)
        if case .active(let since) = presence {
            tracker.confirmPresence(at: since)
            expectClose(since.timeIntervalSince(confirmedAt), 0,
                        "the return is the genuine idle reset", &problems)
        } else {
            problems.append("genuine post-wake input should confirm the candidate")
        }
        clock.advance(60)
        tracker.flush()

        expect(usage.sessions.count == 1,
               "confirmation starts exactly one app-usage UUID", &problems)
        expectClose(usage.sessions.first?.start.timeIntervalSince(confirmedAt) ?? -1, 0,
                    "usage starts at confirmed presence", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 60.1,
                    "only post-confirmation usage is recorded", &problems)
        return problems
    }

    /// A real input reset can already be several seconds old by the next tick.
    /// `.active` is categorical proof of return, so its age must not be sent to
    /// the engine as if it were still merely quiet.
    static func testAgedWakeResetEndsAbsence() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine)
        store.attach(tracker: tracker, usage: usage)
        var gate = PresenceGate()

        engine.transition(on: .launch)
        tracker.prepareToResume(bundleID: "com.example.editor", name: "Editor")
        gate.confirm(at: clock.value)
        clock.advance(60)
        engine.transition(on: .awayBegan(trigger: .systemSleep))
        gate.noteMachineWake()

        clock.advance(20)
        let wakeReset = gate.observe(rawIdleSeconds: 20,
                                     at: clock.value,
                                     displayAwake: true,
                                     screenLocked: false)
        engine.transition(on: .idleObserved(
            seconds: store.applyPresenceObservation(wakeReset)))
        expectClose(engine.totalPausedDuration, 0,
                    "the machine reset alone must leave the absence open", &problems)

        clock.advance(10)
        let humanReset = gate.observe(rawIdleSeconds: 10,
                                      at: clock.value,
                                      displayAwake: true,
                                      screenLocked: false)
        if case .active(let since) = humanReset {
            expectClose(since.timeIntervalSince(clock.value), -10,
                        "the confirmed return retains its honest input date", &problems)
        } else {
            problems.append("the aged downward reset should be confirmed active")
        }
        engine.transition(on: .idleObserved(
            seconds: store.applyPresenceObservation(humanReset)))
        expectClose(engine.totalPausedDuration, 30,
                    "confirmed active must resolve the full engine absence", &problems)
        expect(tracker.currentBundleID == "com.example.editor",
               "the same confirmation must activate the waiting tracker", &problems)
        tracker.flush()
        expectClose(usage.sessions.first?.start.timeIntervalSince(clock.value) ?? -1, -10,
                    "the tracker retains the gate's aged input date", &problems)
        return problems
    }
}
