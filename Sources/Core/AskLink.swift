import Foundation

/// Why a place is listed under an answer.
enum AskSourceRole: String, Equatable {
    case totals = "Totals", bestDay = "Most focused day", bestWeek = "Most focused week",
         bestMonth = "Most focused month", longestSession = "Longest session", session = "Session",
         compared = "Compared", bestHours = "Best hours", appTime = "App time"
}

/// A place in the app one fact came from, and what following it opens.
struct AskLink: Hashable {
    enum Target: Hashable {
        case day(Date)
        case session(thread: UUID, day: Date)
        case period(HistoryPlace)
        /// History at the top: all time, the last 30 days.
        case history
    }

    let target: Target
    /// `Tue 15 Sep`, `Thesis · Tue 15 Sep`, `5 Oct – 11 Oct`, `August 2026`, `All time`.
    let label: String
    let role: AskSourceRole
    /// The session's own name, which is what an answer says to name it.
    var sessionName: String? = nil
}

/// One line of an answer's sources. `mention` is where the answer first names
/// the place, as character offsets into the answer; nil for a place the answer
/// did not name but a lookup rests on.
struct AskSource: Equatable {
    let link: AskLink
    let mention: Range<Int>?
}
