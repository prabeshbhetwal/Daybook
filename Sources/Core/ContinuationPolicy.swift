import Foundation

/// The one eligibility rule for resuming recorded work. A continuation begins
/// a new stretch; it never fills the gap since the recorded stretch ended.
enum ContinuationPolicy {
    static let maximumAge: TimeInterval = 3_600

    /// Archive facts which are stable until the next archive revision. Building
    /// this once lets a continuation list inspect each candidate without
    /// repeatedly scanning the entire history; actions still create a fresh
    /// index at their own boundary.
    struct Index {
        private let recordsByID: [UUID: SessionRecord]
        private let duplicateIDs: Set<UUID>
        let latestByThread: [UUID: SessionRecord]
        let latestByActivity: [String: SessionRecord]

        init(records: [SessionRecord]) {
            var byID: [UUID: SessionRecord] = [:]
            var duplicates = Set<UUID>()
            var threads: [UUID: SessionRecord] = [:]
            var activities: [String: SessionRecord] = [:]
            for record in records {
                if byID[record.id] != nil { duplicates.insert(record.id) }
                byID[record.id] = record
                guard record.workType.countsAsFocus else { continue }
                if let previous = threads[record.threadID] {
                    if isLater(record, than: previous) { threads[record.threadID] = record }
                } else {
                    threads[record.threadID] = record
                }
                let key = activityKey(name: record.name, workType: record.workType)
                if let previous = activities[key] {
                    if isLater(record, than: previous) { activities[key] = record }
                } else {
                    activities[key] = record
                }
            }
            recordsByID = byID
            duplicateIDs = duplicates
            latestByThread = threads
            latestByActivity = activities
        }

        func isEligible(_ canonical: SessionRecord, active: RunningThread?, now: Date) -> Bool {
            guard canonical.workType.countsAsFocus,
                  canonical.end >= canonical.start,
                  !duplicateIDs.contains(canonical.id),
                  recordsByID[canonical.id] == canonical,
                  latestByThread[canonical.threadID]?.id == canonical.id else { return false }

            let key = activityKey(name: canonical.name, workType: canonical.workType)
            if let active,
               activityKey(name: active.name, workType: active.workType) == key {
                return false
            }
            guard latestByActivity[key]?.id == canonical.id else { return false }
            let age = now.timeIntervalSince(canonical.end)
            return age >= 0 && age <= maximumAge
        }
    }

    /// Names are user text, so casing, surrounding space and repeated internal
    /// whitespace must not manufacture separate activities. Work type remains
    /// part of the identity: "Planning" as Admin is not the same activity as a
    /// later deliberately reclassified "Planning" as Learning.
    static func activityKey(name: String, workType: WorkType) -> String {
        let words = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive],
                     locale: Locale(identifier: "en_AU"))
        return "\(workType.rawValue)|\(words)"
    }

    /// Eligibility is deliberately archive-wide, rather than day-scoped. A
    /// midnight boundary must not resurrect an earlier stretch, and an older
    /// row can never become current merely because the view is browsing it.
    static func isEligible(_ canonical: SessionRecord, records: [SessionRecord],
                           active: RunningThread?, now: Date) -> Bool {
        Index(records: records).isEligible(canonical, active: active, now: now)
    }

    /// Deterministic selection makes tied imported records fail predictably,
    /// rather than depending on the archive's incidental array order.
    static func latest(_ records: [SessionRecord]) -> SessionRecord? {
        records.max { left, right in !isLater(left, than: right) }
    }

    private static func isLater(_ candidate: SessionRecord, than current: SessionRecord) -> Bool {
        if candidate.end != current.end { return candidate.end > current.end }
        if candidate.start != current.start { return candidate.start > current.start }
        return candidate.id.uuidString > current.id.uuidString
    }
}
