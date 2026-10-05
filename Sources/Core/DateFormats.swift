import Foundation

/// Fixed date patterns, each built once. Labels on screen are drawn every
/// render, often per row or per bar, and a new `DateFormatter` for each is the
/// most expensive thing about them. Shared instances are never mutated after
/// they are returned.
enum DateFormats {
    /// A pattern in the `en_AU` locale.
    static func australian(_ format: String) -> DateFormatter {
        cached(format, locale: Locale(identifier: "en_AU"))
    }

    /// A pattern in the `en_AU` locale, read in `timeZone`: a period worked
    /// out in one calendar is named in that calendar's zone.
    static func australian(_ format: String, in timeZone: TimeZone) -> DateFormatter {
        cached(format, locale: Locale(identifier: "en_AU"), timeZone: timeZone)
    }

    /// A pattern in the user's own locale.
    static func local(_ format: String) -> DateFormatter {
        cached(format, locale: nil)
    }

    /// "11:25 am" with its one space unbreakable. Breaking there left a line
    /// ending "11:25" and the next beginning "am – 11:31 am", which reads as a
    /// different time entirely.
    static func clockTime(_ date: Date) -> String {
        local("h:mm a").string(from: date).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// "9am", "12pm": an hour on a chart axis.
    static func hourLabel(_ date: Date) -> String {
        local("ha").string(from: date).lowercased()
    }

    /// "8:44 am – 3:56 pm", each time kept whole by `clockTime`.
    static func clockRange(_ start: Date, _ end: Date) -> String {
        "\(clockTime(start)) – \(clockTime(end))"
    }

    private static func cached(_ format: String, locale: Locale?, timeZone: TimeZone? = nil) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(locale?.identifier ?? "")|\(timeZone?.identifier ?? "")|\(format)"
        if let hit = formatters[key] { return hit }
        let formatter = DateFormatter()
        if let locale { formatter.locale = locale }
        if let timeZone { formatter.timeZone = timeZone }
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }
    private static var formatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()
}
