import Foundation
import FoundationModels

/// Ask Daybook v2 part 2: a session's stretches. The `sessionDetail` lookup
/// lists sessions with each working stretch's start and end, its note and its
/// battery reading, read from the Story's day projection and the metadata the
/// session report reads. Mon 13 Nov in the shared fixture holds Thesis in two
/// stretches of one thread (the first with a note and battery readings, the
/// second on external power), Parser and Email.
enum AskSessionDetailChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session's stretches are listed with their times, note and power", stretchesListed),
        ("A session says what it lacks, and a note reads as its first line", noReadingNoNote),
        ("A day lists its sessions newest first", dayNewestFirst),
        ("A stretch across midnight is split at midnight", acrossMidnight),
        ("The running session reads as running", runningSession),
        ("More than ten sessions end with how many there were", moreThanTen),
        ("No session says so", noSession),
        ("A long history stays within 1 KB", longHistory),
        ("Session detail lists the period and each session", linksListPeriodAndSessions),
        ("The catalogue's seventh entry is sessionDetail, with part 1's period guide", catalogueEntry),
    ]

    private static let monday = AskRange.day(year: 2023, month: 11, day: 13)
    /// What a session with neither a note nor a battery reading ends with: silence read as a yes.
    private static let lacks = " \u{00B7} no note \u{00B7} no battery reading"

    private static func span(_ record: SessionRecord) -> DateInterval { DateInterval(start: record.start, end: record.end) }

    // MARK: - Stretches

    private static func stretchesListed() -> [String] {
        AskDataFixture.with { f, problems in
            let a = f.store.powerSummary(for: [f.thesisA.id], interval: span(f.thesisA))?.headline
            let b = f.store.powerSummary(for: [f.thesisB.id], interval: span(f.thesisB))?.headline
            guard let a, let b else { problems.append("the fixture has no power lines: \(String(describing: a)), \(String(describing: b))"); return }
            let want = "Thesis \u{00B7} Mon 13 Nov \u{00B7} 2 stretches: from 9:00am to 10:40am, 1h 40m, \(a), "
                + "note \u{201C}chapter three, fixed citations\u{201D}; from 11:05am to 12:25pm, 1h 20m, \(b)"
            let got = f.store.askLookup(.sessionDetail(monday, words: "thesis"))
            expect(got == want, "Thesis reads “\(got)”, not “\(want)”", &problems)
            expect(a != b, "the two stretches read the same power line: \(a)", &problems)
        }
    }

    private static func noReadingNoNote() -> [String] {
        AskDataFixture.with { f, problems in
            let want = "Parser \u{00B7} Mon 13 Nov \u{00B7} 1 stretch: from 2:00pm to 3:12pm, 1h 12m"
            let got = f.store.askLookup(.sessionDetail(monday, words: "parser"))
            expect(got == want + lacks, "Parser reads “\(got)”, not “\(want + lacks)”", &problems)
            guard case .saved = f.metadata.saveNote("first line\nsecond line", for: f.parser.id) else {
                problems.append("the note was not saved"); return
            }
            let noted = f.store.askLookup(.sessionDetail(monday, words: "parser"))
            expect(noted == want + ", note \u{201C}first line\u{201D} \u{00B7} no battery reading",
                   "a two-line note reads “\(noted)”", &problems)
        }
    }

    private static func dayNewestFirst() -> [String] {
        AskDataFixture.with { f, problems in
            let lines = f.store.askLookup(.sessionDetail(monday, words: nil)).split(separator: "\n").map(String.init)
            expect(lines.count == 3, "Mon 13 Nov lists \(lines.count) sessions", &problems)
            expect(lines.first?.hasPrefix("Email \u{00B7} Mon 13 Nov \u{00B7} 1 stretch: from 4:30pm to 5:00pm, 30m") == true,
                   "the newest reads “\(lines.first ?? "")”", &problems)
            expect(lines.dropFirst().first?.hasPrefix("Parser") == true && lines.last?.hasPrefix("Thesis") == true,
                   "the order is \(lines.map { $0.prefix(7) })", &problems)
        }
    }

    private static func acrossMidnight() -> [String] {
        AskDataFixture.with { f, problems in
            let late = SessionRecord(name: "Late", workType: .deepWork, start: f.moment(1, 23), end: f.moment(0, 1),
                                     workSeconds: 7_200)
            guard f.engine.archive.append(late) == nil else { problems.append("Late was not saved"); return }
            let tuesday = f.store.askLookup(.sessionDetail(.day(year: 2023, month: 11, day: 14), words: "late"))
            expect(tuesday == "Late \u{00B7} Tue 14 Nov \u{00B7} 1 stretch: from 11:00pm until midnight, 1h" + lacks, "Tue reads “\(tuesday)”", &problems)
            let today = f.store.askLookup(.sessionDetail(.today, words: "late"))
            expect(today == "Late \u{00B7} Wed 15 Nov \u{00B7} 1 stretch: from midnight to 1:00am, 1h" + lacks, "today reads “\(today)”", &problems)
        }
    }

    private static func runningSession() -> [String] {
        AskDataFixture.with { f, problems in
            f.engine.start(workType: .deepWork, intent: "Review")
            f.clock.advance(13 * 60)
            let want = "Review \u{00B7} Wed 15 Nov \u{00B7} 1 stretch: running from 9:13am, 13m so far" + lacks
            let all = f.store.askLookup(.sessionDetail(.today, words: nil))
            expect(all == want, "today reads “\(all)”", &problems)
            let named = f.store.askLookup(.sessionDetail(.thisWeek, words: "review"))
            expect(named == want, "this week's Review reads “\(named)”", &problems)
            let other = f.store.askLookup(.sessionDetail(.today, words: "thesis"))
            expect(other == "No sessions match \u{201C}thesis\u{201D} today.", "Thesis today reads “\(other)”", &problems)
            f.clock.advance(60)
            let later = f.store.askLookup(.sessionDetail(.today, words: nil))
            expect(later.hasSuffix("running from 9:13am, 14m so far" + lacks), "a minute later it reads “\(later)”", &problems)
        }
    }

    // MARK: - Counts and caps

    private static func moreThanTen() -> [String] {
        AskDataFixture.with { f, problems in
            // Twelve sessions in last week (6-12 Nov), two on each of the five earliest days.
            for index in 0..<12 {
                let back = 9 - index % 7
                let hour = index < 7 ? 16 : 18
                let record = SessionRecord(name: "Sprint", workType: .deepWork, start: f.moment(back, hour),
                                           end: f.moment(back, hour + 1), workSeconds: 3_600)
                guard f.engine.archive.append(record) == nil else { problems.append("a record was not saved"); return }
            }
            let text = f.store.askLookup(.sessionDetail(.lastWeek, words: "sprint"))
            let lines = text.split(separator: "\n").filter { $0.hasPrefix("Sprint") }
            expect(lines.count == 10, "\(lines.count) sessions are listed", &problems)
            expect(text.hasSuffix("\nNewest 10 of 12."), "the text ends “\(text.suffix(30))”", &problems)
            expect(lines.first?.contains("Sun 12 Nov") == true, "the newest is “\(lines.first ?? "")”", &problems)
            expect(!text.contains("Mon 6 Nov"), "the oldest day is listed: \(text)", &problems)
            expect(text.utf8.count <= 1_024, "the text is \(text.utf8.count) bytes", &problems)
        }
    }

    private static func noSession() -> [String] {
        AskDataFixture.with { f, problems in
            let none = f.store.askLookup(.sessionDetail(monday, words: "nothing"))
            expect(none == "No sessions match \u{201C}nothing\u{201D} on Mon 13 Nov 2023.", "no match reads “\(none)”", &problems)
            let empty = f.store.askLookup(.sessionDetail(.day(year: 2023, month: 11, day: 5), words: nil))
            expect(empty == "No sessions recorded on Sun 5 Nov 2023.", "an empty day reads “\(empty)”", &problems)
            let future = f.store.askLookupResult(.sessionDetail(.day(year: 2023, month: 11, day: 20), words: nil))
            expect(future.links.isEmpty && future.text.hasSuffix("is still to come."), "a later day says: \(future.text)", &problems)
        }
    }

    private static func longHistory() -> [String] {
        AskLookupChecks.withFixture(extraThesisDays: 1_000) { f, problems in
            let text = f.store.askLookup(.sessionDetail(.allTime, words: nil))
            expect(text.utf8.count <= 1_024, "the text is \(text.utf8.count) bytes", &problems)
            // Parser, Thesis on Mon 13 Nov and on Tue 17 Oct, and a Thesis on each extra day.
            expect(text.hasSuffix("\nNewest 10 of 1003."), "the text ends “\(text.suffix(30))”", &problems)
            expect(text.hasPrefix("Parser \u{00B7} Tue 14 Nov \u{00B7}"), "it begins “\(text.prefix(40))”", &problems)
        }
    }

    // MARK: - Sources and catalogue

    private static func linksListPeriodAndSessions() -> [String] {
        AskDataFixture.with { f, problems in
            let day = f.calendar.startOfDay(for: f.moment(2, 12))
            let one = f.store.askLookupResult(.sessionDetail(monday, words: "thesis")).links
            let want = [AskLink(target: .day(day), label: "Mon 13 Nov", role: .stretches),
                        AskLink(target: .session(thread: f.thesisA.threadID, day: day), label: "Thesis \u{00B7} Mon 13 Nov",
                                role: .stretches, sessionName: "Thesis")]
            expect(one == want, "Thesis on Mon 13 Nov lists \(one)", &problems)
            let week = f.store.askLookupResult(.sessionDetail(.thisWeek, words: nil)).links
            expect(week.first?.label == "13 Nov \u{2013} 19 Nov" && week.allSatisfy { $0.role == .stretches },
                   "this week anchors on \(String(describing: week.first))", &problems)
            expect(week.dropFirst().map(\.label) == ["Thesis \u{00B7} Tue 14 Nov", "Email \u{00B7} Mon 13 Nov",
                                                      "Parser \u{00B7} Mon 13 Nov", "Thesis \u{00B7} Mon 13 Nov"],
                   "this week lists \(week.map(\.label))", &problems)
            expect(AskRequest.sessionDetail(.thisWeek, words: "thesis").provenance
                   == "session detail matching \u{201C}thesis\u{201D} (this week)", "provenance with words differs", &problems)
            expect(AskRequest.sessionDetail(.thisWeek, words: nil).provenance == "session detail (this week)",
                   "provenance without words differs", &problems)
        }
    }

    private static func catalogueEntry() -> [String] {
        var problems: [String] = []
        let description = "Returns the detail of sessions in a period: each working stretch with its start and end, "
            + "its note and its battery reading, such as whether the Mac was plugged in."
        let guide = AskLookups.all[0].spec.parameters[0].description
        let words = AskParameter(name: "words",
                                 description: "Words from the session's name, such as thesis; leave out for every session",
                                 required: false)
        let want = AskLookupSpec(name: "sessionDetail", description: description,
                                 parameters: [AskParameter(name: "range", description: guide, required: true), words])
        expect(AskLookups.all.count >= 7 && AskLookups.all[6].spec == want,
               "the seventh entry is \(String(describing: AskLookups.all.dropFirst(6).first?.spec))", &problems)
        expect(AskLookups.named("sessionDetail")?.spec == want, "named(sessionDetail) is not that entry", &problems)
        guard let entry = AskLookups.named("sessionDetail") else { return problems }
        let asked = entry.read(["range": "yesterday", "words": " thesis "]) { AskRange(rawValue: $0) }
        expect(asked == .request(.sessionDetail(.yesterday, words: "thesis")), "words read as \(asked)", &problems)
        let bare = entry.read(["range": "yesterday"]) { AskRange(rawValue: $0) }
        expect(bare == .request(.sessionDetail(.yesterday, words: nil)), "no words read as \(bare)", &problems)
        let refused = entry.read(["range": "31 february"]) { AskRange(rawValue: $0) }
        expect(refused == .refusal(AskFacts.noSuchPeriod("31 february")), "a bad date reads as \(refused)", &problems)
        if #available(macOS 26, *) {
            guard let schema = try? AskOnDeviceTool.schema(for: entry.spec),
                  let expected = try? AskOnDeviceTool.schema(for: want) else {
                problems.append("the schema could not be built"); return problems
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let got = (try? encoder.encode(schema)).flatMap { String(data: $0, encoding: .utf8) }
            let wanted = (try? encoder.encode(expected)).flatMap { String(data: $0, encoding: .utf8) }
            expect(got != nil && got == wanted, "the schema is \(got ?? "unencodable"), not \(wanted ?? "?")", &problems)
        }
        return problems
    }
}
