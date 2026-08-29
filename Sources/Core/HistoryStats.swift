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

    func apply(to days: [HistoryDay]) -> [HistoryDay] {
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
                || Self.searchText(for: day, descriptive: descriptive, stable: stable)
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
                                   descriptive: DateFormatter,
                                   stable: DateFormatter) -> String {
        let apps = day.appBundleIDs.sorted().joined(separator: " ")
        let types = day.workTypes
            .sorted { $0.rawValue < $1.rawValue }
            .flatMap { [$0.rawValue, $0.displayName] }
            .joined(separator: " ")
        return [descriptive.string(from: day.date), stable.string(from: day.date), apps, types]
            .joined(separator: " ")
            .lowercased()
    }
}

/// Canonical History aggregation over the same authoritative in-memory usage
/// snapshot consumed by Today and period rollups. Days without either usage or
/// archive evidence are omitted; existing evidence is never rewritten.
enum HistoryStats {
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
            var cursor = calendar.startOfDay(for: session.start)
            let finalDay = calendar.startOfDay(for: session.end)
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
            var cursor = calendar.startOfDay(for: record.start)
            let finalDay = calendar.startOfDay(for: record.end)
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
}
