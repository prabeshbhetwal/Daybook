import Foundation

/// Date patterns, each built once. Labels on screen are drawn every render,
/// often per row or per bar, and a new `DateFormatter` for each is the most
/// expensive thing about them. Shared instances are never mutated after they
/// are returned.
///
/// Two families. Text the person reads goes through `localized` templates, so
/// it follows their locale and their 12 or 24-hour clock; every such function
/// takes a `locale` (the user's own by default) so a check can pin one. Text
/// that is data (what the Ask model reads, what a search matches against, what
/// is parsed back) stays on `australian`, whatever the person's region.
enum DateFormats {
    /// A pattern in the `en_AU` locale. For data only; display uses `localized`.
    static func australian(_ format: String) -> DateFormatter {
        cached("p|en_AU||\(format)") { $0.locale = Locale(identifier: "en_AU"); $0.dateFormat = format }
    }

    /// A pattern in the `en_AU` locale, read in `timeZone`: a period worked
    /// out in one calendar is named in that calendar's zone. For data only.
    static func australian(_ format: String, in timeZone: TimeZone) -> DateFormatter {
        cached("p|en_AU|\(timeZone.identifier)|\(format)") {
            $0.locale = Locale(identifier: "en_AU")
            $0.timeZone = timeZone
            $0.dateFormat = format
        }
    }

    /// A fixed pattern in the user's own locale. Prefer `localized`: a pattern
    /// such as "h:mm a" fixes the 12-hour clock for everyone.
    static func local(_ format: String) -> DateFormatter {
        cached("p||\(format)") { $0.dateFormat = format }
    }

    /// A template ("jmm", "EEEdMMM") laid out the way `locale` writes it, in
    /// `timeZone` (the system's when nil). "j" asks for the hour in whichever
    /// clock the locale, or the person's 24-hour setting, uses. Dates are
    /// always read in the Gregorian calendar: every day, week and month the
    /// app works out is Gregorian, and a Hijri or Buddhist label on one would
    /// name a different day.
    static func localized(_ template: String, locale: Locale = .current,
                          in timeZone: TimeZone? = nil) -> DateFormatter {
        // `Locale.current` differs from `Locale(identifier:)` of the same name
        // by carrying the person's settings, so it gets a key of its own.
        let who = locale == Locale.current ? "current" : locale.identifier
        return cached("t|\(who)|\(timeZone?.identifier ?? "")|\(template)") {
            $0.locale = locale
            $0.calendar = Calendar(identifier: .gregorian)
            if let timeZone { $0.timeZone = timeZone }
            $0.setLocalizedDateFormatFromTemplate(template)
        }
    }

    // MARK: Clock

    /// Whether `pattern` shows am or pm: an unquoted `a`, `b` or `B`.
    static func hasDayPeriod(_ pattern: String) -> Bool {
        var quoted = false
        for character in pattern {
            if character == "'" { quoted.toggle() } else if !quoted, "abB".contains(character) { return true }
        }
        return false
    }

    /// "11:25 am" on a 12-hour clock, "11:25" or "23:25" on a 24-hour one. The
    /// house style on a 12-hour clock is lowercase, and every time keeps its
    /// spaces unbreakable: breaking one left a line ending "11:25" and the next
    /// beginning "am – 11:31 am", which reads as a different time entirely.
    static func clockTime(_ date: Date, locale: Locale = .current, in timeZone: TimeZone? = nil) -> String {
        clock(localized("jmm", locale: locale, in: timeZone), date)
    }

    /// "9am", "12pm" on a 12-hour clock: an hour on a chart axis. A 24-hour
    /// clock writes the hour as the locale does ("13", "13 Uhr").
    static func hourLabel(_ date: Date, locale: Locale = .current, in timeZone: TimeZone? = nil) -> String {
        let formatter = localized("j", locale: locale, in: timeZone)
        let text = clock(formatter, date)
        guard hasDayPeriod(formatter.dateFormat) else { return text }
        let tight = text.replacingOccurrences(of: "\u{00A0}", with: "")
        return tight.range(of: #"^\d{1,2}[ap]m$"#, options: .regularExpression) == nil ? text : tight
    }

    /// A clock hour said on its own, for a window: "9 am", "1 pm", or "09:00"
    /// on a 24-hour clock, where a bare "09" would not read as a time.
    static func wholeHour(_ hour: Int, locale: Locale = .current) -> String {
        // A fixed day read in UTC, so no daylight-saving change can move it.
        let date = Date(timeIntervalSinceReferenceDate: TimeInterval(((hour % 24) + 24) % 24) * 3_600)
        let hourOnly = localized("j", locale: locale, in: .gmt)
        return clock(hasDayPeriod(hourOnly.dateFormat) ? hourOnly : localized("jmm", locale: locale, in: .gmt), date)
    }

    /// "8:44 am – 3:56 pm", each time kept whole by `clockTime`.
    static func clockRange(_ start: Date, _ end: Date, locale: Locale = .current,
                           in timeZone: TimeZone? = nil) -> String {
        "\(clockTime(start, locale: locale, in: timeZone)) – \(clockTime(end, locale: locale, in: timeZone))"
    }

    /// The strings a `clockRange` is widest as, for a column that must be as
    /// wide as its widest value. Built by the formatter itself, so the width
    /// follows the clock: "12:00 pm – 12:00 pm" is wider than "12:00 – 12:00".
    static func widestClockRanges(locale: Locale = .current) -> [String] {
        var widest: [String] = []
        // Midnight, noon and the last minute of the day.
        for minute in [0, 12 * 60, 23 * 60 + 59] {
            let time = Date(timeIntervalSinceReferenceDate: TimeInterval(minute) * 60)
            let range = clockRange(time, time, locale: locale, in: .gmt)
            if !widest.contains(range) { widest.append(range) }
        }
        return widest
    }

    // MARK: Days

    /// "Wed, 11 Nov": a day in a list or on a chart.
    static func shortDay(_ date: Date, locale: Locale = .current, in timeZone: TimeZone? = nil) -> String {
        localized("EEEdMMM", locale: locale, in: timeZone).string(from: date)
    }

    /// "Saturday 22 August", for a title that names the day.
    static func longDate(_ date: Date, locale: Locale = .current, in timeZone: TimeZone? = nil) -> String {
        localized("EEEEdMMMM", locale: locale, in: timeZone).string(from: date)
    }

    /// "August 2026": a month and the year it is in.
    static func monthYear(_ date: Date, locale: Locale = .current, in timeZone: TimeZone? = nil) -> String {
        localized("MMMMy", locale: locale, in: timeZone).string(from: date)
    }

    /// "22 Aug": a date with no weekday or year.
    static func dayMonth(_ date: Date, locale: Locale = .current, in timeZone: TimeZone? = nil) -> String {
        localized("dMMM", locale: locale, in: timeZone).string(from: date)
    }

    /// "Saturday 22 August", with the year added once it is not `now`'s year.
    static func fullDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                        locale: Locale = .current) -> String {
        let thisYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return localized(thisYear ? "EEEEdMMMM" : "EEEEdMMMMy", locale: locale).string(from: date)
    }

    /// A moment with its day: "Saturday 22 August, 9:13 am".
    static func datedClockTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                               locale: Locale = .current) -> String {
        "\(fullDay(date, now: now, calendar: calendar, locale: locale)), \(clockTime(date, locale: locale))"
    }

    /// A span with its day, "Saturday 22 August, 9:13 am – 10:20 am", and with
    /// both days when it crosses midnight: "Saturday 22 August, 11:30 pm –
    /// Sunday 23 August, 12:40 am". Clock times alone leave a reader, or a
    /// screen reader, guessing which day they belong to. `joiner` is "to" when
    /// the line is spoken.
    static func datedClockRange(_ start: Date, _ end: Date, joiner: String = "–",
                                now: Date = Date(), calendar: Calendar = .current,
                                locale: Locale = .current) -> String {
        let opening = datedClockTime(start, now: now, calendar: calendar, locale: locale)
        if calendar.isDate(start, inSameDayAs: end) { return "\(opening) \(joiner) \(clockTime(end, locale: locale))" }
        return "\(opening) \(joiner) \(datedClockTime(end, now: now, calendar: calendar, locale: locale))"
    }

    /// A span of days the way the chrome writes one: `24 – 30 Aug`,
    /// `31 Aug – 6 Sep`, and the year only when it is not this year —
    /// `28 Dec 2025 – 3 Jan 2026`. A locale that puts the month first ("Aug 24")
    /// names it at both ends: "Aug 24 – Aug 30".
    static func dateRange(_ start: Date, _ end: Date, now: Date = Date(),
                          calendar: Calendar = .current, locale: Locale = .current) -> String {
        func text(_ template: String, _ date: Date) -> String {
            localized(template, locale: locale, in: calendar.timeZone).string(from: date)
        }
        let thisYear = calendar.component(.year, from: now)
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        if startYear != endYear { return "\(text("dMMMy", start)) – \(text("dMMMy", end))" }
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let first = sameMonth && dayComesFirst(locale) ? text("d", start) : text("dMMM", start)
        return "\(first) – \(text(endYear == thisYear ? "dMMM" : "dMMMy", end))"
    }

    /// Whether `locale` writes the day before the month in a short date.
    private static func dayComesFirst(_ locale: Locale) -> Bool {
        let pattern: String = localized("dMMM", locale: locale).dateFormat
        guard let day = pattern.firstIndex(of: "d"), let month = pattern.firstIndex(of: "M") else { return false }
        return day < month
    }

    // MARK: Cache

    /// One clock string: spaces unbreakable, lowercase if it has am or pm.
    private static func clock(_ formatter: DateFormatter, _ date: Date) -> String {
        let text = formatter.string(from: date)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "\u{202F}", with: "\u{00A0}")
        return hasDayPeriod(formatter.dateFormat) ? text.lowercased() : text
    }

    private static func cached(_ key: String, _ configure: (DateFormatter) -> Void) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        _ = localeWatcher
        if let hit = formatters[key] { return hit }
        let formatter = DateFormatter()
        configure(formatter)
        formatters[key] = formatter
        return formatter
    }
    private static var formatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    /// A formatter keeps the locale it was built with, so a person who changes
    /// region or switches to a 24-hour clock while Daybook runs would keep
    /// seeing the old one until it restarted.
    private static let localeWatcher = NotificationCenter.default.addObserver(
        forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil) { _ in
        lock.lock()
        formatters.removeAll()
        lock.unlock()
    }
}
