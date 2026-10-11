import Foundation

/// A review note on screen is checked against its facts again when the
/// session archive or the session metadata moves, and not when only app use
/// does; and a session carried over from the night before is not said to
/// begin at midnight. Uses the Ask fixture of `ReviewNoteStoreChecks`: the
/// clock on Wed 15 Nov 2023 at 9:13, Parser on Tue 14 Nov.
enum ReviewNoteFreshnessChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A rename or an edited session note moves the evidence a note on screen is checked against",
         evidenceMovesOnEdit),
        ("A session stopping moves that evidence, and a session running does not", evidenceAroundASession),
        ("Recording app use leaves that evidence as it was", evidenceIgnoresAppUse),
        ("A session carried over from the night before is not said to begin at midnight", carriedOverMidnight),
    ]

    private typealias Checks = ReviewNoteWriterChecks
    private typealias Fixture = AskLookupChecks.Fixture

    /// A moment on the day `back` days before the clock's day.
    private static func moment(_ f: Fixture, back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = f.calendar.date(byAdding: .day, value: -back, to: f.calendar.startOfDay(for: f.clock.value))!
        return f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func evidenceMovesOnEdit() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let tuesday = Checks.day(f, back: 1)
            guard let parser = Checks.session(on: tuesday, f), let record = parser.recordIDs.first else {
                problems.append("Tuesday has no session")
                return
            }
            let before = f.store.noteEvidence
            expect(f.store.renameSession(parser, to: "Compiler"), "the rename was refused", &problems)
            let renamed = f.store.noteEvidence
            expect(renamed != before, "a rename left the evidence as it was: \(renamed)", &problems)

            f.store.beginNoteEditing(for: record)
            f.store.setNoteDraft("Tokeniser first", for: record)
            expect(f.store.saveNote(for: record), "the session note was not saved", &problems)
            expect(f.store.noteEvidence != renamed, "an edited session note left the evidence as it was", &problems)
        }
    }

    private static func evidenceAroundASession() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.engine.start(workType: .deepWork, intent: "Review")
            let started = f.store.noteEvidence
            f.clock.advance(20 * 60)
            expect(f.store.noteEvidence == started, "a session running for 20 minutes moved the evidence", &problems)
            expect(f.engine.stop(), "the session did not stop", &problems)
            expect(f.store.noteEvidence != started, "a session stopping left the evidence as it was", &problems)
        }
    }

    private static func evidenceIgnoresAppUse() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            guard let usage = f.store.usage else { problems.append("the fixture has no app use"); return }
            let before = f.store.noteEvidence
            let usageRevision = f.store.evidenceRevision.usage
            let recorded = usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                                        start: moment(f, back: 1, 9), end: moment(f, back: 1, 9, 30)))
            expect(recorded && f.store.evidenceRevision.usage != usageRevision,
                   "app use was not recorded, so this proves nothing", &problems)
            expect(f.store.noteEvidence == before, "recording app use moved the evidence", &problems)
        }
    }

    /// Night shift runs from 10 pm on Fri 10 Nov to 2 am on Sat 11 Nov. The
    /// day's session is clipped to its start, so Saturday's facts hold a
    /// session beginning at midnight that began the night before.
    private static func carriedOverMidnight() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let start = moment(f, back: 5, 22)
            let night = SessionRecord(name: "Night shift", workType: .deepWork, start: start,
                                      end: start.addingTimeInterval(4 * 3_600), workSeconds: 4 * 3_600)
            guard f.engine.archive.append(night) == nil else { problems.append("the session was not saved"); return }
            guard let friday = f.store.noteFacts(for: f.store.notePlace(forDayContaining: moment(f, back: 5, 12)))?.text,
                  let saturday = f.store.noteFacts(for: f.store.notePlace(forDayContaining: moment(f, back: 4, 12)))?.text
            else { problems.append("a day has no facts"); return }

            expect(friday.contains("Night shift at 10:00 pm, 2h") && friday.contains("Focus began at 10:00 pm with Night shift"),
                   "Friday's facts are “\(friday)”", &problems)
            expect(!saturday.contains("12:00 am"), "Saturday's facts name 12:00 am: “\(saturday)”", &problems)
            expect(saturday.contains("Focus carried on past midnight with Night shift"),
                   "Saturday's facts do not say focus carried on: “\(saturday)”", &problems)
            expect(saturday.contains("Night shift from before midnight, 2h"),
                   "Saturday's session list does not say it began before midnight: “\(saturday)”", &problems)
            expect(saturday.contains("Longest stretch: 2h in Night shift, from before midnight"),
                   "Saturday's longest stretch does not say it began before midnight: “\(saturday)”", &problems)
        }
    }
}
