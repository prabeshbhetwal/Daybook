import AppKit
import Foundation

/// Every date and time on screen follows the person's locale and their 12 or
/// 24-hour clock. Each check hands the formatter a fixed `Locale`, so none
/// depends on the Mac it runs on, and each fails against the old fixed
/// "h:mm a" and en_AU patterns.
enum LocaleFormatChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A 24-hour locale shows 13:05 with no am or pm", twentyFourHourClock),
        ("A 12-hour locale shows lowercase am or pm, kept with its time", twelveHourClock),
        ("The 12 or 24-hour setting beats the locale's own clock", settingBeatsLocale),
        ("A range keeps each time whole on either clock", rangesStayWhole),
        ("Chart hours read 9am on a 12-hour clock and the locale's hour on a 24-hour one", hourLabels),
        ("History's hour windows follow the clock", historyHours),
        ("Day and month labels are in the locale's language and order", dayLabels),
        ("A span of days names the month once only where the day comes first", dateRanges),
        ("The widest time range is built by the formatter, so its width follows the clock", widestRanges),
        ("Hours from a thousand are grouped and a rate keeps the locale's decimal mark", numberText),
        ("A change of locale reaches formatters already built", cacheFollowsLocale),
    ]

    /// The locale the other checks pin their expected text to.
    static let australian = Locale(identifier: "en_AU")
    private static let american = Locale(identifier: "en_US")
    private static let british = Locale(identifier: "en_GB")
    private static let german = Locale(identifier: "de_DE")
    /// A 12-hour locale on a 24-hour clock, and the other way round.
    private static let american24 = Locale(identifier: "en_US@hours=h23")
    private static let british12 = Locale(identifier: "en_GB@hours=h12")
    private static let nbsp = "\u{00A0}"

    /// Read in UTC so a fixture is the same wall time in every zone.
    private static func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func twentyFourHourClock() -> [String] {
        var problems: [String] = []
        let afternoon = date(11, 11, 13, 5)
        for locale in [british, german, american24] {
            let text = DateFormats.clockTime(afternoon, locale: locale, in: .gmt)
            expect(text == "13:05", "\(locale.identifier) should read 13:05, got \(text)", &problems)
        }
        let morning = DateFormats.clockTime(date(11, 11, 9, 13), locale: british, in: .gmt)
        expect(morning == "09:13", "a 24-hour morning keeps its leading zero, got \(morning)", &problems)
        return problems
    }

    private static func twelveHourClock() -> [String] {
        var problems: [String] = []
        for locale in [australian, american, british12] {
            let text = DateFormats.clockTime(date(11, 11, 13, 5), locale: locale, in: .gmt)
            expect(text == "1:05\(nbsp)pm", "\(locale.identifier) should read 1:05 pm, got \(text)", &problems)
        }
        let morning = DateFormats.clockTime(date(11, 11, 9, 13), locale: american, in: .gmt)
        expect(morning == "9:13\(nbsp)am", "a 12-hour morning reads 9:13 am without a leading zero, got \(morning)", &problems)
        return problems
    }

    private static func settingBeatsLocale() -> [String] {
        var problems: [String] = []
        // Daybook asks for the hour with "j", which each locale resolves to its own clock.
        let on24: String = DateFormats.localized("jmm", locale: american24, in: .gmt).dateFormat
        let on12: String = DateFormats.localized("jmm", locale: british12, in: .gmt).dateFormat
        expect(!DateFormats.hasDayPeriod(on24), "a 24-hour setting on en_US should drop the day period, got \(on24)", &problems)
        expect(DateFormats.hasDayPeriod(on12), "a 12-hour setting on en_GB should add a day period, got \(on12)", &problems)
        expect(!DateFormats.hasDayPeriod("HH:mm 'at' h") && DateFormats.hasDayPeriod("h:mm a"),
               "a quoted letter is not a day period", &problems)
        return problems
    }

    private static func rangesStayWhole() -> [String] {
        var problems: [String] = []
        let start = date(11, 11, 13, 5), end = date(11, 11, 14, 10)
        for locale in [australian, american, british, american24] {
            let range = DateFormats.clockRange(start, end, locale: locale, in: .gmt)
            let times = range.components(separatedBy: " – ")
            expect(times.count == 2, "\(locale.identifier) should join two times with a spaced en dash, got \(range)", &problems)
            for time in times {
                expect(!time.contains(" "), "\(locale.identifier) left a breakable space inside \"\(time)\" of \(range)", &problems)
            }
        }
        let twelve = DateFormats.clockRange(start, end, locale: australian, in: .gmt)
        expect(twelve == "1:05\(nbsp)pm – 2:10\(nbsp)pm", "12-hour range read \(twelve)", &problems)
        let twentyFour = DateFormats.clockRange(start, end, locale: british, in: .gmt)
        expect(twentyFour == "13:05 – 14:10", "24-hour range read \(twentyFour)", &problems)
        return problems
    }

    private static func hourLabels() -> [String] {
        var problems: [String] = []
        let cases: [(Locale, Int, String)] = [
            (australian, 9, "9am"), (australian, 12, "12pm"), (australian, 0, "12am"), (australian, 13, "1pm"),
            (american, 9, "9am"), (british12, 15, "3pm"),
            (british, 13, "13"), (british, 9, "09"), (german, 13, "13\u{00A0}Uhr"), (american24, 13, "13"),
        ]
        for (locale, hour, expected) in cases {
            let text = DateFormats.hourLabel(date(11, 11, hour), locale: locale, in: .gmt)
            expect(text == expected, "\(locale.identifier) hour \(hour) should read \(expected), got \(text)", &problems)
        }
        return problems
    }

    private static func historyHours() -> [String] {
        var problems: [String] = []
        let twelve = HistoryHours.span(from: 9, locale: australian)
        expect(twelve == "9\(nbsp)am – 11\(nbsp)am", "a 12-hour window read \(twelve)", &problems)
        expect(HistoryHours.label(0, locale: australian) == "12\(nbsp)am" && HistoryHours.label(13, locale: american) == "1\(nbsp)pm",
               "midnight and 1 pm read \(HistoryHours.label(0, locale: australian)) and \(HistoryHours.label(13, locale: american))",
               &problems)
        let twentyFour = HistoryHours.span(from: 9, locale: british)
        expect(twentyFour == "09:00 – 11:00", "a 24-hour window read \(twentyFour)", &problems)
        expect(HistoryHours.label(13, locale: american24) == "13:00", "1 pm on a 24-hour clock read \(HistoryHours.label(13, locale: american24))", &problems)
        return problems
    }

    private static func dayLabels() -> [String] {
        var problems: [String] = []
        let wednesday = date(11, 11, 12), march = date(3, 11, 12)
        // Functions that read in the system zone get a date that is the 11th there too.
        let localCalendar = Calendar(identifier: .gregorian)
        let local = localCalendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
        func holds(_ text: String, _ parts: [String], in order: Bool = false, absent: [String] = [], _ what: String) {
            for part in parts where !text.contains(part) { problems.append("\(what) should hold \(part), got \(text)") }
            for part in absent where text.contains(part) { problems.append("\(what) should not hold \(part), got \(text)") }
            if order, let first = text.range(of: parts[0]), let second = text.range(of: parts[1]), first.lowerBound > second.lowerBound {
                problems.append("\(what) puts \(parts[1]) before \(parts[0]): \(text)")
            }
        }
        // Weekday first; the day before the month in Australia, after it in America.
        holds(DateFormats.shortDay(wednesday, locale: australian, in: .gmt), ["11", "Nov"], in: true, absent: ["Mi"], "an Australian short day")
        holds(DateFormats.shortDay(wednesday, locale: american, in: .gmt), ["Nov", "11"], in: true, "an American short day")
        holds(DateFormats.shortDay(wednesday, locale: german, in: .gmt), ["Mi", "11", "Nov"], absent: ["Wed"], "a German short day")
        holds(DateFormats.longDate(wednesday, locale: australian, in: .gmt), ["Wednesday", "11", "November"], "an Australian long date")
        holds(DateFormats.longDate(wednesday, locale: german, in: .gmt), ["Mittwoch", "11", "November"], absent: ["Wednesday"], "a German long date")
        holds(HistoryDayHeader.title(local, isToday: false, locale: german), ["Mi", "Nov"], absent: ["Wed"], "History's German day title")
        holds(DateFormats.fullDay(local, now: local, locale: german), ["Mittwoch", "November"], absent: ["2026"], "a German day this year")
        let exact: [(String, String)] = [
            (DateFormats.monthYear(march, locale: german, in: .gmt), "März 2026"),
            (DateFormats.monthYear(march, locale: australian, in: .gmt), "March 2026"),
            (HistoryMonthHeader.title(march, in: .gmt, locale: german), "März 2026"),
        ]
        for (text, expected) in exact { expect(text == expected, "expected \(expected), got \(text)", &problems) }
        let later = localCalendar.date(byAdding: .year, value: 1, to: local)!
        holds(DateFormats.fullDay(local, now: later, locale: australian), ["Wednesday", "November", "2026"], "a day in another year")
        return problems
    }

    private static func dateRanges() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = date(11, 11)
        let cases: [(Locale, Date, Date, String)] = [
            (australian, date(8, 24), date(8, 30), "24 – 30 Aug"),
            (australian, date(8, 31), date(9, 6), "31 Aug – 6 Sep"),
            (american, date(8, 24), date(8, 30), "Aug 24 – Aug 30"),
            (australian, date(12, 28), date(12, 30), "28 – 30 Dec"),
        ]
        for (locale, start, end, expected) in cases {
            let text = DateFormats.dateRange(start, end, now: now, calendar: calendar, locale: locale)
            expect(text == expected, "\(locale.identifier) range expected \(expected), got \(text)", &problems)
        }
        return problems
    }

    private static func widestRanges() -> [String] {
        var problems: [String] = []
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        }
        let twelve = DateFormats.widestClockRanges(locale: australian)
        let twentyFour = DateFormats.widestClockRanges(locale: british)
        expect(twelve == ["12:00\(nbsp)am – 12:00\(nbsp)am", "12:00\(nbsp)pm – 12:00\(nbsp)pm", "11:59\(nbsp)pm – 11:59\(nbsp)pm"],
               "the 12-hour widest strings read \(twelve)", &problems)
        expect(twentyFour == ["00:00 – 00:00", "12:00 – 12:00", "23:59 – 23:59"],
               "the 24-hour widest strings read \(twentyFour)", &problems)
        let wide = twelve.map(width).max() ?? 0, narrow = twentyFour.map(width).max() ?? 0
        expect(narrow > 0 && narrow < wide, "a 24-hour column should be narrower than a 12-hour one: \(narrow) against \(wide)", &problems)
        // Each reserved string is a range the formatter really draws.
        for text in twelve + twentyFour {
            expect(text.components(separatedBy: " – ").count == 2, "\(text) is not a range", &problems)
        }
        return problems
    }

    private static func numberText() -> [String] {
        var problems: [String] = []
        let cases: [(Int, Locale, String)] = [
            (1_234, american, "1,234"), (1_234, german, "1.234"), (999, german, "999"), (12_345, australian, "12,345"),
        ]
        for (hours, locale, expected) in cases {
            let text = DurationText.hoursText(hours, locale: locale)
            expect(text == expected, "\(hours) hours in \(locale.identifier) expected \(expected), got \(text)", &problems)
        }
        let long = DurationText.compact(1_234 * 3_600 + 5 * 60)
        expect(long == "\(DurationText.hoursText(1_234))h 5m" && long != "1234h 5m",
               "a thousand hours should be grouped, got \(long)", &problems)
        expect(DurationText.compact(5 * 3_600 + 25 * 60) == "5h 25m" && DurationText.compact(3_600) == "1h",
               "the compact form below a thousand hours changed", &problems)
        expect(DurationText.precise(1_234 * 3_600 + 5 * 60) == "\(DurationText.hoursText(1_234))h 5m",
               "precise text should group too, got \(DurationText.precise(1_234 * 3_600 + 5 * 60))", &problems)
        let spoken = DurationText.spoken(in: "1,234h 5m and 1.234h 5m and 15m")
        expect(spoken == "1,234 hours 5 minutes and 1.234 hours 5 minutes and 15 minutes",
               "grouped hours should be spoken whole, got \(spoken)", &problems)
        expect(DurationText.oneDecimal(1.5, locale: american) == "1.5" && DurationText.oneDecimal(1.5, locale: german) == "1,5",
               "a rate should use its locale's mark, got \(DurationText.oneDecimal(1.5, locale: german))", &problems)
        return problems
    }

    private static func cacheFollowsLocale() -> [String] {
        var problems: [String] = []
        let before = DateFormats.localized("jmm", locale: .current)
        expect(DateFormats.localized("jmm", locale: .current) === before, "an unchanged locale should reuse its formatter", &problems)
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        expect(DateFormats.localized("jmm", locale: .current) !== before,
               "a changed locale should build its formatters again", &problems)
        return problems
    }
}
