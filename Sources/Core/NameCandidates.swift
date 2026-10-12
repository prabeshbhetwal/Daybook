import Foundation

/// One earlier named session, reduced to what name matching reads.
struct NameHistoryEntry: Equatable {
    let name: String
    let workType: WorkType
    let end: Date
    /// Bundle ID → seconds in front within the session.
    let appSeconds: [String: TimeInterval]
}

/// An earlier name worth offering for a session that has none.
struct NameCandidate: Equatable {
    /// The most recent spelling.
    let name: String
    /// Shared app time, plus the category bonus.
    let score: Double
    /// The most common category among the name's sessions.
    let usualWorkType: WorkType
    /// Bundle IDs by share of the name's time, at most three.
    let usualApps: [String]
}

/// What the on-device model reads about one unnamed session.
struct NameFacts: Equatable {
    /// The session, its apps, its note and the candidates, one per line.
    let text: String
    let candidates: [NameCandidate]
    /// Display names of the session's apps, for `NameAudit`.
    let appNames: [String]
    /// Changes when the session's facts or the earlier names' ranking change,
    /// so an answer is asked again.
    let cacheKey: String
}

/// Ranks the person's own earlier names by the app time they share with a
/// session. Pure: the caller decides which sessions count as history.
enum NameCandidates {
    static let threshold = 0.3, categoryBonus = 0.1, limit = 3
    /// How far the best earlier name must lead the second.
    static let margin = 0.1

    /// Whether the best earlier name stands clear of the second: with two or
    /// more candidates, an ambiguous session gets no suggestion. The category
    /// bonus equals the margin, so a lead of exactly 0.1 must count despite
    /// floating point (0.85 - 0.75 is a hair under 0.1).
    static func isClearLead(_ candidates: [NameCandidate]) -> Bool {
        candidates.count < 2 || candidates[0].score - candidates[1].score >= margin - 1e-9
    }

    /// Σ over apps of min(share in a, share in b), so 0 to 1; 0 when either
    /// side has no time. Summed in bundle-ID order: a dictionary's order is
    /// not promised, and a different order could move the last digits, and
    /// with them the answer's cache key.
    static func shared(_ a: [String: TimeInterval], _ b: [String: TimeInterval]) -> Double {
        let appsA = a.sorted { $0.key < $1.key }
        let totalA = appsA.reduce(0) { $0 + $1.value }
        let totalB = b.sorted { $0.key < $1.key }.reduce(0) { $0 + $1.value }
        guard totalA > 0, totalB > 0 else { return 0 }
        return appsA.reduce(0) { sum, app in
            sum + min(app.value / totalA, (b[app.key] ?? 0) / totalB)
        }
    }

    /// Groups `history` by name, ignoring case and accents, keeps the groups
    /// whose shared time with `appSeconds` reaches `threshold`, and ranks them
    /// by score. A tie goes to the group used more recently.
    static func rank(appSeconds: [String: TimeInterval], workType: WorkType,
                     history: [NameHistoryEntry]) -> [NameCandidate] {
        let groups = Dictionary(grouping: history) {
            SearchWords.fold($0.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let ranked: [(candidate: NameCandidate, end: Date)] = groups.compactMap { key, entries in
            guard !key.isEmpty else { return nil }
            let newest = entries.max { $0.end < $1.end }!
            let mix = entries.reduce(into: [String: TimeInterval]()) { total, entry in
                for (app, seconds) in entry.appSeconds { total[app, default: 0] += seconds }
            }
            let sharedTime = shared(appSeconds, mix)
            guard sharedTime >= threshold else { return nil }
            let usual = usualWorkType(of: entries)
            // Ties between apps resolve by bundle ID so the order is stable.
            let apps = mix.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(3).map(\.key)
            let score = sharedTime + (usual == workType ? categoryBonus : 0)
            return (NameCandidate(name: newest.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  score: score, usualWorkType: usual, usualApps: apps),
                    newest.end)
        }
        return ranked
            .sorted { ($0.candidate.score, $0.end) > ($1.candidate.score, $1.end) }
            .prefix(limit).map(\.candidate)
    }

    /// The category most of the entries are filed under; a tie goes to the
    /// one used most recently.
    private static func usualWorkType(of entries: [NameHistoryEntry]) -> WorkType {
        let counts = Dictionary(grouping: entries, by: \.workType).mapValues(\.count)
        let most = counts.values.max() ?? 0
        return entries.filter { counts[$0.workType] == most }.max { $0.end < $1.end }!.workType
    }
}
