import Foundation

/// What `NameSuggester` offers: the model (here a `responder`, never the live
/// one) is asked once per session and only the audited answer is shown. The
/// fixture's "now" is 9:13 am on Wed 15 Nov 2023. Two sessions are unnamed:
/// A today 7:00–7:30 in Xcode and B yesterday 14:00–14:45 in Xcode and
/// Terminal, and "Daybook" (Xcode and Terminal half and half) is an earlier
/// name, so each has it as candidate 1. A name typed on A (Xcode only) then
/// trails Daybook for B by more than the margin.
enum NameSuggesterChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An earlier name is offered with its lead", offersEarlier),
        ("A fresh name that fails the audit offers nothing and the next session is tried", auditFallthrough),
        ("Each session is asked once; a redraw does not ask again", askedOnce),
        ("Nothing is asked with the switch off or without evidence; a note alone is asked with no candidates", notAsked),
        ("A timeout or error offers nothing and does not wedge the suggester", timeoutAndError),
        ("A session named on its card while the model answers is not offered", namedMeanwhile),
        ("After Name it and Undo the session is not offered again this run", undoNotReoffered),
        ("Keep as is moves to the next session", keepNext),
        ("The note line the model reads is one line of at most 200 characters", noteLine),
        ("The model's answer maps to a choice, and anything unreadable to none", answerMapping),
        ("Name it or Keep as is on a session named since is not applied", staleOffer),
    ]

    private typealias Checks = NameSuggestionStoreChecks

    private static func offersEarlier() -> [String] {
        pair { f, a, _, problems in
            let calls = Calls()
            let s = make(f, calls)
            run(s)
            expect(s.current?.name == "Daybook" && s.current?.session.threadID == a,
                   "offered \(String(describing: s.current)), not Daybook for today's session", &problems)
            expect(s.current?.lead == "this morning's 30m session", "the lead reads “\(s.current?.lead ?? "nil")”", &problems)
            expect(calls.facts.count == 1, "asked \(calls.facts.count) sessions, not only the newest", &problems)
            expect(calls.facts.first?.candidates.map(\.name) == ["Daybook"], "candidates \(String(describing: calls.facts.first?.candidates))", &problems)
            expect(!s.isAsking, "still asking", &problems)
        }
    }

    private static func auditFallthrough() -> [String] {
        pair { f, _, b, problems in
            let calls = Calls()
            let s = make(f, calls) { n in n == 1 ? .fresh("Sprint 12") : .earlier(1) }
            run(s)
            expect(s.current?.session.threadID == b && s.current?.name == "Daybook",
                   "after a name with a digit, offered \(String(describing: s.current)), not Daybook for yesterday's", &problems)
            expect(calls.facts.count == 2, "asked \(calls.facts.count) times, not once per session", &problems)
        }
    }

    private static func askedOnce() -> [String] {
        pair { f, _, _, problems in
            let calls = Calls()
            let s = make(f, calls) { _ in .none }
            run(s)
            for _ in 0..<3 { run(s) }
            expect(calls.facts.count == 2 && s.current == nil,
                   "asked \(calls.facts.count) times for two sessions, offering \(String(describing: s.current))", &problems)

            // Two redraws before the first answer still ask one at a time, once each.
            let twice = Calls()
            let t = make(f, twice) { _ in .none }
            t.refresh()
            t.refresh()
            settle(t)
            expect(twice.facts.count == 2, "two quick refreshes asked \(twice.facts.count) times", &problems)

            // A cached name is served without asking again.
            let named = Calls()
            let u = make(f, named)
            for _ in 0..<3 { run(u) }
            expect(named.facts.count == 1 && u.current?.name == "Daybook",
                   "a cached name asked \(named.facts.count) times", &problems)
        }
    }

    private static func notAsked() -> [String] {
        var problems = pair { f, _, _, problems in
            let calls = Calls()
            let s = make(f, calls)
            f.persistence.useAppleIntelligence = false
            run(s)
            expect(!s.isUsable && calls.facts.isEmpty && s.current == nil,
                   "with the switch off: usable \(s.isUsable), asked \(calls.facts.count), offered \(String(describing: s.current))",
                   &problems)
            f.persistence.useAppleIntelligence = true
            run(s)
            expect(s.isUsable && s.current?.name == "Daybook", "with the switch back on nothing was offered", &problems)
        }
        let bare = UUID()
        problems += Checks.withFixture(records: { days in [Checks.record(days.at(0, 7), days.at(0, 7, 30), thread: bare)] },
                                       usage: { days in [Checks.app("Finder", days.at(0, 7, 5), 5)] }) { f, _, problems in
            let calls = Calls()
            let s = make(f, calls)
            run(s)
            expect(calls.facts.isEmpty && s.current == nil, "a session with no evidence was asked", &problems)
        }
        let noted = UUID()
        problems += Checks.withFixture(records: { days in [Checks.record(days.at(0, 7), days.at(0, 7, 30), thread: noted)] }) { f, _, problems in
            guard let session = Checks.target(f, noted) else { return problems.append("the session is not offered") }
            _ = f.metadata.saveNote("planning", for: session.recordIDs[0])
            let calls = Calls()
            let s = make(f, calls) { _ in .none }
            run(s)
            expect(calls.facts.count == 1 && calls.facts[0].candidates.isEmpty && calls.facts[0].text.contains("Note: “planning”"),
                   "a note alone: asked \(calls.facts.count) times with \(calls.facts.first?.candidates.count ?? -1) candidates", &problems)
        }
        return problems
    }

    private static func timeoutAndError() -> [String] {
        pair { f, a, _, problems in
            let calls = Calls()
            // The newest session's reply comes after the timeout; the next one's is an error.
            let s = make(f, calls) { n in
                if n == 1 { await pause(0.5); return .earlier(1) }
                throw Refused()
            }
            s.timeout = .milliseconds(150)
            run(s)
            expect(calls.facts.count == 2 && s.current == nil && !s.isAsking,
                   "after a timeout and an error: asked \(calls.facts.count), offered \(String(describing: s.current)), asking \(s.isAsking)",
                   &problems)
            _ = InstalledAppCatalog.turnRunLoop(until: { s.current != nil }, timeout: 0.7)
            expect(s.current == nil, "a late reply offered \(String(describing: s.current))", &problems)

            // Changed facts make a new key: the suggester is not wedged.
            guard let session = Checks.target(f, a) else { return problems.append("the session is not offered") }
            _ = f.metadata.saveNote("planning", for: session.recordIDs[0])
            s.responder = { facts in calls.facts.append(facts); return .earlier(1) }
            run(s)
            expect(s.current?.session.threadID == a && s.current?.name == "Daybook",
                   "after the facts changed, offered \(String(describing: s.current))", &problems)
        }
    }

    // Review Focus 1.
    private static func namedMeanwhile() -> [String] {
        pair { f, a, b, problems in
            guard let first = Checks.target(f, a) else { return problems.append("the session is not offered") }
            let calls = Calls()
            let s = make(f, calls) { n in
                if n == 1 { _ = f.store.renameSession(first, to: "Typed") }   // named on its card while the model answers
                return .earlier(1)
            }
            run(s)
            expect(s.current?.session.threadID == b, "offered \(String(describing: s.current)), not yesterday's session", &problems)
            expect(calls.facts.count == 2, "asked \(calls.facts.count) times", &problems)

            // The answer was dropped, not kept: with the name off again, the session is asked afresh.
            expect(undoLastCorrection(f), "the rename was not undone", &problems)
            run(s)
            expect(calls.facts.count == 3 && s.current?.session.threadID == a,
                   "an answer for a session since named was kept: asked \(calls.facts.count) times, offered \(String(describing: s.current))",
                   &problems)
        }
    }

    // Review Focus 5.
    private static func undoNotReoffered() -> [String] {
        pair { f, a, b, problems in
            let calls = Calls()
            let s = make(f, calls)
            run(s)
            expect(s.current?.session.threadID == a, "today's session was not offered first", &problems)
            s.accept()
            settle(s)
            expect(Checks.target(f, a) == nil, "Name it did not name the session", &problems)
            expect(s.current?.session.threadID == b, "after Name it, offered \(String(describing: s.current))", &problems)

            expect(undoLastCorrection(f), "Undo failed", &problems)
            run(s)
            expect(Checks.target(f, a) != nil && s.current?.session.threadID == b,
                   "after Undo, offered \(String(describing: s.current)), not left on yesterday's", &problems)
            expect(calls.facts.count == 2, "Undo asked again: \(calls.facts.count) times", &problems)

            // A change to its facts is a new key: offered again.
            guard let session = Checks.target(f, a) else { return problems.append("the session is not offered") }
            _ = f.metadata.saveNote("planning", for: session.recordIDs[0])
            run(s)
            expect(s.current?.session.threadID == a, "after its facts changed, offered \(String(describing: s.current))", &problems)
        }
    }

    private static func keepNext() -> [String] {
        pair { f, a, b, problems in
            let calls = Calls()
            let s = make(f, calls)
            run(s)
            s.keep()
            settle(s)
            expect(f.persistence.nameSuggestionKept == [a.uuidString], "kept \(f.persistence.nameSuggestionKept)", &problems)
            expect(s.current?.session.threadID == b, "after Keep as is, offered \(String(describing: s.current))", &problems)
            s.keep()
            settle(s)
            expect(s.current == nil && !s.isAsking && calls.facts.count == 2,
                   "with none left: offered \(String(describing: s.current)), asked \(calls.facts.count) times", &problems)
        }
    }

    private static func noteLine() -> [String] {
        pair { f, a, _, problems in
            guard let session = Checks.target(f, a) else { return problems.append("the session is not offered") }
            func line() -> String? {
                f.store.nameFacts(for: session)?.text.components(separatedBy: "\n").first { $0.hasPrefix("Note: ") }
            }
            _ = f.metadata.saveNote("fixed  parser\n\nfor\tfortnight", for: session.recordIDs[0])
            expect(line() == "Note: “fixed parser for fortnight”", "the note line reads “\(line() ?? "nil")”", &problems)
            _ = f.metadata.saveNote(Array(repeating: "word", count: 80).joined(separator: " \n"), for: session.recordIDs[0])
            let inner = line().map { String($0.dropFirst("Note: “".count).dropLast()) } ?? ""
            expect(inner.count >= 190 && inner.count <= 200 && !inner.contains("\n") && !inner.hasSuffix(" "),
                   "a long note is \(inner.count) characters", &problems)
        }
    }

    /// Nothing tells the suggester the store changed: `current` can be stale
    /// when a button is pressed.
    private static func staleOffer() -> [String] {
        pair { f, a, b, problems in
            guard let first = Checks.target(f, a), let second = Checks.target(f, b) else {
                return problems.append("both sessions should be offered")
            }
            let s = make(f, Calls())
            run(s)
            expect(s.current?.session.threadID == a, "today's session was not offered first", &problems)
            expect(f.store.renameSession(first, to: "Typed"), "the typed name was refused", &problems)
            let typed = f.store.lastCorrection?.id
            s.accept()
            settle(s)
            let names = f.engine.archive.records.filter { $0.threadID == a }.map(\.name)
            expect(names == ["Typed"], "Name it left the session named \(names)", &problems)
            expect(f.store.lastCorrection?.id == typed, "Name it made a second correction", &problems)
            expect(s.current?.session.threadID == b, "after Name it, offered \(String(describing: s.current))", &problems)

            // Keep as is on a session named since leaves it out of the kept list.
            expect(f.store.renameSession(second, to: "Other"), "the second typed name was refused", &problems)
            s.keep()
            settle(s)
            expect(f.persistence.nameSuggestionKept.isEmpty, "kept \(f.persistence.nameSuggestionKept)", &problems)
            expect(s.current == nil, "after Keep as is, offered \(String(describing: s.current))", &problems)
        }
    }

    private static func answerMapping() -> [String] {
        var problems: [String] = []
        let cases: [(String, String, NameChoice)] = [
            ("1", "", .earlier(1)), (" 3 ", "", .earlier(3)), ("new", "Parser work", .fresh("Parser work")),
            ("New", "Parser work", .fresh("Parser work")), ("none", "Parser work", .none),
            ("4", "", .none), ("0", "", .none), ("", "", .none), ("one", "", .none),
        ]
        for (answer, name, want) in cases {
            let got = NameSuggester.choice(answer, name)
            expect(got == want, "“\(answer)” read as \(got), not \(want)", &problems)
        }
        return problems
    }
}
