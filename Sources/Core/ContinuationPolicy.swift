import Foundation

/// The one eligibility rule for resuming recorded work. A continuation begins
/// a new stretch; it never fills the gap since the recorded stretch ended.
enum ContinuationPolicy {
    static let maximumAge: TimeInterval = 3_600

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
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_AU"))
        return "\(workType.rawValue)|\(words)"
    }

    /// Eligibility is deliberately archive-wide, rather than day-scoped. A
    /// midnight boundary must not resurrect an earlier stretch, and an older
    /// row can never become current merely because the view is browsing it.
    static func isEligible(_ canonical: SessionRecord, records: [SessionRecord],
                           active: RunningThread?, now: Date) -> Bool {
        guard canonical.workType.countsAsFocus,
              canonical.end >= canonical.start,
              let archived = records.first(where: { $0.id == canonical.id }),
              archived == canonical,
              let newestThreadRecord = latest(records.filter {
                  $0.threadID == canonical.threadID && $0.workType.countsAsFocus
              }),
              newestThreadRecord.id == canonical.id else { return false }

        let key = activityKey(name: canonical.name, workType: canonical.workType)
        if let active,
           activityKey(name: active.name, workType: active.workType) == key {
            return false
        }

        guard let newestActivityRecord = latest(records.filter {
            $0.workType.countsAsFocus
                && activityKey(name: $0.name, workType: $0.workType) == key
        }), newestActivityRecord.id == canonical.id else { return false }

        let age = now.timeIntervalSince(canonical.end)
        return age >= 0 && age <= maximumAge
    }

    /// Deterministic selection makes tied imported records fail predictably,
    /// rather than depending on the archive's incidental array order.
    static func latest(_ records: [SessionRecord]) -> SessionRecord? {
        records.max { left, right in
            if left.end != right.end { return left.end < right.end }
            if left.start != right.start { return left.start < right.start }
            return left.id.uuidString < right.id.uuidString
        }
    }
}
