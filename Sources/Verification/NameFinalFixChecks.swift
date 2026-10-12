import Foundation

/// The last review's findings on name suggestions, kept apart from the other
/// name suites so their numbers hold: what Name it hands back for Undo, a tie
/// that a later name breaks, and an offer the store refused.
enum NameFinalFixChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Name it hands back the rename's correction; Undo with it restores the name and the session is not offered again", nameItUndo),
        ("A session whose earlier names tied is offered once another name breaks the tie", tieBreaks),
        ("A Name it the store refuses leaves the session on offer", refusedStaysOffered),
    ]

    private typealias Checks = NameSuggestionStoreChecks
    private typealias Support = NameSuggesterChecks

    private static func nameItUndo() -> [String] {
        Support.pair { f, a, b, problems in
            let s = Support.make(f, Support.Calls())
            Support.run(s)
            guard s.current?.session.threadID == a else { return problems.append("today's session was not offered first") }
            let done = s.accept()
            Support.settle(s)
            expect(done?.name == "Daybook" && done?.correctionID == f.store.lastCorrection?.id,
                   "Name it returned \(String(describing: done)), not the name and the rename's correction", &problems)
            guard let done else { return }
            expect(Checks.target(f, a) == nil, "Name it did not name the session", &problems)
            expect(f.store.undoCorrection(expectedID: done.correctionID), "Undo with the returned correction failed", &problems)
            expect(Checks.target(f, a) != nil, "Undo did not put the empty name back", &problems)
            Support.run(s)
            expect(s.current?.session.threadID == b, "after Undo, offered \(String(describing: s.current)), not yesterday's", &problems)
            // Yesterday's session has no card on today's Story: its answer must come back too.
            let yesterday = s.accept()
            expect(yesterday?.correctionID == f.store.lastCorrection?.id && yesterday?.correctionID != done.correctionID,
                   "Name it on yesterday's session returned \(String(describing: yesterday))", &problems)
            // Switching off with nothing on offer must still tell the notice, which then drops its confirmation.
            let before = s.stops
            s.cancelAll()
            expect(s.stops != before, "stopping the suggester did not change `stops`", &problems)
        }
    }

    /// Today 7:00–7:30 (B) in Xcode and Terminal: "Daybook" used Xcode only and
    /// "Thesis" Terminal only, so they tie. Yesterday's C used Terminal, which
    /// only Thesis shares. Naming C "Daybook" gives Daybook Terminal time too.
    private static func tieBreaks() -> [String] {
        let (b, c) = (UUID(), UUID())
        return Checks.withFixture(records: { days in [
            Checks.record(days.at(0, 7), days.at(0, 7, 30), thread: b),
            Checks.record(days.at(1, 14), days.at(1, 14, 45), thread: c),
            Checks.record(days.at(3, 9), days.at(3, 10), name: "Daybook"),
            Checks.record(days.at(4, 9), days.at(4, 10), name: "Thesis"),
        ] }, usage: { days in [
            Checks.app("Xcode", days.at(0, 7), 15 * 60), Checks.app("Terminal", days.at(0, 7, 15), 15 * 60),
            Checks.app("Terminal", days.at(1, 14), 40 * 60),
            Checks.app("Xcode", days.at(3, 9), 50 * 60), Checks.app("Terminal", days.at(4, 9), 50 * 60),
        ] }) { f, _, problems in
            guard let first = Checks.target(f, b), let second = Checks.target(f, c) else {
                return problems.append("the sessions are not offered")
            }
            let tied = f.store.nameFacts(for: first)?.candidates
            expect(tied?.count == 2 && !NameCandidates.isClearLead(tied ?? []),
                   "B should tie, got \(String(describing: tied?.map { "\($0.name) \($0.score)" }))", &problems)
            let calls = Support.Calls()
            let s = Support.make(f, calls)
            Support.run(s)
            expect(s.current?.session.threadID == c && calls.facts.count == 1,
                   "B was asked or offered while tied: offered \(String(describing: s.current?.session.threadID)), asked \(calls.facts.count)",
                   &problems)
            expect(f.store.acceptNameSuggestion("Daybook", for: second), "naming C failed", &problems)
            Support.run(s)
            expect(s.current?.session.threadID == b && s.current?.name == "Daybook" && calls.facts.count == 2,
                   "once Daybook led, B was offered \(String(describing: s.current?.name)) after \(calls.facts.count) questions",
                   &problems)
        }
    }

    /// The archive folder is read-only, so the store cannot save the rename.
    private static func refusedStaysOffered() -> [String] {
        Support.pair { f, a, _, problems in
            let s = Support.make(f, Support.Calls())
            Support.run(s)
            let folder = f.engine.archive.dataDirectoryURL.path
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }
            let refused = s.accept()
            Support.settle(s)
            guard refused == nil else { return problems.append("the store accepted the rename, so nothing was refused") }
            expect(s.current?.session.threadID == a && s.current?.name == "Daybook",
                   "after a refusal, offered \(String(describing: s.current)), not the same session again", &problems)
            expect(Checks.target(f, a) != nil, "a refused Name it left the session named", &problems)
        }
    }
}
