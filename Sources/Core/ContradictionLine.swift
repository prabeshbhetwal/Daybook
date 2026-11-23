import Foundation

/// The one factual line a session's report adds when the label and the time part ways (spec section 6):
/// "Mostly media: 34 of 48 minutes". The label is kept and nothing is asked. Only a category the person
/// or a rule chose is held against the evidence; Daybook's own guess is not contradicted by itself.
enum ContradictionLine {
    /// The purposes a category stands for, the smallest honest mapping (plan ruling B7). Nil for one that
    /// stands for none: a break is rest, whatever the screen showed.
    static func purposes(for category: WorkType) -> Set<AppPurpose>? {
        let focused = Set(AppPurpose.allCases.filter(\.isFocused))
        switch category {
        case .deepWork: return focused
        case .meetings: return [.communication]
        case .admin: return [.utility, .communication]
        case .learning: return focused.union([.research, .media])
        case .breakTime: return nil
        default: return focused   // a category of the person's own
        }
    }

    /// `credited` is a stored shape's credited seconds by purpose. Under a minute of it there is nothing
    /// worth a line, and no minutes to count. A category that counts while watching (`countsWhileWatching`,
    /// as Meetings and Learning do) also stands for media: the film it holds is the work, not a contradiction.
    static func text(category: WorkType, source: DecisionSource, credited: [String: TimeInterval],
                     countsWhileWatching: Bool) -> String? {
        guard source == .user || source == .rule, var stands = purposes(for: category) else { return nil }
        if countsWhileWatching { stands.insert(.media) }
        var seconds: [AppPurpose: TimeInterval] = [:]
        for (key, value) in credited where value > 0 {
            if let purpose = AppPurpose(rawValue: key) { seconds[purpose, default: 0] += value }
        }
        let total = seconds.values.reduce(0, +)
        guard total >= ActivityConstants.minCreditedSeconds,
              stands.reduce(0, { $0 + (seconds[$1] ?? 0) }) / total < ActivityConstants.contradictionLow,
              let other = seconds.first(where: {
                  !stands.contains($0.key) && $0.value / total > ActivityConstants.contradictionHigh
              }) else { return nil }
        // The name the phase strip gives the activity, with only its first letter set down for the sentence.
        let minutes = Int((total / 60).rounded())
        return "Mostly \(other.key.inSentence): "
            + "\(Int((other.value / 60).rounded())) of \(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}
