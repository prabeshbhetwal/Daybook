import Foundation

/// One evidence-backed calendar day in History. Tracked time is authoritative
/// app usage; focused time and session count come from the session archive.
/// Their sources remain separate so a historical qualification never becomes a
/// silent reconciliation.
struct HistoryDay: Identifiable, Equatable {
    let date: Date
    let tracked: TimeInterval
    let focused: TimeInterval
    let sessions: Int
    let appBundleIDs: Set<String>
    let workTypes: Set<WorkType>

    var id: Date { date }
}

/// Every non-nil condition must match. A query searches the date plus the
/// canonical app and work-type identifiers carried by `HistoryDay`; the
/// optional app and work-type controls then narrow that result by intersection.
struct HistoryFilter: Equatable {
    var query = ""
    var appBundleID: String?
    var workType: WorkType?

    func apply(to days: [HistoryDay],
               appNamesByBundleID: [String: String] = [:]) -> [HistoryDay] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let descriptive = DateFormatter()
        descriptive.locale = Locale(identifier: "en_AU")
        descriptive.calendar = Calendar(identifier: .gregorian)
        descriptive.dateFormat = "EEEE d MMMM yyyy"

        let stable = DateFormatter()
        stable.locale = Locale(identifier: "en_US_POSIX")
        stable.calendar = Calendar(identifier: .gregorian)
        stable.dateFormat = "yyyy-MM-dd"

        return days.filter { day in
            let queryMatches = needle.isEmpty
                || Self.searchText(for: day, appNamesByBundleID: appNamesByBundleID,
                                   descriptive: descriptive, stable: stable)
                    .contains(needle)
            let appMatches = appBundleID.map(day.appBundleIDs.contains) ?? true
            let workTypeMatches = workType.map(day.workTypes.contains) ?? true
            return queryMatches && appMatches && workTypeMatches
        }
    }

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || appBundleID != nil || workType != nil
    }

    private static func searchText(for day: HistoryDay,
                                   appNamesByBundleID: [String: String],
                                   descriptive: DateFormatter,
                                   stable: DateFormatter) -> String {
        let apps = day.appBundleIDs.sorted().joined(separator: " ")
        let appNames = day.appBundleIDs.compactMap { appNamesByBundleID[$0] }
            .sorted()
            .joined(separator: " ")
        let types = day.workTypes
            .sorted { $0.rawValue < $1.rawValue }
            .flatMap { [$0.rawValue, $0.displayName] }
            .joined(separator: " ")
        return [descriptive.string(from: day.date), stable.string(from: day.date),
                apps, appNames, types]
            .joined(separator: " ")
            .lowercased()
    }
}

/// Canonical History aggregation over the same authoritative in-memory usage
/// snapshot consumed by Today and period rollups. Days without either usage or
/// archive evidence are omitted; existing evidence is never rewritten.
enum HistoryStats {
    /// Presentation refuses any one decoded record that touches more than this
    /// many local days. Four hundred matches the archive's existing defensive
    /// day-walk horizon and comfortably exceeds any legitimate focus/app stretch.
    /// The source record remains byte-identical and available for inspection.
    static let maximumCalendarDaysPerRecord = 400

    private struct DayAccumulator {
        var tracked: TimeInterval = 0
        var focused: TimeInterval = 0
        var threadIDs: Set<UUID> = []
        var appBundleIDs: Set<String> = []
        var workTypes: Set<WorkType> = []
    }

    static func days(sessionRecords: [SessionRecord],
                     usage: [AppUsageSession],
                     calendar: Calendar = .current) -> [HistoryDay] {
        var buckets: [Date: DayAccumulator] = [:]

        // Split each usage stretch only across the calendar days it touches.
        // This is linear in the archive plus cross-midnight spans, rather than
        // rescanning all 20,000 possible usage records once for every day.
        for session in usage where session.end > session.start {
            guard let span = boundedSpan(start: session.start, end: session.end,
                                         calendar: calendar) else { continue }
            var cursor = span.first
            let finalDay = span.last
            while cursor <= finalDay {
                guard let bounds = SessionRecord.dayBounds(cursor, calendar: calendar) else { break }
                let start = max(session.start, bounds.start)
                let end = min(session.end, bounds.end)
                if end > start {
                    var bucket = buckets[cursor] ?? DayAccumulator()
                    bucket.tracked += end.timeIntervalSince(start)
                    bucket.appBundleIDs.insert(session.bundleID)
                    buckets[cursor] = bucket
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        // Session records keep their established proportional day attribution.
        // Break records add a work-type fact but never focused time or a session.
        for record in sessionRecords {
            guard let span = boundedSpan(start: record.start, end: record.end,
                                         calendar: calendar) else { continue }
            var cursor = span.first
            let finalDay = span.last
            while cursor <= finalDay {
                let worked = record.workSeconds(on: cursor, calendar: calendar)
                if worked > 0 {
                    var bucket = buckets[cursor] ?? DayAccumulator()
                    bucket.workTypes.insert(record.workType)
                    if record.workType.countsAsFocus {
                        bucket.focused += worked
                        bucket.threadIDs.insert(record.threadID)
                    }
                    buckets[cursor] = bucket
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        return buckets.map { date, bucket in
            HistoryDay(date: date, tracked: bucket.tracked,
                       focused: bucket.focused, sessions: bucket.threadIDs.count,
                       appBundleIDs: bucket.appBundleIDs,
                       workTypes: bucket.workTypes)
        }
        .sorted { $0.date > $1.date }
    }

    private static func boundedSpan(start: Date, end: Date,
                                    calendar: Calendar) -> (first: Date, last: Date)? {
        guard end >= start else { return nil }
        let first = calendar.startOfDay(for: start)
        // An exclusive midnight end did not touch the following day. Pull the
        // probe just inside any positive interval before counting local days.
        let duration = end.timeIntervalSince(start)
        let probe = duration > 0
            ? end.addingTimeInterval(-min(0.001, duration / 2))
            : end
        let last = calendar.startOfDay(for: probe)
        guard let distance = calendar.dateComponents([.day], from: first, to: last).day,
              distance >= 0,
              distance < maximumCalendarDaysPerRecord else { return nil }
        return (first, last)
    }
}
