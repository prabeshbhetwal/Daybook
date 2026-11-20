import Foundation

/// The label book (Phase C, rulings C7, C9, C14, C15, C25): answers cached by fingerprint and the category
/// list they were asked against, the limits on making and keeping unkept labels, and the shadow tally.
enum AILabelBookChecks: CheckSuite {
    typealias Fixture = AIFixture

    static let tests: [(String, () -> [String])] = [
        ("An answer is cached by fingerprint and the offered category list, a changed list asks again, and the old list's answers go",
         cacheKey),
        ("A cached answer lapses 90 days after it was last used, to the second, and is pruned on the next write",
         cacheExpiry),
        ("A second label within 24 hours is refused and one after 24 hours is made, and a fourth unkept label is refused",
         labelLimits),
        ("A label unused for 30 days is archived to the second: still listed, not reused, not counted",
         archiving),
        ("A label is reused for a fingerprint it holds, and using it for another keeps that one too",
         reuse),
        ("The tally reads the newest 20 entries that hold a choice, keeps 50, and says so in plain words",
         tallyText),
        ("The tally counts a pick, a label and a proposed label as matched only when the person chose that id",
         tallyMatching),
        ("The book round trips, reads a missing key as empty, and loses only the unreadable entry",
         bookFile),
    ]

    private static func at(_ seconds: TimeInterval) -> Date { Fixture.base.addingTimeInterval(seconds) }
    private static let day = Fixture.day

    private static func cacheKey() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        let one = Fixture.fingerprint(1), two = Fixture.fingerprint(2)
        book.recordAnswer(.pick("custom.film"), recordID: UUID(), fingerprint: one, offered: ["b", "a"], now: at(0))
        book.recordAnswer(.none, recordID: UUID(), fingerprint: two, offered: ["a", "b"], now: at(0))
        expect(AILabelBook.digest(of: ["b", "a"]) == "a|b" && AILabelBook.digest(of: ["a", "b"]) == "a|b",
               "the digest of b and a was \(AILabelBook.digest(of: ["b", "a"])), not a|b", &problems)
        expect(AILabelBook.digest(of: ["a", "c"]) != AILabelBook.digest(of: ["a", "b"]), "two lists shared a digest", &problems)
        expect(book.cachedAnswer(for: one, offered: ["a", "b"], now: at(1)) == .pick("custom.film"),
               "the same fingerprint and list missed, in another order", &problems)
        expect(book.cachedAnswer(for: one, offered: ["a", "b", "c"], now: at(1)) == nil, "a longer list hit", &problems)
        expect(book.cachedAnswer(for: one, offered: ["a"], now: at(1)) == nil, "a shorter list hit", &problems)
        expect(book.cachedAnswer(for: Fixture.fingerprint(3), offered: ["a", "b"], now: at(1)) == nil,
               "another fingerprint hit", &problems)
        expect(book.cachedAnswer(for: two, offered: ["a", "b"], now: at(1)) == AIAnswer.none,
               "a cached none was not remembered", &problems)
        expect(book.cachedAnswer(for: two, offered: ["a", "b", "custom.new"], now: at(1)) == nil,
               "a cached none outlived the category made after it", &problems)
        book.recordAnswer(.pick("custom.class"), recordID: UUID(), fingerprint: one, offered: ["a", "b"], now: at(2))
        expect(book.answers.count == 2 && book.cachedAnswer(for: one, offered: ["a", "b"], now: at(3)) == .pick("custom.class"),
               "a second answer for the same key did not replace the first (\(book.answers.count) kept)", &problems)
        // The list changed, and an answer was saved against the new one: what was asked of the old can never hit again.
        let longer = ["a", "b", "custom.new"]
        book.recordAnswer(.pick("custom.new"), recordID: UUID(), fingerprint: two, offered: longer, now: at(4))
        expect(book.answers.map(\.fingerprint) == [two] && book.answers.map(\.digest) == [AILabelBook.digest(of: longer)],
               "answers for the earlier list were kept: \(book.answers.map(\.digest))", &problems)
        return problems
    }

    private static func cacheExpiry() -> [String] {
        var problems: [String] = []
        let one = Fixture.fingerprint(1), two = Fixture.fingerprint(2)
        let expiry = AILabelConstants.answerExpiry
        expect(expiry == 90 * day, "the answer expiry was \(expiry) s", &problems)
        var book = AILabelBook()
        book.recordAnswer(.pick("a"), recordID: UUID(), fingerprint: one, offered: ["a"], now: at(0))
        expect(book.cachedAnswer(for: one, offered: ["a"], now: at(expiry)) == .pick("a"), "an answer lapsed at exactly 90 days", &problems)
        expect(book.cachedAnswer(for: one, offered: ["a"], now: at(expiry + 1)) == nil, "an answer lasted 90 days and a second", &problems)
        book.recordAnswer(.pick("b"), recordID: UUID(), fingerprint: two, offered: ["a"], now: at(expiry))
        expect(book.answers.count == 2, "an answer used 90 days ago was pruned (\(book.answers.count) kept)", &problems)
        book.recordAnswer(.pick("b"), recordID: UUID(), fingerprint: two, offered: ["a"], now: at(expiry + 1))
        expect(book.answers.map(\.fingerprint) == [two], "the lapsed answer was not pruned on write: \(book.answers.count) kept", &problems)

        // Using an answer again stamps it, so a pattern in use does not lapse.
        var used = AILabelBook()
        used.recordAnswer(.pick("a"), recordID: UUID(), fingerprint: one, offered: ["a"], now: at(0))
        used.recordAnswer(.pick("a"), recordID: UUID(), fingerprint: one, offered: ["a"], now: at(60 * day))
        expect(used.cachedAnswer(for: one, offered: ["a"], now: at(120 * day)) == .pick("a"),
               "an answer used again at 60 days lapsed at 120", &problems)
        expect(used.cachedAnswer(for: one, offered: ["a"], now: at(150 * day + 1)) == nil,
               "an answer used at 60 days lasted past 150 days", &problems)
        return problems
    }

    private static func make(_ book: inout AILabelBook, _ id: String, seed: Int, now: TimeInterval) -> AILabel? {
        book.addUnkeptLabel(id: id, name: id, dominant: .media, fingerprint: Fixture.fingerprint(seed), now: at(now))
    }

    private static func labelLimits() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        expect(AILabelConstants.newLabelsPerDay == 1 && AILabelConstants.maxUnkeptLabels == 3, "the limits changed", &problems)
        expect(book.canMakeLabel(now: at(0)) && make(&book, "ai.1", seed: 1, now: 0) != nil, "a first label was refused", &problems)
        expect(!book.canMakeLabel(now: at(day - 1)) && make(&book, "ai.x", seed: 9, now: day - 1) == nil,
               "a second label 24 hours less a second later was made", &problems)
        expect(book.labels.count == 1, "a refused label was kept (\(book.labels.count) labels)", &problems)
        expect(book.canMakeLabel(now: at(day)) && make(&book, "ai.2", seed: 2, now: day) != nil,
               "a label 24 hours after the last was refused", &problems)
        expect(make(&book, "ai.x", seed: 9, now: day + 60) == nil, "a label a minute after another was made", &problems)
        expect(make(&book, "ai.3", seed: 3, now: 2 * day) != nil, "a third unkept label was refused", &problems)
        expect(!book.canMakeLabel(now: at(3 * day)) && make(&book, "ai.4", seed: 4, now: 3 * day) == nil,
               "a fourth unkept label was made", &problems)
        expect(book.labels.map(\.id) == ["ai.1", "ai.2", "ai.3"], "the labels were \(book.labels.map(\.id))", &problems)
        if let made = book.labels.last {
            expect(made.countsTowardFocus == AppPurpose.media.isFocused && !made.archived
                   && made.created == at(2 * day) && made.lastUsed == at(2 * day) && made.fingerprints == [Fixture.fingerprint(3)],
                   "a made label was \(made)", &problems)
            let look = LabelLook.look(for: .media)
            expect(made.symbolName == look.symbolName && made.hue == look.hue, "a label did not take its dominant activity's look", &problems)
        }
        var coding = AILabelBook()
        expect(coding.addUnkeptLabel(id: "ai.c", name: "Cad", dominant: .coding, fingerprint: Fixture.fingerprint(), now: at(0))?
                .countsTowardFocus == true, "a label whose dominant activity is focused did not count toward focus", &problems)
        return problems
    }

    private static func archiving() -> [String] {
        var problems: [String] = []
        let month = AILabelConstants.labelArchiveAfter
        expect(month == 30 * day, "the archive time was \(month) s", &problems)
        var book = AILabelBook()
        for (index, id) in ["ai.1", "ai.2", "ai.3"].enumerated() {
            _ = make(&book, id, seed: index + 1, now: TimeInterval(index) * day)
        }
        book.archiveStale(now: at(month))
        expect(book.labels.allSatisfy { !$0.archived }, "a label was archived at exactly 30 days", &problems)
        expect(book.reusableLabel(for: Fixture.fingerprint(1), now: at(month))?.id == "ai.1", "a label of exactly 30 days was not reused", &problems)
        let later = month + 1
        expect(book.reusableLabel(for: Fixture.fingerprint(1), now: at(later)) == nil,
               "a label unused for 30 days and a second was reused before it was archived", &problems)
        expect(book.canMakeLabel(now: at(later)), "a lapsed label held a place in the limit before it was archived", &problems)
        book.archiveStale(now: at(later))
        expect(book.labels.map(\.archived) == [true, false, false], "archived flags were \(book.labels.map(\.archived))", &problems)
        expect(book.labels.count == 3, "an archived label left the book", &problems)
        expect(book.reusableLabel(for: Fixture.fingerprint(1), now: at(later)) == nil, "an archived label was reused", &problems)
        expect(book.reusableLabel(for: Fixture.fingerprint(2), now: at(later))?.id == "ai.2", "a live label was not reused", &problems)
        expect(make(&book, "ai.4", seed: 4, now: later) != nil, "an archived label counted toward the limit", &problems)
        expect(book.labels.count == 4, "the archived label left the book, or the fourth was lost (\(book.labels.count) labels)", &problems)
        // An archive is kept: archiving again changes nothing and never brings a label back.
        book.archiveStale(now: at(later + 1))
        expect(book.labels.first?.archived == true, "an archived label came back", &problems)
        return problems
    }

    private static func reuse() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        _ = make(&book, "ai.1", seed: 1, now: 0)
        expect(book.reusableLabel(for: Fixture.fingerprint(1), now: at(10))?.id == "ai.1", "a label was not reused for its own fingerprint", &problems)
        expect(book.reusableLabel(for: Fixture.fingerprint(2), now: at(10)) == nil, "a label was reused for a fingerprint it never held", &problems)
        book.markUsed(labelID: "ai.1", fingerprint: Fixture.fingerprint(2), now: at(20 * day))
        expect(book.reusableLabel(for: Fixture.fingerprint(2), now: at(21 * day))?.id == "ai.1", "a label was not reused for a fingerprint it was used for", &problems)
        expect(book.labels.first?.fingerprints.count == 2 && book.labels.first?.lastUsed == at(20 * day),
               "using a label left it as \(String(describing: book.labels.first))", &problems)
        book.markUsed(labelID: "ai.1", fingerprint: Fixture.fingerprint(2), now: at(21 * day))
        expect(book.labels.first?.fingerprints.count == 2, "a fingerprint was kept twice", &problems)
        expect(book.reusableLabel(for: Fixture.fingerprint(1), now: at(49 * day)) != nil, "a label used 28 days ago lapsed", &problems)
        book.markUsed(labelID: "ai.unknown", fingerprint: Fixture.fingerprint(5), now: at(day))
        expect(book.labels.count == 1 && book.labels.first?.fingerprints.count == 2, "using an unknown label changed the book", &problems)
        return problems
    }

    private static func entries(_ book: inout AILabelBook, count: Int, choose: (Int) -> String?) {
        for index in 0..<count {
            let id = UUID()
            book.recordAnswer(.pick("answer.\(index)"), recordID: id, fingerprint: Fixture.fingerprint(index),
                              offered: ["a"], now: at(TimeInterval(index)))
            if let chosen = choose(index) { book.recordChoice(recordID: id, chosen: chosen) }
        }
    }

    private static func tallyText() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        expect(book.tallyText() == "No choices to compare yet", "an empty tally said \"\(book.tallyText())\"", &problems)
        entries(&book, count: 3, choose: { _ in nil })
        expect(book.tallyText() == "No choices to compare yet", "answers with no choice said \"\(book.tallyText())\"", &problems)
        var one = AILabelBook()
        entries(&one, count: 1, choose: { "answer.\($0)" })
        expect(one.tallyText() == "AI matched your last choice", "one match said \"\(one.tallyText())\"", &problems)
        var miss = AILabelBook()
        entries(&miss, count: 1, choose: { _ in "custom.other" })
        expect(miss.tallyText() == "AI did not match your last choice", "one miss said \"\(miss.tallyText())\"", &problems)
        var mixed = AILabelBook()
        entries(&mixed, count: 3, choose: { $0 == 1 ? nil : "answer.\($0)" })
        expect(mixed.tallyText() == "AI matched 2 of your last 2 choices", "a skipped entry said \"\(mixed.tallyText())\"", &problems)
        // 25 entries with a choice each: only the newest 20 are read, and an even index matches.
        var long = AILabelBook()
        entries(&long, count: 25, choose: { $0 % 2 == 0 ? "answer.\($0)" : "custom.other" })
        expect(long.tallyText() == "AI matched 10 of your last 20 choices", "25 entries said \"\(long.tallyText())\"", &problems)
        // A window of 20 reaches back past an entry with no choice, to the 20 that hold one.
        var sparse = AILabelBook()
        entries(&sparse, count: 24, choose: { $0 % 2 == 1 ? nil : "answer.\($0)" })
        expect(sparse.tallyText() == "AI matched 12 of your last 12 choices", "a sparse tally said \"\(sparse.tallyText())\"", &problems)
        var many = AILabelBook()
        entries(&many, count: 60, choose: { _ in nil })
        expect(many.tally.count == AILabelConstants.tallyKeep && many.tally.first?.answerID == "answer.10",
               "60 entries kept \(many.tally.count), from \(String(describing: many.tally.first?.answerID))", &problems)
        return problems
    }

    private static func tallyMatching() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        let ids = (0..<5).map { _ in UUID() }
        let answers: [AIAnswer] = [.pick("custom.x"), .label("ai.y"), .proposed(id: "ai.z", name: "Poems"), .none, .pick("custom.x")]
        for (index, answer) in answers.enumerated() {
            book.recordAnswer(answer, recordID: ids[index], fingerprint: Fixture.fingerprint(index), offered: ["a"], now: at(0))
        }
        expect(book.tally.count == 4, "a none answer was tallied (\(book.tally.count) entries)", &problems)
        book.recordChoice(recordID: ids[0], chosen: "custom.x")
        book.recordChoice(recordID: ids[1], chosen: "custom.other")
        book.recordChoice(recordID: ids[2], chosen: "ai.z")
        book.recordChoice(recordID: ids[3], chosen: "custom.x")
        book.recordChoice(recordID: UUID(), chosen: "custom.x")
        expect(book.tallyText() == "AI matched 2 of your last 3 choices", "the tally said \"\(book.tallyText())\"", &problems)
        book.recordChoice(recordID: ids[1], chosen: "ai.y")
        expect(book.tallyText() == "AI matched 3 of your last 3 choices", "a later choice did not replace an earlier one: \"\(book.tallyText())\"", &problems)
        // Answering the same record again replaces its entry, not adds one.
        book.recordAnswer(.pick("custom.q"), recordID: ids[0], fingerprint: Fixture.fingerprint(0), offered: ["a"], now: at(5))
        expect(book.tally.count == 4 && book.tally.last?.answerID == "custom.q" && book.tally.last?.chosen == nil,
               "a second answer for a record left \(book.tally.count) entries", &problems)
        return problems
    }

    private static func bookFile() -> [String] {
        var problems: [String] = []
        let book = Fixture.filledBook()
        guard let data = try? JSONEncoder().encode(book), let back = try? JSONDecoder().decode(AILabelBook.self, from: data) else {
            return ["a filled book did not round trip"]
        }
        expect(back == book, "a book read back as a different book", &problems)
        expect(book.labels.count == 3 && book.answers.count == 4 && book.removedNames == ["Gossip"] && book.tally.count == 3,
               "the fixture held \(book.labels.count) labels, \(book.answers.count) answers, \(book.tally.count) tally entries", &problems)
        let empty = try? JSONDecoder().decode(AILabelBook.self, from: Data("{}".utf8))
        expect(empty == AILabelBook(), "an empty file did not read as an empty book: \(String(describing: empty))", &problems)
        let partial = try? JSONDecoder().decode(AILabelBook.self, from: Data(#"{"removedNames":["Gossip"]}"#.utf8))
        expect(partial?.removedNames == ["Gossip"] && partial?.labels.isEmpty == true && partial?.tally.isEmpty == true,
               "a file with one key lost the others: \(String(describing: partial))", &problems)
        expect((try? JSONDecoder().decode(AILabelBook.self, from: Data("[1]".utf8))) == nil, "a file that is not a book was read", &problems)
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return problems + ["no object"] }
        for key in ["labels", "answers", "tally"] {
            guard var list = object[key] as? [Any], list.count >= 3 else { problems.append("\(key) held no list"); continue }
            list[1] = ["unreadable": true]
            object[key] = list
        }
        object["removedNames"] = ["Gossip", 3, "Chess"]
        guard let damaged = try? JSONSerialization.data(withJSONObject: object),
              let read = try? JSONDecoder().decode(AILabelBook.self, from: damaged) else {
            return problems + ["a book with unreadable entries did not decode"]
        }
        expect(read.labels.map(\.id) == ["ai.a", "ai.c"], "the labels read were \(read.labels.map(\.id))", &problems)
        expect(read.answers.count == 3 && read.tally.count == 2, "\(read.answers.count) answers and \(read.tally.count) tally entries survived", &problems)
        expect(read.removedNames == ["Gossip", "Chess"], "the removed names read were \(read.removedNames)", &problems)
        return problems
    }
}
