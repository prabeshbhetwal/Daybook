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
    /// Focused seconds by category, so a period can name the category it
    /// spent most of its focus in. Sums to `focused`.
    var focusByWorkType: [WorkType: TimeInterval] = [:]

    var id: Date { date }
}

/// History is a derived presentation index. Source records whose decoded span
/// exceeds the defensive day-walk bound stay byte-identical in their archives,
/// but the omission must travel with the derived rows so the UI can disclose it.
struct HistoryBuildResult: Equatable {
    let days: [HistoryDay]
    let droppedUsageSpans: Int
    let droppedFocusSpans: Int
    let droppedRestSpans: Int
    /// Focus, rest and app-usage records left out for starting before the day
    /// ahead of the install date.
    var droppedBeforeInstall = 0
}

/// How History reads a query: each word must turn up somewhere in what a
/// thing is known by, in any order, ignoring case and accents. So
/// "cafe tuesday" finds the break named "Café" on a Tuesday, and
/// "parser notes" finds the session called Parser whose note says "notes".
enum SearchWords {
    /// Lower-cased, accents dropped: the form both sides are compared in.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The query's words, folded, with stray punctuation at their edges
    /// dropped so "parser," still finds Parser. Inner punctuation stays, so
    /// "2026-09-28" and "28/9" are still one word each.
    static func words(in query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    /// True when every word is in `text`. `text` must already be folded.
    static func all(_ words: [String], in text: String) -> Bool {
        words.allSatisfy(text.contains)
    }
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
        let words = SearchWords.words(in: query)
        let descriptive = DateFormatter()
        descriptive.locale = Locale(identifier: "en_AU")
        descriptive.calendar = Calendar(identifier: .gregorian)
        descriptive.dateFormat = "EEEE d MMMM yyyy"

        let stable = DateFormatter()
        stable.locale = Locale(identifier: "en_US_POSIX")
        stable.calendar = Calendar(identifier: .gregorian)
        stable.dateFormat = "yyyy-MM-dd"

        return days.filter { day in
            let queryMatches = words.isEmpty
                || SearchWords.all(words, in: Self.searchText(for: day, appNamesByBundleID: appNamesByBundleID,
                                                              descriptive: descriptive, stable: stable))
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
        return SearchWords.fold([descriptive.string(from: day.date), stable.string(from: day.date),
                                 apps, appNames, types]
            .joined(separator: " "))
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
        var focusByWorkType: [WorkType: TimeInterval] = [:]
    }

    private enum SpanResolution {
        case accepted(first: Date, last: Date)
        case invalid
        case exceedsBound
    }

    /// - Parameter installedOn: when this Mac started keeping history. A record
    ///   that starts before the day ahead of it is malformed and left out; the
    ///   day ahead keeps a first session that began before the app first saved.
    static func build(sessionRecords: [SessionRecord],
                      usage: [AppUsageSession],
                      calendar: Calendar = .current,
                      installedOn: Date? = nil) -> HistoryBuildResult {
        var buckets: [Date: DayAccumulator] = [:]
        var droppedUsageSpans = 0
        var droppedFocusSpans = 0
        var droppedRestSpans = 0
        var droppedBeforeInstall = 0
        let earliest = earliestDay(installedOn: installedOn, calendar: calendar)

        // Split each usage stretch only across the calendar days it touches.
        // This is linear in the archive plus cross-midnight spans, rather than
        // rescanning all 20,000 possible usage records once for every day.
        for session in usage where session.end > session.start {
            if let earliest, session.start < earliest {
                droppedBeforeInstall += 1
                continue
            }
            let span: (first: Date, last: Date)
            switch boundedSpan(start: session.start, end: session.end, calendar: calendar) {
            case .accepted(let first, let last): span = (first, last)
            case .exceedsBound:
                droppedUsageSpans += 1
                continue
            case .invalid:
                continue
            }
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
            if let earliest, record.start < earliest {
                droppedBeforeInstall += 1
                continue
            }
            let span: (first: Date, last: Date)
            switch boundedSpan(start: record.start, end: record.end, calendar: calendar) {
            case .accepted(let first, let last): span = (first, last)
            case .exceedsBound:
                if record.workType.countsAsFocus { droppedFocusSpans += 1 }
                else { droppedRestSpans += 1 }
                continue
            case .invalid:
                continue
            }
            var cursor = span.first
            let finalDay = span.last
            while cursor <= finalDay {
                let worked = record.workSeconds(on: cursor, calendar: calendar)
                if worked > 0 {
                    var bucket = buckets[cursor] ?? DayAccumulator()
                    bucket.workTypes.insert(record.workType)
                    if record.workType.countsAsFocus {
                        bucket.focused += worked
                        bucket.focusByWorkType[record.workType, default: 0] += worked
                        bucket.threadIDs.insert(record.threadID)
                    }
                    buckets[cursor] = bucket
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        let days = buckets.map { date, bucket in
            HistoryDay(date: date, tracked: bucket.tracked,
                       focused: bucket.focused, sessions: bucket.threadIDs.count,
                       appBundleIDs: bucket.appBundleIDs,
                       workTypes: bucket.workTypes,
                       focusByWorkType: bucket.focusByWorkType)
        }
        .sorted { $0.date > $1.date }
        return HistoryBuildResult(days: days,
                                  droppedUsageSpans: droppedUsageSpans,
                                  droppedFocusSpans: droppedFocusSpans,
                                  droppedRestSpans: droppedRestSpans,
                                  droppedBeforeInstall: droppedBeforeInstall)
    }

    /// The first day History shows: the day ahead of the install date, which
    /// keeps a first session that began before the app first saved.
    static func earliestDay(installedOn: Date?, calendar: Calendar) -> Date? {
        installedOn.flatMap {
            calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: $0))
        }
    }

    private static func boundedSpan(start: Date, end: Date,
                                    calendar: Calendar) -> SpanResolution {
        guard end >= start else { return .invalid }
        let first = calendar.startOfDay(for: start)
        // An exclusive midnight end did not touch the following day. Pull the
        // probe just inside any positive interval before counting local days.
        let duration = end.timeIntervalSince(start)
        let probe = duration > 0
            ? end.addingTimeInterval(-min(0.001, duration / 2))
            : end
        let last = calendar.startOfDay(for: probe)
        guard let distance = calendar.dateComponents([.day], from: first, to: last).day,
              distance >= 0 else { return .invalid }
        guard distance < maximumCalendarDaysPerRecord else { return .exceedsBound }
        return .accepted(first: first, last: last)
    }
}
