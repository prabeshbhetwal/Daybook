import Foundation

/// Ask Daybook v2 part 2, after the final review: how `sessionDetail` names
/// and times a session. A session without a name is told by its category, as
/// the Story and Ask's session lists tell it, and only the day slice that
/// holds now is a stretch still running.
enum AskSessionDetailNameChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session without a name is told by its category, in the text and in its source", unnamedSession),
        ("A session running since last night ended at midnight on yesterday", runningSinceLastNight),
    ]

    private static let lacks = " \u{00B7} no note \u{00B7} no battery reading"

    private static func unnamedSession() -> [String] {
        AskDataFixture.with { f, problems in
            let record = SessionRecord(name: "", workType: .deepWork, start: f.moment(2, 18), end: f.moment(2, 19),
                                       workSeconds: 3_600)
            guard f.engine.archive.append(record) == nil else { problems.append("the session was not saved"); return }
            let result = f.store.askLookupResult(.sessionDetail(.day(year: 2023, month: 11, day: 13), words: nil))
            expect(result.text.hasPrefix("Deep work \u{00B7} Mon 13 Nov \u{00B7} 1 stretch: from 6:00pm to 7:00pm, 1h" + lacks),
                   "the unnamed session reads: \(result.text)", &problems)
            expect(!result.text.contains("\n \u{00B7}") && !result.text.hasPrefix(" \u{00B7}"),
                   "a line begins with no name: \(result.text)", &problems)
            expect(result.links.contains { $0.label == "Deep work \u{00B7} Mon 13 Nov" },
                   "its source has no title: \(result.links.map(\.label))", &problems)
        }
    }

    private static func runningSinceLastNight() -> [String] {
        AskDataFixture.with { f, problems in
            // Moments are read from the clock, so both are taken before it moves.
            let (night, small) = (f.moment(1, 23), f.moment(0, 1))
            f.clock.value = night
            f.engine.start(workType: .deepWork, intent: "Night")
            f.clock.value = small
            let yesterday = f.store.askLookup(.sessionDetail(.yesterday, words: "night"))
            expect(yesterday == "Night \u{00B7} Tue 14 Nov \u{00B7} 1 stretch: from 11:00pm until midnight, 1h" + lacks,
                   "yesterday reads “\(yesterday)”", &problems)
            let today = f.store.askLookup(.sessionDetail(.today, words: "night"))
            expect(today == "Night \u{00B7} Wed 15 Nov \u{00B7} 1 stretch: running from midnight, 1h so far" + lacks,
                   "today reads “\(today)”", &problems)
        }
    }
}
