import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 9

    static func testCodableRoundTrip() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.sessionName = "Refactor"
        engine.transition(on: .launch)
        clock.advance(300)
        engine.transition(on: .appActivated(bundleID: "com.spotify.client", name: "Spotify"))
        engine.transition(on: .dwellExpired(bundleID: "com.spotify.client"))

        let snapshot = engine.snapshot()
        do {
            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            expect(decoded == snapshot, "decoded snapshot should equal the original", &problems)
            expect(decoded.kind == .paused, "snapshot kind should be paused", &problems)
            expect(decoded.pauseBundleID == "com.spotify.client",
                   "snapshot should carry the distraction bundle id", &problems)

            let restoreClock = TestClock(clock.value)
            let restored = makeEngine(restoreClock)
            restored.restore(from: decoded)
            expect(restored.state == .paused(reason: .distractionApp(bundleID: "com.spotify.client")),
                   "restored state should match, got \(restored.state)", &problems)
            expectClose(restored.elapsed, 300, "restored elapsed", &problems)
        } catch {
            problems.append("round-trip threw: \(error)")
        }
        return problems
    }

    // MARK: - 11

    /// D14 — the launch path. A snapshot written while running, reloaded after a
    /// gap longer than the threshold, must escalate exactly as a live wake would.
    static func testRestoreWithGap() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.sessionName = "Refactor"
        engine.transition(on: .launch)
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        clock.advance(600)
        let snapshot = engine.snapshot()

        // Short gap: absorbed as a micro-break, session continues.
        let shortClock = TestClock(clock.value.addingTimeInterval(120))
        let shortEngine = makeEngine(shortClock)
        var shortDecisions = 0
        shortEngine.onNeedsDecision = { _, _ in shortDecisions += 1 }
        shortEngine.restore(from: snapshot)
        expect(shortEngine.state == .running, "a 2m gap should stay running", &problems)
        expectClose(shortEngine.totalPausedDuration, 120, "gap absorbed", &problems)
        expect(shortDecisions == 0, "a 2m gap should raise no alert", &problems)

        // Long gap: escalates through the same extended-break path.
        let longClock = TestClock(clock.value.addingTimeInterval(1_320))
        let longEngine = makeEngine(longClock)
        var raised: TimeInterval?
        longEngine.onNeedsDecision = { away, _ in raised = away }
        longEngine.restore(from: snapshot)
        if case .awaitingUserDecision(let away, let app) = longEngine.state {
            expectClose(away, 1_320, "restored away", &problems)
            expect(app == "Terminal", "restored lastApp should survive, got \(app)", &problems)
        } else {
            problems.append("a 22m gap should await a decision, got \(longEngine.state)")
        }
        expectClose(raised ?? -1, 1_320, "restored alert away", &problems)
        expect(longEngine.currentAppBundleID == "com.apple.Terminal",
               "restore should repopulate the bundle id", &problems)
        return problems
    }

    // MARK: - 12

    /// D6 — a dwell that fires after focus has moved on must not pause.
    static func testDwellCancellation() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.transition(on: .launch)
        engine.transition(on: .appActivated(bundleID: "com.spotify.client", name: "Spotify"))
        clock.advance(10)
        // Back to work before the 20s dwell elapses.
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        engine.transition(on: .dwellExpired(bundleID: "com.spotify.client"))
        expect(engine.state == .running, "a stale dwell must not pause, got \(engine.state)",
               &problems)

        // Staying put does pause, and a work app resumes immediately.
        engine.transition(on: .appActivated(bundleID: "com.spotify.client", name: "Spotify"))
        engine.transition(on: .dwellExpired(bundleID: "com.spotify.client"))
        expect(engine.state == .paused(reason: .distractionApp(bundleID: "com.spotify.client")),
               "dwelling on a break app should pause, got \(engine.state)", &problems)
        clock.advance(60)
        engine.transition(on: .appActivated(bundleID: "com.apple.finder", name: "Finder"))
        expect(engine.state.isPaused, "a neutral app must not resume (D5)", &problems)
        engine.transition(on: .appActivated(bundleID: "com.apple.Terminal", name: "Terminal"))
        expect(engine.state == .running, "a work app should resume", &problems)
        expectClose(engine.totalPausedDuration, 60, "pause accumulated on exit", &problems)
        return problems
    }

    // MARK: - 13

    static func testPureHelpers() -> [String] {
        var problems: [String] = []

        // D15 title formatting.
        expect(Tokens.duration(0) == "0m", "0s should format as 0m", &problems)
        expect(Tokens.duration(900) == "15m", "900s should format as 15m", &problems)
        expect(Tokens.duration(8_100) == "2h 15m", "8100s should format as 2h 15m",
               &problems)
        expect(Tokens.duration(-5) == "0m", "negative input should format as 0m",
               &problems)
        // A corrupted or hand-edited archive can decode a finite value too large
        // for Int. Formatting it must not trap on every launch.
        for bad in [1e300, .infinity, .nan] {
            expect(Tokens.duration(bad) == "—", "\(bad)s formats as a dash, not a crash", &problems)
            expect(Tokens.clock(bad) == "—", "\(bad)s clock formats as a dash", &problems)
            expect(Tokens.spent(bad) == "—", "\(bad)s spent formats as a dash", &problems)
        }

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()

        // D9 — a missing key must read as 15m, not as a zero-second threshold.
        expectClose(store.breakThreshold, FocusConstants.defaultThreshold,
                    "default threshold", &problems)

        // The archive ring caps at capacity, dropping the oldest entries.
        let clock = TestClock(base.addingTimeInterval(60))
        let dir = scratchDirectory()
        let ring = SessionArchive(directory: dir, now: { clock.value }, capacity: 3)
        let overflow = 5
        for index in 0..<overflow {
            ring.append(SessionRecord(name: "s\(index)", workType: .deepWork,
                                      start: base, end: base.addingTimeInterval(60),
                                      workSeconds: Double(index)))
        }
        expect(ring.records.count == 3,
               "ring should cap at 3, got \(ring.records.count)",
               &problems)
        expect(ring.records.map(\.name) == ["s2", "s3", "s4"],
               "ring should retain the newest entries in order, got \(ring.records.map(\.name))",
               &problems)
        expect(ring.sessionsToday() == 3,
               "all surviving records end on the same day", &problems)
        clock.value = base.addingTimeInterval(86_400 * 5)
        expect(ring.sessionsToday() == 0, "no records end five days later", &problems)
        try? FileManager.default.removeItem(at: dir)

        // A corrupt blob is discarded rather than crashing or wedging the app.
        defaults.set(Data("not json".utf8), forKey: "fc.state")
        expect(store.loadState() == nil, "corrupt state should decode as nil", &problems)
        expect(defaults.data(forKey: "fc.state") == nil,
               "corrupt state should be cleared from defaults", &problems)

        store.removeAll()
        return problems
    }

    static func testScratchDirectoryCleanup() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        expect(FileManager.default.fileExists(atPath: directory.path),
               "scratch directory should exist before cleanup", &problems)
        cleanUp()
        expect(!FileManager.default.fileExists(atPath: directory.path),
               "cleanup should remove every tracked scratch directory", &problems)
        return problems
    }

    static func testEmptiedPreferenceSweep() -> [String] {
        var problems: [String] = []
        let folder = scratchDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ name: String, _ contents: [String: Any]) {
            let data = try? PropertyListSerialization.data(fromPropertyList: contents,
                                                           format: .binary, options: 0)
            try? data?.write(to: folder.appendingPathComponent(name))
        }
        let app = FocusConstants.bundleIdentifier
        let emptied = "\(app).activity-rules.\(UUID().uuidString).plist"
        let holding = "\(app).rule-consumer.\(UUID().uuidString).plist"
        let other = "com.example.other.plist"
        write(emptied, [:]); write(holding, ["key": 1]); write("\(app).plist", [:]); write(other, [:])
        removeEmptiedPreferenceFiles(in: folder)
        let left = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        expect(!left.contains(emptied), "an emptied suite's plist was not removed", &problems)
        expect(left.contains(holding), "a suite that still holds settings was removed", &problems)
        expect(left.contains("\(app).plist"), "the app's own preferences file was removed", &problems)
        expect(left.contains(other), "another app's preferences file was removed", &problems)
        return problems
    }
}
