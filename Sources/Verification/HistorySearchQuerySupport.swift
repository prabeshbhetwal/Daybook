import Foundation

/// The fixtures and the row comparison the search-box checks share
/// (`HistorySearchQueryChecks`): "now" is `SelfTest.base` and every span is
/// built through the period calendar.
extension HistorySearchQueryChecks {
    static var periods: Calendar { SelfTest.gregorian.forPeriods }
    static let apps = ["com.apple.Notes": "Notes", "com.apple.dt.Xcode": "Xcode",
                       "com.microsoft.VSCode": "Visual Studio Code"]

    struct Row {
        var span: DateInterval?
        var weekdays: Set<Int>?
        var min: TimeInterval?
        var max: TimeInterval?
        var app: String?
        var type: WorkType?
        var leftover = ""
        var labels: [String] = []
        var noOverlap = false
    }

    static func midnight(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar = periods) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day))!)
    }

    /// `[start, end)` from two dates of 2023, or of the years given.
    static func span(_ m1: Int, _ d1: Int, _ m2: Int, _ d2: Int, y1: Int = 2023, y2: Int? = nil,
                       in calendar: Calendar = periods) -> DateInterval {
        DateInterval(start: midnight(y1, m1, d1, in: calendar), end: midnight(y2 ?? y1, m2, d2, in: calendar))
    }

    static func verify(_ text: String, _ row: Row, now: Date = SelfTest.base, calendar: Calendar = periods,
                       types: [WorkType] = [], _ problems: inout [String]) {
        let got = SearchQuery.parse(text, now: now, calendar: calendar, apps: apps, categories: types)
        let tag = "\"\(text)\""
        expect(got.span == row.span, "\(tag): span \(String(describing: got.span)), not \(String(describing: row.span))",
               &problems)
        expect(got.weekdays == row.weekdays, "\(tag): weekdays \(String(describing: got.weekdays)), not \(String(describing: row.weekdays))", &problems)
        expect(got.minLength == row.min, "\(tag): minLength \(String(describing: got.minLength)), not \(String(describing: row.min))", &problems)
        expect(got.maxLength == row.max, "\(tag): maxLength \(String(describing: got.maxLength)), not \(String(describing: row.max))", &problems)
        expect(got.appBundleID == row.app, "\(tag): app \(String(describing: got.appBundleID)), not \(String(describing: row.app))", &problems)
        expect(got.workType == row.type, "\(tag): category \(String(describing: got.workType?.rawValue))", &problems)
        expect(got.leftover == row.leftover, "\(tag): leftover \"\(got.leftover)\", not \"\(row.leftover)\"", &problems)
        expect(got.phrases.map(\.label) == row.labels, "\(tag): chips \(got.phrases.map(\.label)), not \(row.labels)", &problems)
        expect(got.noOverlap == row.noOverlap, "\(tag): noOverlap \(got.noOverlap), not \(row.noOverlap)", &problems)
    }
}
