import Foundation

extension HistoryAppLens {
    /// The other apps in front during the spans, busiest first; shares are of
    /// all app use in them, this app's included.
    static func appsAlongside(_ bundleID: String, in spans: [DateInterval], usage: SortedUsage) -> [AppRank] {
        var others: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        var overall: TimeInterval = 0
        usage.forEachOverlap(spans) { stretch, piece in
            overall += piece.duration
            guard stretch.bundleID != bundleID else { return }
            var entry = others[stretch.bundleID] ?? (stretch.appName, 0, 0)
            entry.total += piece.duration
            entry.longest = max(entry.longest, piece.duration)
            others[stretch.bundleID] = entry
        }
        var ranks: [AppRank] = []
        for (bundle, entry) in others {
            ranks.append(AppRank(bundleID: bundle, appName: entry.name, total: entry.total,
                                 share: overall > 0 ? entry.total / overall : 0, longest: entry.longest))
        }
        return ranks.sorted { $0.total == $1.total ? $0.bundleID < $1.bundleID : $0.total > $1.total }
    }

    static func legacySeconds(_ used: [DateInterval], before date: Date) -> TimeInterval {
        used.reduce(0) { total, interval in
            interval.start < date ? total + min(interval.end, date).timeIntervalSince(interval.start) : total
        }
    }
}
