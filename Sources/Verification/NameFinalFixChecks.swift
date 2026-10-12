import Foundation

/// The last review's findings on name suggestions, kept apart from the other
/// name suites so their numbers hold: what Name it hands back for Undo, a tie
/// that a later name breaks, an offer the store refused, and an answer kept
/// after the earlier names were ranked again, and a key that reads the same
/// on every call.
enum NameFinalFixChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Name it hands back the rename's correction; Undo with it restores the name and the session is not offered again", nameItUndo),
        ("A session whose earlier names tied is offered once another name breaks the tie", tieBreaks),
        ("A Name it the store refuses leaves the session on offer", refusedStaysOffered),
        ("A cached name is dropped when renames tie or overturn the earlier names' ranking", rankingChanges),
        ("The facts' key reads the same on every call, whatever order the apps are summed in", stableKey),
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

    /// Today 7:00–7:30 (B) in Xcode and Terminal. "Daybook" used Xcode and
    /// Mail, so it alone fits B and is offered. Naming yesterday's C, Terminal
    /// only, "Thesis" brings Thesis within 0.05 of Daybook: a tie. Naming D,
    /// Xcode and Terminal, "Thesis" too puts Thesis well ahead.
    private static func rankingChanges() -> [String] {
        let (b, c, d) = (UUID(), UUID(), UUID())
        return Checks.withFixture(records: { days in [
            Checks.record(days.at(0, 7), days.at(0, 7, 30), thread: b),
            Checks.record(days.at(1, 14), days.at(1, 14, 45), thread: c),
            Checks.record(days.at(1, 16), days.at(1, 16, 45), thread: d),
            Checks.record(days.at(3, 9), days.at(3, 11), name: "Daybook"),
        ] }, usage: { days in [
            Checks.app("Xcode", days.at(0, 7), 15 * 60), Checks.app("Terminal", days.at(0, 7, 15), 15 * 60),
            Checks.app("Terminal", days.at(1, 14), 40 * 60),
            Checks.app("Xcode", days.at(1, 16), 20 * 60), Checks.app("Terminal", days.at(1, 16, 20), 20 * 60),
            Checks.app("Xcode", days.at(3, 9), 45 * 60), Checks.app("Mail", days.at(3, 9, 45), 55 * 60),
        ] }) { f, _, problems in
            let calls = Support.Calls()
            let s = Support.make(f, calls)
            Support.run(s)
            guard s.current?.session.threadID == b, s.current?.name == "Daybook",
                  let second = Checks.target(f, c), let third = Checks.target(f, d) else {
                return problems.append("B was not offered Daybook first: \(String(describing: s.current))")
            }
            expect(f.store.acceptNameSuggestion("Thesis", for: second), "naming C failed", &problems)
            Support.run(s)
            let tied = Checks.target(f, b).flatMap { f.store.nameFacts(for: $0)?.candidates } ?? []
            expect(tied.count == 2 && !NameCandidates.isClearLead(tied),
                   "B should tie, got \(tied.map { "\($0.name) \($0.score)" })", &problems)
            expect(s.current?.session.threadID != b && calls.facts.count == 1,
                   "B was offered \(String(describing: s.current?.name)) while tied, after \(calls.facts.count) questions",
                   &problems)
            expect(f.store.acceptNameSuggestion("Thesis", for: third), "naming D failed", &problems)
            Support.run(s)
            expect(s.current?.session.threadID == b && s.current?.name == "Thesis" && calls.facts.count == 2,
                   "once Thesis led, B was offered \(String(describing: s.current?.name)) after \(calls.facts.count) questions",
                   &problems)
        }
    }

    /// Five apps with fractional seconds, against names with three and four:
    /// sums whose result hangs on the order the apps are added in.
    private static func stableKey() -> [String] {
        let b = UUID()
        return Checks.withFixture(records: { days in [
            Checks.record(days.at(0, 7), days.at(0, 8), thread: b),
            Checks.record(days.at(3, 9), days.at(3, 11), name: "Daybook"),
            Checks.record(days.at(4, 9), days.at(4, 11), name: "Thesis"),
        ] }, usage: { days in [
            Checks.app("Xcode", days.at(0, 7), 601.3), Checks.app("Terminal", days.at(0, 7, 11), 437.7),
            Checks.app("Safari", days.at(0, 7, 20), 523.9), Checks.app("Mail", days.at(0, 7, 30), 311.1),
            Checks.app("Notes", days.at(0, 7, 40), 289.4),
            Checks.app("Xcode", days.at(3, 9), 1201.7), Checks.app("Terminal", days.at(3, 9, 25), 733.3),
            Checks.app("Safari", days.at(3, 9, 40), 911.9), Checks.app("Mail", days.at(3, 10), 401.1),
            Checks.app("Safari", days.at(4, 9), 1500.3), Checks.app("Notes", days.at(4, 9, 30), 700.7),
            Checks.app("Terminal", days.at(4, 9, 45), 333.3),
        ] }) { f, _, problems in
            guard let session = Checks.target(f, b) else { return problems.append("the session is not offered") }
            let facts = (0..<50).compactMap { _ in f.store.nameFacts(for: session) }
            expect(facts.first?.candidates.count == 2, "candidates \(String(describing: facts.first?.candidates))", &problems)
            let keys = Set(facts.map(\.cacheKey))
            expect(facts.count == 50 && keys.count == 1, "50 calls gave \(keys.count) keys: \(keys.sorted())", &problems)
        }
    }
}
