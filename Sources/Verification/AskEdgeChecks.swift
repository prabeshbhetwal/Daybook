import Foundation

/// Two edges of the clip Ask puts on a session: one paused all through the
/// range has no work there and is not found by it, and an app counts as used
/// in a session by its use inside the part of the session in the range, not
/// by the session overlapping it.
enum AskEdgeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's word searches drop a session paused all through the range, and keep an instant inside it",
         pausedSessionIsNotFound),
        ("Ask's app time counts a session by the app's use inside the range, paused or not",
         { appUseIsClippedToRange() + appUseInPausedSession() }),
    ]

    private static let notes = "com.example.Notes"

    /// "Zeta" from 23:00 yesterday to 01:00 today, paused until 00:30: half an
    /// hour of work, all of it today.
    private static func pausedSessionIsNotFound() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let today = f.calendar.startOfDay(for: f.clock.value)
            let yesterday = f.calendar.date(byAdding: .day, value: -1, to: today)!
            func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
                f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            let paused = SessionRecord(name: "Zeta", workType: .deepWork, start: at(yesterday, 23),
                                       end: at(today, 1), workSeconds: 1_800,
                                       pausedSpans: [DateInterval(start: at(yesterday, 23), end: at(today, 0, 30))])
            // No length: it belongs to the instant it happened.
            let instant = SessionRecord(name: "Blip", workType: .deepWork, start: at(today, 8), end: at(today, 8),
                                        workSeconds: 300)
            guard f.engine.archive.append(paused) == nil, f.engine.archive.append(instant) == nil else {
                problems.append("could not save the sessions")
                return
            }

            let cases: [(AskRequest, String)] = [
                (.focusTotals(.yesterday, words: "zeta"), "No sessions match “zeta” yesterday."),
                (.findSessions(words: "zeta", .yesterday), "No sessions match “zeta” yesterday."),
                (.focusTotals(.today, words: "zeta"), "Sessions matching “zeta” today: 30m over 1 session on 1 day."),
                (.findSessions(words: "zeta", .today), "Wed 15 Nov · Zeta · 30m"),
                (.focusTotals(.today, words: "blip"), "Sessions matching “blip” today: 5m over 1 session on 1 day."),
                (.focusTotals(.yesterday, words: "blip"), "No sessions match “blip” yesterday."),
            ]
            for (request, want) in cases {
                let got = f.store.askLookup(request)
                expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
            }
        }
    }

    /// Notes in front 23:10 to 23:40 yesterday, inside "Night" (23:00 to
    /// 01:00), and 10 minutes this morning outside any session. Today holds
    /// only the session's first hour past midnight, where Notes was not used.
    private static func appUseIsClippedToRange() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let now = f.clock.value
            let today = f.calendar.startOfDay(for: now)
            let yesterday = f.calendar.date(byAdding: .day, value: -1, to: today)!
            func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
                f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            let night = SessionRecord(name: "Night", workType: .deepWork, start: at(yesterday, 23),
                                      end: at(today, 1), workSeconds: 7_200)
            guard f.engine.archive.append(night) == nil, let tracker = f.store.tracker else {
                problems.append("could not save the overnight session")
                return
            }
            func stretch(from start: Date, minutes: Double, app: String, name: String) {
                f.clock.value = start
                tracker.appActivated(bundleID: app, name: name)
                f.clock.advance(minutes * 60)
            }
            stretch(from: at(yesterday, 23, 10), minutes: 30, app: notes, name: "Notes")
            stretch(from: at(yesterday, 23, 40), minutes: 1, app: "com.example.Mail", name: "Mail")
            stretch(from: at(today, 8, 40), minutes: 10, app: notes, name: "Notes")
            stretch(from: at(today, 8, 50), minutes: 1, app: "com.example.Mail", name: "Mail")
            f.clock.value = now

            let cases: [(AskRequest, String)] = [
                (.appTime(.today, app: "notes"), "Notes today: 10m in front; used in 0 sessions."),
                (.appTime(.yesterday, app: "notes"), "Notes yesterday: 30m in front; used in 1 session."),
            ]
            for (request, want) in cases {
                let got = f.store.askLookup(request)
                expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
            }
        }
    }

    /// "Night" from 23:00 yesterday to 01:00 today, paused from midnight: no
    /// work today, yet Notes was in front 00:10 to 00:40 inside it, so it
    /// counts for today as History's app filter lists it. Yesterday's use is
    /// 10 minutes at noon; the 30 minutes past midnight are not yesterday's.
    private static func appUseInPausedSession() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let now = f.clock.value
            let today = f.calendar.startOfDay(for: now)
            let yesterday = f.calendar.date(byAdding: .day, value: -1, to: today)!
            func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
                f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            let night = SessionRecord(name: "Night", workType: .deepWork, start: at(yesterday, 23),
                                      end: at(today, 1), workSeconds: 3_600,
                                      pausedSpans: [DateInterval(start: at(today, 0), end: at(today, 1))])
            guard f.engine.archive.append(night) == nil, let tracker = f.store.tracker else {
                problems.append("could not save the overnight session")
                return
            }
            func stretch(from start: Date, minutes: Double, app: String, name: String) {
                f.clock.value = start
                tracker.appActivated(bundleID: app, name: name)
                f.clock.advance(minutes * 60)
            }
            stretch(from: at(yesterday, 12), minutes: 10, app: notes, name: "Notes")
            stretch(from: at(yesterday, 12, 10), minutes: 1, app: "com.example.Mail", name: "Mail")
            stretch(from: at(today, 0, 10), minutes: 30, app: notes, name: "Notes")
            stretch(from: at(today, 0, 40), minutes: 1, app: "com.example.Mail", name: "Mail")
            stretch(from: at(today, 8, 40), minutes: 10, app: notes, name: "Notes")
            stretch(from: at(today, 8, 50), minutes: 1, app: "com.example.Mail", name: "Mail")
            f.clock.value = now

            let cases: [(AskRequest, String)] = [
                (.appTime(.today, app: "notes"), "Notes today: 40m in front; used in 1 session."),
                (.appTime(.yesterday, app: "notes"), "Notes yesterday: 10m in front; used in 0 sessions."),
            ]
            for (request, want) in cases {
                let got = f.store.askLookup(request)
                expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
            }
        }
    }
}
