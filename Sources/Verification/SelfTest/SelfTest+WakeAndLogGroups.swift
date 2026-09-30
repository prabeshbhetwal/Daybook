import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 99

    /// A question is pending; the user walks off for forty minutes without
    /// locking anything. That quiet is banked as a second absence, so neither
    /// "I was working" nor "It was a break" can hand it to a session.
    static func testQuietWhileAwaiting() -> [String] {
        var problems: [String] = []
        func scenario(_ decision: UserDecision) -> SessionEngine {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = 4 * 3_600
            prefs.breakThreshold = 5 * 60
            let clock = TestClock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Pending test")
            clock.advance(20 * 60)
            engine.transition(on: .awayBegan(trigger: .screenLock))   // T+20
            clock.advance(10 * 60)
            engine.transition(on: .awayEnded)                          // T+30: asked about 10m
            guard case .awaitingUserDecision = engine.state else {
                problems.append("the ten minutes are asked about, got \(engine.state)"); return engine
            }
            clock.advance(2 * 60)                                      // T+32: two ordinary minutes
            clock.advance(10 * 60)                                     // T+42: ten quiet minutes
            engine.transition(on: .idleObserved(seconds: 600))         // opens the second absence at T+32
            clock.advance(30 * 60)                                     // T+72: still gone
            engine.transition(on: .idleObserved(seconds: 40 * 60))
            engine.transition(on: .idleObserved(seconds: 1))           // T+72: back; 40m banked
            clock.advance(60)                                          // T+73: answers
            engine.transition(on: .decision(decision))
            return engine
        }
        let merged = scenario(.mergeTime)
        expectClose(merged.elapsed, 33 * 60,
                    "I was working: 20 + the 10 merged + 3 ordinary, never the 40 quiet, got \(Int(merged.elapsed / 60))m",
                    &problems)
        let broke = scenario(.tookBreak)
        expectClose(broke.elapsed, 3 * 60,
                    "It was a break: the new stretch holds 3 ordinary minutes, not 43, got \(Int(broke.elapsed / 60))m",
                    &problems)
        return problems
    }

    // MARK: - 100

    /// An app's self-declared App Store category names its purpose only when
    /// neither a rule nor an override speaks — and automatic sessions carry a
    /// name from what the user is doing, "Browsing" in anything ambiguous.
    static func testCategoryFallbackAndNames() -> [String] {
        var problems: [String] = []
        // The pure mapping.
        expect(PurposeMap.categoryFallback("public.app-category.developer-tools") == .coding,
               "developer-tools reads as coding", &problems)
        expect(PurposeMap.categoryFallback("public.app-category.social-networking") == .communication,
               "social-networking reads as communication", &problems)
        expect(PurposeMap.categoryFallback("public.app-category.music") == .media,
               "music reads as media", &problems)
        expect(PurposeMap.categoryFallback("public.app-category.lifestyle") == nil
                   && PurposeMap.categoryFallback(nil) == nil,
               "a category with nothing to say stays silent", &problems)

        // Precedence, with the injected lookup saved and restored: it is
        // process-global and the other tests assume the default.
        let saved = PurposeMap.declaredCategory
        defer { PurposeMap.declaredCategory = saved }
        PurposeMap.declaredCategory = { bundleID in
            switch bundleID {
            case "com.example.unmapped-ide": return "public.app-category.developer-tools"
            case "com.apple.dt.Xcode": return "public.app-category.music"   // a lie a rule outranks
            default: return nil
            }
        }
        expect(PurposeMap.purpose(for: "com.example.unmapped-ide", activity: .active) == .coding,
               "an unmapped app is read from its declared category", &problems)
        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .active) == .coding,
               "a rule outranks the declared category", &problems)
        expect(PurposeMap.purpose(for: "com.example.mystery", activity: .active) == .utility,
               "unmapped and unlabelled stays a utility", &problems)
        expect(PurposeMap.purpose(for: "com.example.unmapped-ide", activity: .active,
                                  overrides: ["com.example.unmapped-ide": "media"]) == .media,
               "the user's override outranks everything", &problems)

        // Names.
        expect(AutoSessionDetector.sessionName(forApp: "company.thebrowser.dia", purpose: .writingAI)
                   == "Browsing",
               "an ambiguous app names the act, not the tool", &problems)
        expect(AutoSessionDetector.sessionName(forApp: "com.apple.dt.Xcode", purpose: .coding)
                   == "Coding", "coding names itself", &problems)
        expect(AutoSessionDetector.sessionName(forApp: "com.example.mystery", purpose: .utility)
                   == "", "a utility has no name to give", &problems)
        return problems
    }

    // MARK: - 101

    /// The lid closes; the machine dark-wakes all evening. No wake event ends
    /// the absence any more — only confirmed input does — so the whole of it
    /// is measured from the lid close: past the cap the session ends there,
    /// and a late idle pause cannot shorten what is asked.
    static func testWakeIsNotAReturn() -> [String] {
        var problems: [String] = []
        func make(capHours: Double) -> (engine: SessionEngine, archive: SessionArchive, clock: TestClock) {
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let prefs = PersistenceStore(defaults: defaults)
            prefs.removeAll()
            prefs.longAwayCap = capHours * 3_600
            prefs.breakThreshold = 5 * 60
            let clock = TestClock(base)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: prefs, archive: archive, ownBundleID: "com.test",
                                       schedulesDwell: false, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Lid test")
            clock.advance(20 * 60)
            engine.transition(on: .awayBegan(trigger: .systemSleep))    // T+20: lid closes
            return (engine, archive, clock)
        }

        // Six hours of dark wakes, the ticker frozen throughout; the first
        // confirmed input resolves the whole absence and ends the session
        // where the lid closed.
        let capped = make(capHours: 1)
        capped.clock.advance(6 * 3_600)
        capped.engine.transition(on: .idleObserved(seconds: 2))          // real input
        expect(capped.engine.state == .idle, "past the cap the session is over, got \(capped.engine.state)",
               &problems)
        let record = capped.archive.records.last
        expectClose(record?.end.timeIntervalSince(base) ?? 0, 20 * 60,
                    "the record ends where the lid closed", &problems)
        expectClose(record?.workSeconds ?? 0, 20 * 60, "and carries only the work before it", &problems)

        // The same evening under a large cap: the question is about all six
        // hours, not the sliver since the last wake.
        let asked = make(capHours: 8)
        asked.clock.advance(6 * 3_600)
        asked.engine.transition(on: .idleObserved(seconds: 2))
        if case .awaitingUserDecision(let away, _) = asked.engine.state {
            expectClose(away, 6 * 3_600, "the whole absence is asked about, got \(Int(away / 60))m", &problems)
        } else {
            problems.append("below the cap the absence is asked about, got \(asked.engine.state)")
        }

        // A ticker that survived long enough to raise a late idle pause must
        // not shorten the measure: the pause folds back to the lid close.
        let folded = make(capHours: 1)
        folded.clock.advance(2 * 3_600)
        folded.engine.transition(on: .idleObserved(seconds: 7_200))      // pause back-dated to T+20
        expect(folded.engine.state.isPaused, "quiet pauses the session", &problems)
        folded.clock.advance(4 * 3_600)
        folded.engine.transition(on: .idleObserved(seconds: 2))          // real input, six hours on
        expect(folded.engine.state == .idle,
               "the folded absence outgrew the cap, got \(folded.engine.state)", &problems)
        expectClose(folded.archive.records.last?.end.timeIntervalSince(base) ?? 0, 20 * 60,
                    "ended where the lid closed, not at the late pause", &problems)
        return problems
    }

    // MARK: - 60

    static func testLogAppGroups() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        func entry(_ bundleID: String, _ name: String,
                   startMinute: Double, minutes: Double, visits: Int = 1) -> LogEntry {
            let start = day.addingTimeInterval(startMinute * 60)
            return LogEntry(session: AppSession(bundleID: bundleID, appName: name,
                                                start: start,
                                                end: start.addingTimeInterval(minutes * 60),
                                                attended: minutes * 60,
                                                visits: visits),
                            day: day)
        }
        // The shape from the real screenshot: one app scattered across the day.
        let entries = [
            entry("com.anthropic.claudefordesktop", "Claude", startMinute: 700, minutes: 5),
            entry("company.thebrowser.dia", "Dia", startMinute: 690, minutes: 1),
            entry("com.anthropic.claudefordesktop", "Claude", startMinute: 600, minutes: 13,
                  visits: 2),
            entry("com.anthropic.claudefordesktop", "Claude", startMinute: 500, minutes: 11,
                  visits: 6),
            entry("net.whatsapp.WhatsApp", "WhatsApp", startMinute: 400, minutes: 3)
        ]
        let groups = PeriodStats.appGroups(from: entries)

        expect(groups.count == 3, "three apps from five sessions, got \(groups.count)", &problems)
        expect(groups.first?.appName == "Claude", "largest first", &problems)
        expectClose(groups.first?.total ?? 0, 29 * 60,
                    "an app's total is the sum of its sessions", &problems)
        expect(groups.first?.sessions.count == 3,
               "and it keeps every one of them for the expanded view", &problems)
        expect(groups.first?.visits == 9, "visits add up across sessions", &problems)
        expectClose(groups.map(\.share).reduce(0, +), 1.0,
                    "shares cover the whole period exactly once", &problems)
        expect(groups.map(\.total) == groups.map(\.total).sorted(by: >),
               "rows are ordered by time spent", &problems)

        // Order must not shuffle between refreshes when two apps tie.
        let tied = [entry("com.b", "Beta", startMinute: 10, minutes: 5),
                    entry("com.a", "Alpha", startMinute: 20, minutes: 5)]
        expect(PeriodStats.appGroups(from: tied).map(\.appName) == ["Alpha", "Beta"],
               "ties break on name, so the order is stable", &problems)

        expect(PeriodStats.appGroups(from: []).isEmpty,
               "no sessions, no rows", &problems)

        // The expanded panel's figures.
        guard let claude = groups.first else { return problems }
        expectClose(claude.longest, 13 * 60, "longest is the biggest session", &problems)

        // Its own chart across a period, including days it was never used —
        // a gap has to look like a gap, not be skipped.
        let calendar = Calendar.current
        guard let weekStart = calendar.date(byAdding: .day, value: -3, to: day),
              let weekEnd = calendar.date(byAdding: .day, value: 2, to: day) else {
            return problems
        }
        let daily = claude.dailyTotals(from: weekStart, to: weekEnd)
        expect(daily.count == 6, "one entry per calendar day, got \(daily.count)", &problems)
        expect(daily.filter { $0.seconds > 0 }.count == 1,
               "only the day it was used carries time", &problems)
        expectClose(daily.first(where: { $0.seconds > 0 })?.seconds ?? 0, 29 * 60,
                    "and that day carries all of it", &problems)
        expect(daily.map(\.day) == daily.map(\.day).sorted(),
               "days run oldest first", &problems)

        return problems
    }
}
