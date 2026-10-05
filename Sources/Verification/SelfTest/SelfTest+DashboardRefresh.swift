import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Archive callbacks update the dashboard immediately only while it is on
    /// screen. Hidden mutations are coalesced until the next appearance.
    static func testDashboardArchiveVisibility() -> [String] {
        var problems: [String] = []
        let clock = TestClock(anchoredNow())
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let sessions = SessionArchive(directory: directory, now: { clock.value })
        let engine = SessionEngine(store: persistence, archive: sessions,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine)
        store.attach(tracker: tracker, usage: usage)
        let day = Calendar.current.startOfDay(for: clock.value)
        let identity = UUID()

        func checkpoint(minutes: Double) {
            usage.checkpoint(AppUsageSession(id: identity, bundleID: "com.example.editor",
                                             appName: "Editor",
                                             start: day.addingTimeInterval(9 * 3_600),
                                             end: day.addingTimeInterval(9 * 3_600 + minutes * 60),
                                             endReason: .stillOpen))
        }

        checkpoint(minutes: 10)
        expectClose(store.trackedForSelectedDay, 0,
                    "a hidden dashboard does not refresh immediately", &problems)
        store.refresh()
        expectClose(store.trackedForSelectedDay, 0,
                    "an ordinary hidden refresh does not consume the full dashboard", &problems)
        expectClose(store.glanceApps.first?.total ?? -1, 10 * 60,
                    "the hidden-dashboard refresh still updates today's popover glance", &problems)
        store.setDashboardVisible(true)
        expectClose(store.trackedForSelectedDay, 10 * 60,
                    "appearing consumes the pending archive refresh", &problems)

        checkpoint(minutes: 20)
        expectClose(store.trackedForSelectedDay, 20 * 60,
                    "a visible dashboard refreshes a same-count correction immediately", &problems)

        store.setDashboardVisible(false)
        checkpoint(minutes: 30)
        expectClose(store.trackedForSelectedDay, 20 * 60,
                    "a hidden dashboard keeps its last rendered value", &problems)
        store.setDashboardVisible(true)
        expectClose(store.trackedForSelectedDay, 30 * 60,
                    "the next appearance refreshes hidden archive changes", &problems)
        return problems
    }

    /// A normal refresh flushes the open stretch. Its synchronous archive
    /// callback must join that transaction rather than re-entering the full
    /// selected-day/period rebuild and publishing every figure twice.
    static func testDashboardRefreshCoalescesCheckpointCallback() -> [String] {
        var problems: [String] = []
        let clock = TestClock(anchoredNow())
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence,
                                   archive: SessionArchive(directory: directory,
                                                           now: { clock.value }),
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value }, idle: .disabled)
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
        clock.advance(10 * 60)

        var fullTrackedPublications = 0
        let observation = store.$trackedForSelectedDay.dropFirst().sink { _ in
            fullTrackedPublications += 1
        }
        store.refresh()

        expect(usage.sessions.count == 1, "refresh flushes one stable checkpoint", &problems)
        expectClose(store.trackedForSelectedDay, 10 * 60,
                    "the one full rebuild sees the flushed checkpoint", &problems)
        expect(fullTrackedPublications == 1,
               "one refresh transaction publishes the full tracked figure once, got "
               + "\(fullTrackedPublications)", &problems)
        withExtendedLifetime(observation) {}
        return problems
    }

    /// Preserved usage before the authoritative recording epoch remains
    /// visible, but the selected day carries the approved qualification.
    static func testSelectedDayIntegrityNote() -> [String] {
        var problems: [String] = []
        let clock = TestClock(anchoredNow())
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence,
                                   archive: SessionArchive(directory: directory,
                                                           now: { clock.value }),
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        guard let yesterday = calendar.date(byAdding: .day, value: -1,
                                            to: calendar.startOfDay(for: clock.value)) else {
            return ["could not make the pre-accuracy day"]
        }
        usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                     start: yesterday.addingTimeInterval(10 * 3_600),
                                     end: yesterday.addingTimeInterval(10.5 * 3_600)))
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine)
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.selectDay(offset: 1)

        let expected = "App usage from before \(Tokens.longDate(clock.value)) was preserved "
            + "and may include unattended time."
        expect(store.selectedDayIntegrityNote == expected,
               "the selected pre-accuracy day shows the approved warning", &problems)
        store.selectDay(offset: 2)
        expect(store.selectedDayIntegrityNote == nil,
               "a pre-accuracy day without usage has no warning", &problems)
        store.setDashboardVisible(false)
        guard let twoDaysAgo = calendar.date(byAdding: .day, value: -2,
                                             to: calendar.startOfDay(for: clock.value)) else {
            return problems + ["could not make the second pre-accuracy day"]
        }
        usage.record(AppUsageSession(bundleID: "com.example.browser", appName: "Browser",
                                     start: twoDaysAgo.addingTimeInterval(11 * 3_600),
                                     end: twoDaysAgo.addingTimeInterval(11.25 * 3_600)))
        store.refresh()
        expect(store.selectedDayIntegrityNote == nil,
               "the cached warning stays frozen while the dashboard is hidden", &problems)
        store.setDashboardVisible(true)
        expect(store.selectedDayIntegrityNote == expected,
               "dashboard appearance rebuilds the cached warning", &problems)
        store.selectDay(offset: 0)
        expect(store.selectedDayIntegrityNote == nil,
               "an authoritative selected day has no warning", &problems)
        return problems
    }

    /// Period qualification is about every bar and log row in view, not merely
    /// the anchor day. A post-epoch anchor must still warn when its selected
    /// week or month reaches back into preserved legacy usage.
    static func testPeriodIntegrityNoteCoversCompleteRange() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let anchor = periodAnchor()
        guard let week = calendar.weeksFromMonday.dateInterval(of: .weekOfYear, for: anchor),
              let month = calendar.dateInterval(of: .month, for: anchor) else {
            return ["could not construct period integrity bounds"]
        }
        let legacyWeekStart = week.start.addingTimeInterval(2 * 3_600)
        let legacyMonthStart = month.start.addingTimeInterval(3 * 3_600)
        let accurateFrom = max(legacyWeekStart, legacyMonthStart).addingTimeInterval(3_600)
        guard accurateFrom < anchor else {
            return ["the anchored period has no pre-epoch interval to exercise"]
        }

        let clock = TestClock(accurateFrom)
        let directory = scratchDirectory()
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        usage.record(AppUsageSession(bundleID: "com.example.week", appName: "Week Legacy",
                                     start: legacyWeekStart,
                                     end: legacyWeekStart.addingTimeInterval(600)))
        usage.record(AppUsageSession(bundleID: "com.example.month", appName: "Month Legacy",
                                     start: legacyMonthStart,
                                     end: legacyMonthStart.addingTimeInterval(600)))
        clock.value = anchor

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence,
                                   archive: SessionArchive(directory: directory,
                                                           now: { clock.value }),
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      isEnabled: false, idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        expect(store.selectedDayIntegrityNote == nil,
               "the post-epoch anchor day itself has no legacy warning", &problems)

        let expected = "App usage from before \(Tokens.longDate(accurateFrom)) was preserved "
            + "and may include unattended time."
        store.period = .week
        expect(store.selectedDayIntegrityNote == expected,
               "Week warns when any selected day contains legacy usage", &problems)
        store.period = .month
        expect(store.selectedDayIntegrityNote == expected,
               "Month warns when any selected day contains legacy usage", &problems)
        return problems
    }
}
