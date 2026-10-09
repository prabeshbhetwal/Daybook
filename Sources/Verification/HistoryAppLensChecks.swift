import Foundation

/// Picking an app in History: a session is listed only when the app was in
/// front inside it, and the app's figures add up to its whole record.
enum HistoryAppLensChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An app's History lists only the sessions it was in front in, with its time outside sessions apart",
         lensFigures),
        ("Picking or typing an app finds the sessions that used it, not every session on its day", searchBySession),
        ("An app's time in a session crossing midnight is its start day's; ten seconds in front is enough",
         lensEdges),
        ("An app used in the session still running counts as used in a session", runningSession)
    ]

    /// Monday 31 August 2026. Session A runs 9–10 am and uses Qwen for three
    /// minutes beside Dia; session B runs 2–3 pm and flickers past Qwen for
    /// five seconds. Qwen is also open 1:00–1:02 pm and 11:58 pm–12:03 am,
    /// outside every session.
    private struct Story {
        let calendar = Calendar.current
        let day = SelfTest.gregorian.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let threadA = UUID()
        let threadB = UUID()

        func at(_ hour: Int, _ minute: Int, _ second: Int = 0, dayOffset: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: dayOffset, to: day)!
            return calendar.date(bySettingHour: hour, minute: minute, second: second, of: base)!
        }

        var records: [SessionRecord] {
            [SessionRecord(name: "Parser", workType: .deepWork, start: at(9, 0), end: at(10, 0),
                           workSeconds: 3_600, threadID: threadA),
             SessionRecord(name: "Review", workType: .deepWork, start: at(14, 0), end: at(15, 0),
                           workSeconds: 3_600, threadID: threadB)]
        }

        var usage: [AppUsageSession] {
            [AppUsageSession(bundleID: "dia", appName: "Dia", start: at(9, 0), end: at(9, 20)),
             AppUsageSession(bundleID: "qwen", appName: "Qwen", start: at(9, 20), end: at(9, 23)),
             AppUsageSession(bundleID: "qwen", appName: "Qwen", start: at(13, 0), end: at(13, 2)),
             AppUsageSession(bundleID: "qwen", appName: "Qwen", start: at(14, 30), end: at(14, 30, 5)),
             AppUsageSession(bundleID: "dia", appName: "Dia", start: at(14, 30, 5), end: at(14, 50)),
             AppUsageSession(bundleID: "qwen", appName: "Qwen", start: at(23, 58),
                             end: at(0, 3, dayOffset: 1))]
        }
    }

    private static func lensFigures() -> [String] {
        var problems: [String] = []
        let story = Story()
        let lens = HistoryAppLens.build(bundleID: "qwen", records: story.records,
                                        usage: SortedUsage(story.usage), calendar: story.calendar)
        expect(lens.sessions.map(\.threadID) == [story.threadA],
               "only session A used Qwen past a flicker, got \(lens.sessions.count) sessions", &problems)
        SelfTest.expectClose(lens.sessions.first?.seconds ?? -1, 180, "Qwen's time in session A", &problems)
        // The flicker still happened inside a session: it is not outside use.
        SelfTest.expectClose(lens.inSession, 185, "Qwen's time inside sessions", &problems)
        SelfTest.expectClose(lens.outsideTotal, 420, "Qwen's time outside sessions", &problems)
        expect(lens.days.map(\.day) == [story.day, story.at(0, 0, dayOffset: 1)],
               "Qwen was used on the 31st and, past midnight, the 1st; got \(lens.days.map(\.day))", &problems)
        expect(lens.outside.map(\.span.start) == [story.at(0, 0, dayOffset: 1), story.at(23, 58), story.at(13, 0)],
               "three outside sittings, split at midnight, newest first; got \(lens.outside.map(\.span.start))",
               &problems)
        SelfTest.expectClose(lens.hoursInSession[9], 180, "the 9 am hour inside sessions", &problems)
        SelfTest.expectClose(lens.hoursOutside[13], 120, "the 1 pm hour outside sessions", &problems)
        expect(lens.alongside.map(\.bundleID) == ["dia"],
               "Dia ran beside Qwen in session A, got \(lens.alongside.map(\.bundleID))", &problems)
        expect(lens.lastUsed == story.at(0, 3, dayOffset: 1), "last used at 12:03 am, got \(String(describing: lens.lastUsed))",
               &problems)
        // 3m inside and 7m outside, printed in whole minutes, make the whole.
        let line = HistorySearchText.lensSentence(appName: "Qwen", lens: lens)
        expect(line.sentence == "You used Qwen for 10m on 2 days.", "the headline read \"\(line.sentence)\"", &problems)
        return problems
    }

    /// A session from 11:30 pm to 12:30 am with Qwen in front 11:50 pm to
    /// 12:10 am; another next morning with Qwen in front for exactly ten
    /// seconds.
    private static func lensEdges() -> [String] {
        var problems: [String] = []
        let story = Story()
        let night = UUID()
        let morning = UUID()
        let records = [
            SessionRecord(name: "Late", workType: .deepWork, start: story.at(23, 30),
                          end: story.at(0, 30, dayOffset: 1), workSeconds: 3_600, threadID: night),
            SessionRecord(name: "Early", workType: .deepWork, start: story.at(10, 0, dayOffset: 1),
                          end: story.at(11, 0, dayOffset: 1), workSeconds: 3_600, threadID: morning)
        ]
        let usage = [
            AppUsageSession(bundleID: "qwen", appName: "Qwen", start: story.at(23, 50), end: story.at(0, 10, dayOffset: 1)),
            AppUsageSession(bundleID: "qwen", appName: "Qwen", start: story.at(10, 20, dayOffset: 1),
                            end: story.at(10, 20, 10, dayOffset: 1))
        ]
        let lens = HistoryAppLens.build(bundleID: "qwen", records: records, usage: SortedUsage(usage),
                                        calendar: story.calendar)
        expect(lens.sessions.map(\.threadID) == [morning, night],
               "both sessions used Qwen, the ten-second one included; got \(lens.sessions.count)", &problems)
        let lateDay = lens.days.first { $0.day == story.day }
        // The card under the 31st says 20m; so must the 31st's own figure.
        SelfTest.expectClose(lateDay?.inSession ?? -1, 1_200, "the 31st's figure for the late session", &problems)
        SelfTest.expectClose(lens.hoursInSession[23], 600, "the 11 pm hour", &problems)
        SelfTest.expectClose(lens.hoursInSession[0], 600, "the 12 am hour", &problems)
        expect(lens.outside.isEmpty, "none of it was outside a session, got \(lens.outside.count) sittings", &problems)
        return problems
    }

    /// Qwen in front for five minutes inside a session that has not stopped.
    private static func runningSession() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let story = Story()
            let clock = TestClock(story.at(9, 0, dayOffset: 1))
            let suite = "fc-selftest-history-lens-running-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["Could not create isolated preferences"] }
            defer { defaults.removePersistentDomain(forName: suite) }
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults),
                                       archive: SelfTest.makeArchive(clock),
                                       ownBundleID: "fc.history-lens.test", schedulesDwell: false,
                                       now: { clock.value })
            engine.start(workType: .deepWork, intent: "Live")
            clock.advance(20 * 60)
            let usage = SelfTest.makeUsageArchive(clock, sessions: [
                AppUsageSession(bundleID: "qwen", appName: "Qwen", start: story.at(9, 5, dayOffset: 1),
                                end: story.at(9, 10, dayOffset: 1))
            ], accurateFrom: story.day)
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "fc.history-lens.test",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.setHistoryApp("qwen")
            let lens = store.historyAppLens()
            expect(lens?.sessions.map(\.threadID) == [engine.activeThreadID],
                   "the running session used Qwen, got \(lens?.sessions.count ?? -1) sessions", &problems)
            SelfTest.expectClose(lens?.inSession ?? -1, 300, "Qwen's time in the running session", &problems)
            SelfTest.expectClose(lens?.outsideTotal ?? -1, 0, "Qwen's time outside sessions", &problems)
            return problems
        }
    }

    private static func searchBySession() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let story = Story()
            let clock = TestClock(story.at(9, 0, dayOffset: 1))
            let suite = "fc-selftest-history-lens-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["Could not create isolated preferences"] }
            defer { defaults.removePersistentDomain(forName: suite) }
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults),
                                       archive: SelfTest.makeArchive(clock, records: story.records),
                                       ownBundleID: "fc.history-lens.test", schedulesDwell: false,
                                       now: { clock.value })
            let usage = SelfTest.makeUsageArchive(clock, sessions: story.usage, accurateFrom: story.day)
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "fc.history-lens.test",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()

            store.setHistoryApp("qwen")
            let picked = store.historySearchHits(limit: .max).map(\.threadID)
            expect(picked == [story.threadA],
                   "picking Qwen lists session A alone, got \(picked.count) sessions", &problems)
            expect(store.historyAppLens()?.sessions.count == 1, "the app's story has session A", &problems)

            store.setHistoryApp(nil)
            store.setHistoryQuery("qwen")
            let typed = store.historySearchHits(limit: .max).map(\.threadID)
            expect(typed == [story.threadA], "typing Qwen finds session A alone, got \(typed.count) sessions", &problems)
            expect(store.historyAppLens() == nil, "a typed word is a search, not the app's story", &problems)
            return problems
        }
    }
}
