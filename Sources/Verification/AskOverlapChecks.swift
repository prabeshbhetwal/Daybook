import Foundation

/// A session that crosses midnight is searched by the part of it inside the
/// range asked about, not by the day it began or by all of it: asking about
/// today finds last night's session with the hour that falls today.
enum AskOverlapChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's word searches clip a session that crosses midnight to the range asked about",
         overnightSessionIsClipped),
    ]

    /// The Ask fixture with "Thesis" saved from 23:00 yesterday to 01:00 today,
    /// two hours of work: an hour on each day, built from the store's calendar.
    private static func overnightSessionIsClipped() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let today = f.calendar.startOfDay(for: f.clock.value)
            let yesterday = f.calendar.date(byAdding: .day, value: -1, to: today)!
            func at(_ day: Date, _ hour: Int) -> Date {
                f.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            }
            let overnight = SessionRecord(name: "Thesis", workType: .deepWork, start: at(yesterday, 23),
                                          end: at(today, 1), workSeconds: 7_200)
            guard f.engine.archive.append(overnight) == nil else {
                problems.append("could not save the overnight session")
                return
            }

            let cases: [(AskRequest, String)] = [
                (.focusTotals(.today, words: "thesis"),
                 "Sessions matching “thesis” today (Wed 15 Nov): 1h over 1 session on 1 day."),
                (.focusTotals(.yesterday, words: "thesis"),
                 "Sessions matching “thesis” yesterday (Tue 14 Nov): 1h over 1 session on 1 day."),
                // Monday's hour, and the overnight session's two hours over Tuesday and Wednesday.
                (.focusTotals(.thisWeek, words: "thesis"),
                 "Sessions matching “thesis” this week (13 Nov – 19 Nov): 3h over 2 sessions on 3 days, an average of 1h on each day "
                 + "with focus; the longest finished session was Thesis on Tue 14 Nov, 2h."),
                // The line is dated by a day inside the range, not the day the session began,
                // and timed from where it enters the range.
                (.findSessions(words: "thesis", .today), "Wed 15 Nov · 12:00am · Thesis · 1h"),
                (.findSessions(words: "thesis", .yesterday), "Tue 14 Nov · 11:00pm · Thesis · 1h"),
            ]
            for (request, want) in cases {
                let got = f.store.askLookup(request)
                expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
            }
        }
    }
}
