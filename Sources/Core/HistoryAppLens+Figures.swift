import Foundation

extension HistoryAppLens {
    /// The other apps in front during the spans, busiest first; shares are of
    /// all app use in them, this app's included.
    static func appsAlongside(_ bundleID: String, in spans: [DateInterval], usage: SortedUsage) -> [AppRank] {
        let all = usage.uniqueUse(within: spans)
        let overall = all.values.reduce(0) { $0 + $1.total }
        var ranks: [AppRank] = []
        for (bundle, entry) in all where bundle != bundleID {
            ranks.append(AppRank(bundleID: bundle, appName: entry.name, total: entry.total,
                                 share: overall > 0 ? entry.total / overall : 0, longest: entry.longest))
        }
        return ranks.sorted { $0.total == $1.total ? $0.bundleID < $1.bundleID : $0.total > $1.total }
    }

    /// The moments' seconds outside the records' pauses, where a record says
    /// exactly when it paused. Each record's pauses are cut to its own span,
    /// so a pause saved past a record's end never takes time from the next.
    static func unpausedSeconds(_ moments: [DateInterval], in records: [SessionRecord]) -> TimeInterval {
        let paused = merged(records.flatMap { record in
            (record.exactPausedSpans ?? []).compactMap {
                $0.intersection(with: DateInterval(start: record.start, end: record.end))
            }
        })
        return moments.reduce(0) { total, moment in
            split(moment, by: paused).outside.reduce(total) { $0 + $1.duration }
        }
    }

    static func legacySeconds(_ used: [DateInterval], before date: Date) -> TimeInterval {
        used.reduce(0) { total, interval in
            interval.start < date ? total + min(interval.end, date).timeIntervalSince(interval.start) : total
        }
    }
}
