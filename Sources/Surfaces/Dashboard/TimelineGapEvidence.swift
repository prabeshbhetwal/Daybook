import Foundation

struct TimelineRestEvidence: Identifiable, Equatable {
    let id: UUID
    let name: String
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Presentation-only partition of one elided gap. Named rests retain only
/// their canonical overlap; every interval outside them remains unknown
/// inactivity instead of inheriting the rest's label.
struct TimelineGapEvidence: Equatable {
    let rests: [TimelineRestEvidence]
    let unknown: [DateInterval]

    init(gap: TimelineGap, breaks: [SessionRecord]) {
        rests = breaks.compactMap { record in
            guard record.workType == .breakTime else { return nil }
            let start = max(gap.start, record.start)
            let end = min(gap.end, record.end)
            guard end > start else { return nil }
            return TimelineRestEvidence(id: record.id,
                                        name: record.name.isEmpty ? "Break" : record.name,
                                        start: start, end: end)
        }.sorted { $0.start < $1.start }

        var unlabelled: [DateInterval] = []
        var cursor = gap.start
        for rest in rests {
            if rest.start > cursor {
                unlabelled.append(DateInterval(start: cursor, end: rest.start))
            }
            cursor = max(cursor, rest.end)
        }
        if cursor < gap.end {
            unlabelled.append(DateInterval(start: cursor, end: gap.end))
        }
        unknown = unlabelled
    }
}
