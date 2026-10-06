import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// A preserved legacy stretch may remain visible in Review, but Insights
    /// cannot call it verified Rhythm or an authoritative active day. A later
    /// complete day remains eligible and supplies the literal expected totals.
    static func testInsightsExcludePreAccuracyUsage() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: periodAnchor(calendar: calendar))
        let clock = TestClock(today.addingTimeInterval(12 * 3_600))
        guard let accurateDay = calendar.date(byAdding: .day, value: -2, to: today),
              let legacyDay = calendar.date(byAdding: .day, value: -3, to: today) else {
            return ["could not build mixed-accuracy Insights dates"]
        }
        let legacyStart = legacyDay.addingTimeInterval(9 * 3_600)
        let authoritativeStart = today.addingTimeInterval(9 * 3_600)
        let usage = makeUsageArchive(
            clock,
            sessions: [
                AppUsageSession(bundleID: "org.example.legacy", appName: "Legacy",
                                start: legacyStart,
                                end: legacyStart.addingTimeInterval(60 * 60)),
                AppUsageSession(bundleID: "org.example.current", appName: "Current",
                                start: authoritativeStart,
                                end: authoritativeStart.addingTimeInterval(30 * 60))
            ],
            accurateFrom: accurateDay.addingTimeInterval(12 * 3_600))
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let archive = makeArchive(clock)
        archive.append(SessionRecord(name: "Legacy deep work", workType: .deepWork,
                                     start: legacyStart,
                                     end: legacyStart.addingTimeInterval(60 * 60),
                                     workSeconds: 60 * 60))
        archive.append(SessionRecord(name: "Current admin", workType: .admin,
                                     start: authoritativeStart,
                                     end: authoritativeStart.addingTimeInterval(30 * 60),
                                     workSeconds: 30 * 60))
        let engine = SessionEngine(
            store: persistence,
            archive: archive,
            ownBundleID: "com.example.self",
            schedulesDwell: false,
            now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.refreshInsights()

        let month = store.insightMonthSurface
        expect(month.rhythm?.detail.hasPrefix("30m at the Mac") == true,
               "verified Rhythm sums only the literal authoritative 30m; got "
                   + "'\(month.rhythm?.detail ?? "nil")'", &problems)
        expect(month.rhythm?.detail.contains("1h 30m") != true,
               "legacy time is absent from verified Rhythm", &problems)
        expect(month.continuity?.headline.hasPrefix("1 of 2 days had tracked time") == true,
               "active-day continuity counts only complete authoritative days; got "
                   + "'\(month.continuity?.headline ?? "nil")'", &problems)
        expect(month.quality?.headline == "Admin was 100% of focused time",
               "Focus quality excludes preserved pre-accuracy session/usage evidence; got "
                   + "'\(month.quality?.headline ?? "nil")'", &problems)
        expect(month.quality?.detail.hasPrefix("1 recorded focus session supplies") == true,
               "Focus quality counts only the authoritative thread session; got "
                   + "'\(month.quality?.detail ?? "nil")'", &problems)
        return problems
    }

    /// Week and Month are range statements. One canonical thread resumed after
    /// local midnight remains one focus session, and an A-to-B app change across
    /// those resumed stretches remains one real transition divided by that one
    /// session — never two daily denominators that dilute the rate to zero.
    static func testInsightQualityDeduplicatesThreadsAcrossRange() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 26
        components.hour = 12
        guard let moment = SelfTest.gregorian.date(from: components),
              let firstDay = calendar.date(byAdding: .day, value: -1,
                                           to: calendar.startOfDay(for: moment)),
              let accuracyDay = calendar.date(byAdding: .day, value: -1,
                                              to: firstDay) else {
            return ["could not build cross-day Insights quality fixture"]
        }
        let secondDay = calendar.startOfDay(for: moment)
        let clock = TestClock(moment)
        let threadID = UUID()
        let firstStart = firstDay.addingTimeInterval(23.5 * 3_600)
        let secondStart = secondDay.addingTimeInterval(10 * 60)
        let records = [
            SessionRecord(name: "Range thread", workType: .deepWork,
                          start: firstStart,
                          end: firstStart.addingTimeInterval(20 * 60),
                          workSeconds: 20 * 60, threadID: threadID),
            SessionRecord(name: "Range thread", workType: .deepWork,
                          start: secondStart,
                          end: secondStart.addingTimeInterval(30 * 60),
                          workSeconds: 30 * 60, threadID: threadID)
        ]
        let usage = makeUsageArchive(
            clock,
            sessions: [
                AppUsageSession(bundleID: "org.example.alpha", appName: "Alpha",
                                start: firstStart,
                                end: firstStart.addingTimeInterval(20 * 60)),
                AppUsageSession(bundleID: "org.example.beta", appName: "Beta",
                                start: secondStart,
                                end: secondStart.addingTimeInterval(30 * 60))
            ],
            accurateFrom: accuracyDay.addingTimeInterval(12 * 3_600))
        let archive = makeArchive(clock, records: records, calendar: calendar)
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.refreshInsights()

        for (label, surface) in [("Week", store.insightWeekSurface),
                                 ("Month", store.insightMonthSurface)] {
            let detail = surface.quality?.detail ?? "nil"
            expect(detail.hasPrefix("1 recorded focus session supplies"),
                   "\(label) deduplicates the resumed thread; got '\(detail)'", &problems)
            expect(detail.contains("1.0 app switches per recorded focus session"),
                   "\(label) keeps the cross-day A-to-B transition undiluted; got "
                       + "'\(detail)'", &problems)
        }
        return problems
    }

    /// Tracker-originated checkpoints publish archive callbacks while the
    /// tracker is transitioning. Insights must join that final transition frame
    /// just like Review, then retain a pending refresh while hidden.
    static func testTrackerTransitionsInvalidateInsights() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchoredNow())
        let clock = TestClock(today.addingTimeInterval(9 * 3_600))
        guard let accurateFrom = calendar.date(byAdding: .day, value: -3, to: today) else {
            return ["could not build tracker Insights accuracy epoch"]
        }
        let usage = makeUsageArchive(clock, sessions: [], accurateFrom: accurateFrom)
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(
            store: persistence,
            archive: makeArchive(clock),
            ownBundleID: "com.example.self",
            schedulesDwell: false,
            now: { clock.value })
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setInsightsVisible(true)
        expect(store.insightWeekSurface.rhythm == nil,
               "the visible fixture begins without Rhythm", &problems)

        tracker.appActivated(bundleID: "org.example.editor", name: "Editor")
        clock.advance(10)
        tracker.flush()
        expect(store.insightWeekSurface.rhythm?.detail.hasPrefix("10s at the Mac") == true,
               "a visible tracker checkpoint refreshes Insights on its final frame; got "
                   + "'\(store.insightWeekSurface.rhythm?.detail ?? "nil")'", &problems)

        store.setInsightsVisible(false)
        clock.advance(10)
        tracker.flush()
        expect(store.insightsRefreshPending,
               "a hidden tracker checkpoint leaves Insights pending", &problems)
        store.setInsightsVisible(true)
        expect(store.insightWeekSurface.rhythm?.detail.hasPrefix("20s at the Mac") == true,
               "the next open consumes the hidden tracker checkpoint; got "
                   + "'\(store.insightWeekSurface.rhythm?.detail ?? "nil")'", &problems)
        return problems
    }

    /// A small positive share/rate is evidence. Decimal rounding must not turn
    /// it into a visible assertion of zero.
    static func testInsightQualityPreservesTinyPositiveEvidence() -> [String] {
        var problems: [String] = []
        let surface = InsightSurface.make(
            range: .week,
            goal: GoalProgress(goal: 4 * 3_600, achieved: 0, typical: nil),
            rhythm: [],
            rhythmPeak: nil,
            quality: FocusQuality(
                byWorkType: [WorkTypeShare(workType: .deepWork,
                                           seconds: 30, share: 0.004)],
                insideSessionShare: 0.004,
                switchesPerSession: 0.04,
                sessionCount: 1),
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)
        let headline = surface.quality?.headline ?? ""
        let detail = surface.quality?.detail ?? ""
        expect(headline == "Deep work was <1% of focused time",
               "tiny positive work-type share uses an honest lower bound; got '\(headline)'",
               &problems)
        expect(detail.contains("<1% of tracked time")
                   && detail.contains("<0.1 app switches"),
               "tiny positive quality details retain both lower bounds; got '\(detail)'",
               &problems)
        expect(detail.hasPrefix("1 recorded focus session supplies"),
               "singular quality evidence uses the singular verb; got '\(detail)'",
               &problems)
        expect(!headline.contains(" 0%") && !detail.contains(" 0%")
                   && !detail.contains("0.0 app switches"),
               "positive quality facts never render as zero", &problems)
        return problems
    }
}
