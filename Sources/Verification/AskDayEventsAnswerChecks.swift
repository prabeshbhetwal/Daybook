import Foundation

/// Ask Daybook v2 part 2, after the final review: the `dayEvents` lines for
/// answers about time away. A receipt's name is the session that was running,
/// never what the user said; their words survive only as the name of the
/// break they recorded. The answers come from the engine (`AskDataFixture.answer`),
/// as an app launch hands them over, because a hand-built receipt once held
/// the user's words where the engine puts the session.
enum AskDayEventsAnswerChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An answer about time away never names its session, so it is never taken for the answer", sessionIsNotTheAnswer),
        ("A break the user named keeps its name, and a missing reason is said", labelAndSilence),
        ("The name a break has now is the one Ask tells", renamedBreakIsTold),
    ]

    private static let dot = "\u{00B7}"
    private static let sunday = AskRange.day(year: 2023, month: 11, day: 12)
    private static let monday = AskRange.day(year: 2023, month: 11, day: 13)

    /// The receipts of the shared fixture came from the engine as the session
    /// they were asked in ("Thesis", "Email") and a break named "Coffee".
    private static func sessionIsNotTheAnswer() -> [String] {
        AskDataFixture.with { f, problems in
            for receipt in f.receipts {
                expect(["Thesis", "Email"].contains(receipt.name), "the engine's receipt names “\(receipt.name)”", &problems)
            }
            let text = f.store.askLookup(.dayEvents(monday))
            expect(!text.contains("answered \u{201C}"), "an answer is worded as a quoted name: \(text)", &problems)
            expect(!text.contains("answered: Thesis") && !text.contains("answered: Email"),
                   "a session is worded as the answer: \(text)", &problems)
            // The away lines name no session, so the model cannot take one for what was said.
            let awayLines = text.split(separator: "\n").filter { $0.contains("away") }
            expect(awayLines.count == 2, "the away lines are \(awayLines.count): \(text)", &problems)
            for line in awayLines {
                expect(!line.contains("during"), "an away line names a session: \(line)", &problems)
                for receipt in f.receipts {
                    expect(!line.contains(receipt.name), "an away line names “\(receipt.name)”: \(line)", &problems)
                }
            }
            expect(text.contains("away \(dot) answered: Counted as focus, 25m"),
                   "the counted answer lost its line: \(text)", &problems)
            expect(text.contains("away \(dot) answered: Recorded as a break"),
                   "the break answer lost its line: \(text)", &problems)
            // The break the answer made is told by the answer, not twice.
            expect(f.store.askLookup(.dayEvents(.thisWeek)).contains("Mon 13 Nov \(dot) 2 breaks, 1h \(dot) 2 answers"),
                   "the answer's break is listed as a break", &problems)
        }
    }

    private static func labelAndSilence() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.dayEvents(monday))
            expect(text.contains("Recorded as a break \(dot) named \u{201C}Coffee\u{201D}"),
                   "the break's name is lost: \(text)", &problems)
            expect(text.contains("Counted as focus, 25m \(dot) no reason recorded"),
                   "a counted answer does not say it has no reason: \(text)", &problems)
            guard let plain = AskDataFixture.answer(.tookBreak, "Review", .deepWork, begun: f.moment(3, 14),
                                                    away: f.moment(3, 14, 30), back: f.moment(3, 14, 55)),
                  let left = AskDataFixture.answer(.continueSession, "", .deepWork, begun: f.moment(3, 16),
                                                   away: f.moment(3, 16, 30), back: f.moment(3, 16, 55)),
                  f.add(plain), f.add(left) else { problems.append("could not add the answers"); return }
            let day = f.store.askLookup(.dayEvents(sunday))
            // A break with no name of its own is "Break": no label, so no reason.
            expect(day.contains("from 2:30pm to 2:55pm \(dot) away \(dot) answered: "
                                + "Recorded as a break \(dot) no reason recorded"), "an unnamed break says: \(day)", &problems)
            // Named or not, the away line never carries the session.
            expect(day.contains("from 4:30pm to 4:55pm \(dot) away \(dot) answered: Left uncounted \(dot) no reason recorded"),
                   "an unnamed session says: \(day)", &problems)
            expect(!day.contains("named"), "a label was made up: \(day)", &problems)
        }
    }

    private static func renamedBreakIsTold() -> [String] {
        AskDataFixture.with { f, problems in
            // The Story names the break its record carries now, so a later rename is what Ask tells.
            guard let coffee = f.engine.awayDecisions.first(where: { $0.insertedRecord?.id == f.coffee.id }),
                  f.store.canNameBreak(for: coffee), f.store.nameBreak(for: coffee, to: "walk") else {
                problems.append("could not rename the answer's break"); return
            }
            let text = f.store.askLookup(.dayEvents(monday))
            expect(text.contains("named \u{201C}Walk\u{201D}") && !text.contains("Coffee"),
                   "the renamed break reads: \(text)", &problems)
        }
    }
}
