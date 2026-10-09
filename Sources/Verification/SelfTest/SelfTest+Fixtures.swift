import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    struct UsageEnvelopeFixture: Codable {
        let metadata: AppUsageMetadata
        let sessions: [AppUsageSession]
    }

    /// A scratch directory per archive so tests never touch real history.
    static func scratchDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-selftest-\(UUID().uuidString)", isDirectory: true)
        scratchDirectories.append(directory)
        return directory
    }

    static func makeArchive(_ clock: TestClock) -> SessionArchive {
        SessionArchive(directory: scratchDirectory(), now: { clock.value })
    }

    static func makeArchive(_ clock: TestClock,
                                    records: [SessionRecord],
                                    calendar: Calendar = .current) -> SessionArchive {
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: directory.appendingPathComponent("sessions.json"),
                            options: .atomic)
        }
        return SessionArchive(directory: directory, calendar: calendar,
                              now: { clock.value })
    }

    static func makeEngine(_ clock: TestClock) -> SessionEngine {
        let defaults = MemoryDefaults.suite(named: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        return SessionEngine(store: store,
                             archive: makeArchive(clock),
                             ownBundleID: FocusConstants.bundleIdentifier,
                             schedulesDwell: false,
                             now: { clock.value })
    }

    static func makeUsageArchive(_ clock: TestClock,
                                         sessions: [AppUsageSession],
                                         accurateFrom: Date? = nil) -> AppUsageArchive {
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let envelope = UsageEnvelopeFixture(
            metadata: AppUsageMetadata(accurateFrom: accurateFrom ?? clock.value),
            sessions: sessions)
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: directory.appendingPathComponent("app-usage.json"),
                            options: .atomic)
        }
        return AppUsageArchive(directory: directory, now: { clock.value })
    }

    /// Gregorian in the Mac's own time zone, for fixtures that name a day by
    /// year, month and day. Under a Hebrew or Buddhist calendar
    /// `Calendar.current` reads 2026 as another year entirely.
    static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// "Now", moved to noon when the real clock is within three hours of
    /// midnight, so fixtures built as "two hours ago, today" stay inside today.
    /// Tests 87 and 94 failed at 00:45 because their earlier stretches fell on
    /// yesterday and only the after-midnight share counted.
    static func anchoredNow() -> Date {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? now
        // Both edges, measured on the calendar: a daylight-saving day is 23 or
        // 25 hours. Fixtures step forward from here, and one started at 23:55
        // crossed into the next day.
        let nearMidnight = now.timeIntervalSince(dayStart) < 3 * 3_600
            || nextDay.timeIntervalSince(now) < 3 * 3_600
        return nearMidnight ? dayStart.addingTimeInterval(12 * 3_600) : now
    }

    /// An anchor that is safely inside its own week and month: fixtures that
    /// seed "today, yesterday, two days ago" and then roll them up by week or
    /// month must not straddle a boundary. On a Monday the plain anchor put
    /// yesterday in the previous week, which emptied the week's chart and made
    /// the anchor day the first day of its own period.
    static func periodAnchor(calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
        for _ in 0..<40 {
            let start = calendar.weeksFromMonday.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            let daysIntoWeek = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            let dayOfMonth = calendar.component(.day, from: day)
            if daysIntoWeek >= 2, dayOfMonth >= 10 { return day }
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return day
    }
}
