import Foundation

/// The places Ask Daybook's lookups name beside their text, so an answer can
/// list where its figures came from. Labels use the forms the lookups already
/// write (`askDay`, `askLabel`), and a place is the one History opens.
extension SessionStore {
    /// The period a lookup was asked about: a day, week, month or year is a
    /// place in History; all time and the last 30 days are not, so they open
    /// History itself, labelled with the range's title and its dates.
    func askPeriodLink(_ range: AskRange, role: AskSourceRole) -> AskLink {
        // The last 30 days sits at month level in History's breakdown but is no month.
        guard let level = range.level, range != .last30Days else {
            let title = range.title.prefix(1).uppercased() + range.title.dropFirst()
            return AskLink(target: .history, label: askDates(range).map { "\(title) (\($0))" } ?? title, role: role)
        }
        return askPlaceLink(HistoryPlace(level: level, span: askInterval(range)), role: role)
    }

    /// A History row's place: a day opens as the day, a longer row as a period.
    func askPlaceLink(_ place: HistoryPlace, role: AskSourceRole) -> AskLink {
        AskLink(target: place.level == .day ? .day(place.start) : .period(place), label: askLabel(place), role: role)
    }

    /// A session on the day a lookup dates it by: `Thesis · Tue 15 Sep`.
    func askSessionLink(thread: UUID, name: String, day: Date, role: AskSourceRole) -> AskLink {
        AskLink(target: .session(thread: thread, day: day), label: "\(name) \u{00B7} \(askDay(day))", role: role,
                sessionName: name)
    }

    /// Why a best day, week or month is listed.
    func askBestRole(_ unit: HistoryLevel) -> AskSourceRole {
        switch unit {
        case .day: return .bestDay
        case .week: return .bestWeek
        case .month, .year: return .bestMonth  // no lookup names a best year
        }
    }
}
