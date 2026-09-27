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

    /// A pattern in the user's own locale.
    static func local(_ format: String) -> DateFormatter {
        cached(format, locale: nil)
    }

    private static func cached(_ format: String, locale: Locale?) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(locale?.identifier ?? "")|\(format)"
        if let hit = formatters[key] { return hit }
        let formatter = DateFormatter()
        if let locale { formatter.locale = locale }
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }
    private static var formatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()
}
