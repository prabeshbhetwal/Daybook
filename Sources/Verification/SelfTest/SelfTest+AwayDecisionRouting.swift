import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Presentation hiding is not an action boundary. A global shortcut or any
    /// future caller can still reach the store directly, so an unresolved Away
    /// decision must reject ordinary stop/start/pause mutations at that shared
    /// App seam while leaving the exact pending evidence intact.
    static func testAwayDecisionRejectsOrdinarySessionMutations() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Pending evidence")
        clock.advance(20 * 60)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(20 * 60)
        engine.transition(on: .awayEnded)
        guard case .awaitingUserDecision(let pendingBefore, _) = engine.state else {
            return ["fixture did not reach awaitingUserDecision: \(engine.state)"]
        }
        let recordsBefore = engine.archive.records
        let store = SessionStore(engine: engine, now: { clock.value })

        store.stop()
        store.togglePause()
        store.startQuick(QuickStart(id: "blocked", name: "Blocked", workType: .admin))

        if case .awaitingUserDecision(let pendingAfter, _) = engine.state {
            expectClose(pendingAfter, pendingBefore,
                        "ordinary actions preserve the pending Away interval", &problems)
        } else {
            problems.append("ordinary actions changed unresolved evidence to \(engine.state)")
        }
        expect(engine.archive.records == recordsBefore,
               "rejected ordinary actions archive no partial session", &problems)
        return problems
    }

    /// The hotkey has three literal outcomes. Pending evidence is not a fourth
    /// kind of stop: it routes back to the existing answer surface and leaves
    /// state untouched. Idle and ordinary live states retain zero-friction
    /// start/stop behaviour through the same store boundary.
    static func testHotKeyRoutesPendingAwayDecision() -> [String] {
        var problems: [String] = []

        let idleClock = TestClock(base)
        let idleEngine = makeEngine(idleClock)
        let idleStore = SessionStore(engine: idleEngine, now: { idleClock.value })
        expect(idleStore.performSessionHotKeyAction() == .started,
               "idle hotkey starts through the shared boundary", &problems)
        expect(idleEngine.state == .running,
               "idle hotkey leaves a running session", &problems)
        expect(idleStore.performSessionHotKeyAction() == .stopped,
               "ordinary live hotkey stops through the shared boundary", &problems)
        expect(idleEngine.state == .idle,
               "ordinary live hotkey leaves an idle session", &problems)

        let pendingClock = TestClock(base)
        let pendingEngine = makeEngine(pendingClock)
        pendingEngine.start(workType: .learning, intent: "Pending")
        pendingClock.advance(20 * 60)
        pendingEngine.transition(on: .awayBegan(trigger: .systemSleep))
        pendingClock.advance(20 * 60)
        pendingEngine.transition(on: .awayEnded)
        let pendingStore = SessionStore(engine: pendingEngine, now: { pendingClock.value })
        let recordsBefore = pendingEngine.archive.records

        expect(pendingStore.performSessionHotKeyAction() == .showAwayDecision,
               "pending hotkey routes to the existing Away decision", &problems)
        expect(pendingStore.hasUnresolvedAwayDecision,
               "pending hotkey keeps the decision outstanding", &problems)
        expect(pendingEngine.archive.records == recordsBefore,
               "pending hotkey writes no replacement evidence", &problems)
        return problems
    }

    /// The setting is retained only because it controls a real production list:
    /// the selected app's recent grouped sessions in Today. The rows are newest
    /// first and the configured limit is applied after canonical grouping.
    static func testSessionsPerAppLimitsProductionAppHistory() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: anchoredNow())
        let clock = TestClock(day.addingTimeInterval(12 * 3_600))
        let app = "org.example.editor"
        let usageSessions = (0..<5).map { index -> AppUsageSession in
            let start = day.addingTimeInterval(9 * 3_600 + Double(index * 10 * 60))
            return AppUsageSession(bundleID: app, appName: "Editor",
                                   start: start, end: start.addingTimeInterval(60))
        }
        let usage = makeUsageArchive(clock, sessions: usageSessions, accurateFrom: day)
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        persistence.menuSessionCount = 3
        let engine = SessionEngine(
            store: persistence, archive: makeArchive(clock),
            ownBundleID: "com.example.self", schedulesDwell: false,
            now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)

        let visible = store.sessions(for: app)
        expect(visible.count == 3,
               "configured Today app-session list shows three rows, got \(visible.count)",
               &problems)
        expect(visible.map(\.start) == usageSessions.suffix(3).reversed().map(\.start),
               "the configured list retains the newest grouped app sessions", &problems)
        return problems
    }

    /// A focus session is a thread, not every archived stretch. An app switch is
    /// a change between adjacent app identities inside one focus stretch, not the
    /// first app observed and not a same-app checkpoint split.
    static func testFocusQualityCountsThreadsAndTransitions() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        let clock = TestClock(day.addingTimeInterval(12 * 3_600))
        let sharedThread = UUID()
        let secondThread = UUID()
        let records = [
            SessionRecord(name: "One", workType: .deepWork,
                          start: day.addingTimeInterval(9 * 3_600),
                          end: day.addingTimeInterval(9.5 * 3_600),
                          workSeconds: 30 * 60, threadID: sharedThread),
            SessionRecord(name: "One", workType: .deepWork,
                          start: day.addingTimeInterval(10 * 3_600),
                          end: day.addingTimeInterval(10.5 * 3_600),
                          workSeconds: 30 * 60, threadID: sharedThread),
            SessionRecord(name: "Two", workType: .admin,
                          start: day.addingTimeInterval(11 * 3_600),
                          end: day.addingTimeInterval(11.5 * 3_600),
                          workSeconds: 30 * 60, threadID: secondThread)
        ]
        func use(_ bundleID: String, _ startMinute: Int, _ endMinute: Int)
            -> AppUsageSession {
            AppUsageSession(bundleID: bundleID, appName: bundleID,
                            start: day.addingTimeInterval(Double(startMinute * 60)),
                            end: day.addingTimeInterval(Double(endMinute * 60)))
        }
        let usage = makeUsageArchive(clock, sessions: [
            use("app.a", 9 * 60, 9 * 60 + 10),
            use("app.a", 9 * 60 + 10, 9 * 60 + 15),
            use("app.b", 9 * 60 + 15, 9 * 60 + 30),
            use("app.b", 10 * 60, 10 * 60 + 10),
            use("app.b", 10 * 60 + 10, 10 * 60 + 20),
            use("app.c", 10 * 60 + 20, 10 * 60 + 30),
            use("app.c", 11 * 60, 11 * 60 + 15),
            use("app.a", 11 * 60 + 15, 11 * 60 + 30)
        ], accurateFrom: day)
        let archive = makeArchive(clock, records: records, calendar: calendar)
        let quality = DashboardStats(sessions: archive, usage: usage,
                                     calendar: calendar, now: { clock.value })
            .focusQuality(for: day)

        expect(quality.sessionCount == 2,
               "three stretches across two thread IDs count as two sessions; got "
                   + "\(quality.sessionCount)", &problems)
        expectClose(quality.switchesPerSession, 1.5,
                    "three real app transitions over two thread sessions", &problems)
        return problems
    }
}
