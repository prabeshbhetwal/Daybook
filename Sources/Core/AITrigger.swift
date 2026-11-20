import Foundation

/// Whether an ended session is worth one question to the on-device model (Phase C, rulings C2 and C3). Pure:
/// the caller says what the record, its shape and the remembered corrections are.
enum AITrigger {
    /// Asked about: an automatic session whose category is still the app's own guess, with a stored shape
    /// that has a fingerprint, at least `modelMinCounted` of counted time, no remembered correction for its
    /// kind (the person's earlier word beats the model's), and evidence that is unclear. A session the
    /// person or a rule filed, or one that began by hand, already carries the person's choice.
    static func shouldAsk(record: SessionRecord, shape: SessionActivityShape, hasCorrection: Bool) -> Bool {
        guard !hasCorrection, record.effectiveOrigin == .automatic, record.effectiveCategorySource == .builtIn,
              shape.fingerprint != nil, shape.countedSeconds >= AILabelConstants.modelMinCounted else { return false }
        let total = shape.credited.values.reduce(0, +)
        // Nothing credited is nothing to describe: the question would be empty.
        guard total > 0 else { return false }
        let ranked = Self.ranked(shape.credited)
        let top = ranked[0]
        let next = ranked.count > 1 ? ranked[1].value : 0
        return isUnclear(topShare: top.value / total, lead: (top.value - next) / total,
                         topIsFocused: AppPurpose(rawValue: top.key)?.isFocused ?? false)
    }

    /// A shape's credited activities, largest first and ties by name, so the same shape always names the same
    /// top purpose: the trigger, the question and a new label's look all read it.
    static func ranked(_ credited: [String: TimeInterval]) -> [(key: String, value: TimeInterval)] {
        credited.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    }

    /// The rule on the numbers alone: shares of credited seconds, 0 to 1. A top that is not a focused
    /// purpose asks because the deterministic fallback then gives no category. shortcut: over shares of
    /// whole purposes a top at `modelShare` always leads by 0.20 or more, so the lead only bites if the
    /// two constants move; it is kept because the spec names both.
    static func isUnclear(topShare: Double, lead: Double, topIsFocused: Bool) -> Bool {
        topShare < AILabelConstants.modelShare || lead < AILabelConstants.modelMargin || !topIsFocused
    }
}
