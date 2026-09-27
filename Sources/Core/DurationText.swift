import Foundation

/// Compact, factual duration text shared by Core prose and Design surfaces.
/// Keeping this Foundation-only avoids the old drift where Core rounded a real
/// app observation down to `0m` while SwiftUI showed something else.
enum DurationText {
    static func precise(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        guard seconds < TimeInterval(Int.max) else { return "—" }
        if seconds > 0, seconds < 1 { return "<1s" }

        let total = Int(seconds.rounded(.down))
        if total < 60 { return "\(total)s" }
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        guard hours > 0 else { return "\(minutes)m" }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }

    /// `2h 15m`, `4h`, `15m`, `0m`: whole minutes, for sentences and tiles.
    static func compact(_ seconds: TimeInterval) -> String {
        guard let total = wholeSeconds(seconds) else { return "—" }
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        guard hours > 0 else { return "\(minutes)m" }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }

    /// Whole seconds, negatives as zero; nil when the value cannot be an `Int`.
    /// `Int(_:)` traps on NaN, infinity and anything past `Int.max`, and a
    /// corrupted or hand-edited archive can decode a finite value that large.
    static func wholeSeconds(_ seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, abs(seconds) < TimeInterval(Int.max) else { return nil }
        return max(0, Int(seconds))
    }
}
