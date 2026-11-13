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
        return minutes > 0 ? "\(hoursText(hours))h \(minutes)m" : "\(hoursText(hours))h"
    }

    /// `2h 15m`, `4h`, `15m`, `0m`: whole minutes, for sentences and tiles.
    /// From a thousand hours the hours are grouped as the locale does:
    /// `1,234h 5m`.
    static func compact(_ seconds: TimeInterval) -> String {
        guard let total = wholeSeconds(seconds) else { return "—" }
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        guard hours > 0 else { return "\(minutes)m" }
        return minutes > 0 ? "\(hoursText(hours))h \(minutes)m" : "\(hoursText(hours))h"
    }

    /// A count of hours, grouped from a thousand (`1,234`; `1.234` in German).
    /// Below that it is plain digits, so a time and its minutes are never
    /// written in two numeral systems.
    static func hoursText(_ hours: Int, locale: Locale = .current) -> String {
        hours < 1_000 ? "\(hours)" : hours.formatted(.number.locale(locale))
    }

    /// A rate to one decimal place in the locale's own separator: `1.5`, `1,5`.
    /// `String(format:)` writes a full stop whatever the locale.
    static func oneDecimal(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// The same text with each compact duration in words, for VoiceOver:
    /// `2h 15m` becomes `2 hours 15 minutes`, `1m` becomes `1 minute` and
    /// `<1s` becomes `under a second`. The eye reads `15m` as minutes; speech
    /// reads it as fifteen metres. Numbers inside words or times are left.
    /// Compiled once: every accessibility label on the story went through
    /// this, and each call was compiling the pattern again. Hours of a thousand
    /// or more carry their locale's grouping (`1,234h`, `1.234h`).
    private static let compactDuration = try? NSRegularExpression(
        pattern: #"(?<![\w.:])(\d{1,3}(?:[,.  ’]\d{3})+|\d+)([hms])(?!\w)"#)

    static func spoken(in text: String) -> String {
        let text = text.replacingOccurrences(of: "<1s", with: "under a second")
        let units: [Character: (one: String, many: String)] = [
            "h": ("hour", "hours"), "m": ("minute", "minutes"), "s": ("second", "seconds")
        ]
        guard let regex = compactDuration else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text),
                  let digits = Range(match.range(at: 1), in: text),
                  let unit = Range(match.range(at: 2), in: text),
                  let words = units[text[unit].first ?? " "] else { continue }
            result += text[cursor..<whole.lowerBound]
            result += "\(text[digits]) \(text[digits] == "1" ? words.one : words.many)"
            cursor = whole.upperBound
        }
        return result + text[cursor...]
    }

    /// Whole seconds, negatives as zero; nil when the value cannot be an `Int`.
    /// `Int(_:)` traps on NaN, infinity and anything past `Int.max`, and a
    /// corrupted or hand-edited archive can decode a finite value that large.
    static func wholeSeconds(_ seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, abs(seconds) < TimeInterval(Int.max) else { return nil }
        return max(0, Int(seconds))
    }

    /// `25%`, or `25 per cent` for speech, from a share where 1 is the whole;
    /// `—` when the share cannot be a whole per cent. Shares are worked out
    /// from stored durations, and malformed ones make them NaN, infinite or
    /// far past `Int`, so they go through the same guard as seconds.
    static func percent(_ share: Double, spoken: Bool = false) -> String {
        guard let whole = wholeSeconds((share * 100).rounded()) else { return "—" }
        return spoken ? "\(whole) per cent" : "\(whole)%"
    }
}
