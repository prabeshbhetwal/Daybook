import Foundation

/// The limits and housekeeping of the label book that the first review of Task 2 found missing (Phase C,
/// ruling C29): the daily limit counts labels made, not labels held, a name that belongs to a category the
/// model was not offered is never proposed, and a label keeps a bounded set of fingerprints.
enum AILabelRulesChecks: CheckSuite {
    typealias Fixture = AIFixture

    static let tests: [(String, () -> [String])] = [
        ("A label made today still counts toward the daily limit after it is kept, merged or removed", madeCounts),
        ("The record of labels made drops makes older than a day, and is written to the file and read back", madeFile),
        ("A proposed name that belongs to any category the model was not offered is none, in any case or plural",
         unofferedNames),
        ("The live labels are those neither archived nor lapsed at the time asked, whatever the clock says", liveAt),
        ("A label keeps its newest 50 fingerprints, and using one it already holds evicts nothing", fingerprintCap),
        ("Forgetting a label drops the cached answers that name it and no others", forgetting),
        ("A live unkept label is not reused when its name belongs to a category not offered, beyond the 20th or removed",
         unkeptShadowed),
        ("A make dated later than now neither blocks the next label nor stays in the record of makes", futureMakes),
    ]

    private static func at(_ seconds: TimeInterval) -> Date { Fixture.base.addingTimeInterval(seconds) }
    private static let day = Fixture.day

    private static func make(_ book: inout AILabelBook, _ id: String, seed: Int, now: TimeInterval) -> AILabel? {
        book.addUnkeptLabel(id: id, name: id, dominant: .media, fingerprint: Fixture.fingerprint(seed), now: at(now))
    }

    private static func madeCounts() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        expect(make(&book, "ai.1", seed: 1, now: 0) != nil, "a first label was refused", &problems)
        // Kept, merged into a category or removed: it leaves the book's labels, but it was still made today.
        book.labels.removeAll()
        expect(book.madeAt == [at(0)], "the make was recorded as \(book.madeAt)", &problems)
        expect(!book.canMakeLabel(now: at(3_600)), "a label removed an hour after it was made left room for another", &problems)
        expect(make(&book, "ai.2", seed: 2, now: 3_600) == nil, "a second label was made the day the first was removed", &problems)
        expect(book.labels.isEmpty && book.madeAt == [at(0)],
               "a refused label left \(book.labels.count) labels and \(book.madeAt.count) makes", &problems)
        expect(!book.canMakeLabel(now: at(day - 1)), "a label 24 hours less a second after a removed one was allowed", &problems)
        expect(book.canMakeLabel(now: at(day)) && make(&book, "ai.3", seed: 3, now: day) != nil,
               "a label 24 hours after a removed one was refused", &problems)
        return problems
    }

    private static func madeFile() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        _ = make(&book, "ai.1", seed: 1, now: 0)
        _ = make(&book, "ai.2", seed: 2, now: day)
        expect(book.madeAt == [at(day)], "after a day the record held \(book.madeAt.count) makes, not the newest alone", &problems)
        book.madeAt = [at(day), at(day + 5)]
        guard let data = try? JSONEncoder().encode(book), let back = try? JSONDecoder().decode(AILabelBook.self, from: data) else {
            return problems + ["a book with makes did not round trip"]
        }
        expect(back.madeAt == book.madeAt && back == book, "the makes read back as \(back.madeAt)", &problems)
        let missing = try? JSONDecoder().decode(AILabelBook.self, from: Data(#"{"labels":[]}"#.utf8))
        expect(missing?.madeAt.isEmpty == true, "a file with no makes read as \(String(describing: missing?.madeAt))", &problems)
        let damaged = try? JSONDecoder().decode(AILabelBook.self, from: Data(#"{"madeAt":[100,"x",200]}"#.utf8))
        expect(damaged?.madeAt.count == 2, "a file with one unreadable make kept \(String(describing: damaged?.madeAt.count))", &problems)
        return problems
    }

    private static let words = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo",
                                "Lima", "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform", "Victor",
                                "Whiskey", "Xray", "Yankee"]
    private static let others = ["Break", "Unsorted", "Old projects"]
    private static let offered = [(id: "deepWork", name: "Deep work"), (id: "custom.film", name: "Film")]

    private static func propose(_ label: String, from list: [(id: String, name: String)] = offered) -> AIAnswer {
        AIAnswerResolver.resolve(choice: "new", label: label, offered: list, unofferedNames: others, unkeptLabels: [],
                                 removedNames: [], newID: { "ai.new" })
    }

    private static func unofferedNames() -> [String] {
        var problems: [String] = []
        for name in ["Break", "break", "BREAK", "Breaks", "Unsorted", "  unsorted ", "Old Projects", "old project"] {
            expect(propose(name) == AIAnswer.none, "\"\(name)\" resolved to \(propose(name))", &problems)
        }
        expect(propose("film") == .pick("custom.film"), "an offered name did not pick: \(propose("film"))", &problems)
        expect(propose("Poetry") == .proposed(id: "ai.new", name: "Poetry"), "a fresh label resolved to \(propose("Poetry"))", &problems)
        // The 21st category was never shown to the model, so its name is no new label either.
        let many = words.enumerated().map { (id: "custom.\($0.offset + 1)", name: $0.element) }
        expect(propose("tango", from: many) == .pick("custom.20"), "the 20th category did not pick: \(propose("tango", from: many))", &problems)
        for name in ["Uniform", "yankee"] {
            expect(propose(name, from: many) == AIAnswer.none, "\"\(name)\", beyond the 20 offered, resolved to \(propose(name, from: many))", &problems)
        }
        return problems
    }

    private static func liveAt() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        for (index, id) in ["ai.1", "ai.2", "ai.3"].enumerated() { _ = make(&book, id, seed: index + 1, now: TimeInterval(index) * day) }
        let month = AILabelConstants.labelArchiveAfter
        func live(_ seconds: TimeInterval) -> [String] { book.liveLabels(now: at(seconds)).map(\.id) }
        expect(live(2 * day) == ["ai.1", "ai.2", "ai.3"], "the live labels were \(live(2 * day))", &problems)
        expect(live(month) == ["ai.1", "ai.2", "ai.3"], "a label unused for exactly 30 days was not live: \(live(month))", &problems)
        expect(live(month + 1) == ["ai.2", "ai.3"], "the live labels 30 days and a second on were \(live(month + 1))", &problems)
        expect(live(month + day + 1) == ["ai.3"], "the live labels a day later were \(live(month + day + 1))", &problems)
        book.labels[2].archived = true
        expect(live(2 * day) == ["ai.1", "ai.2"], "an archived label was live: \(live(2 * day))", &problems)
        expect(book.labels.count == 3, "asking for the live labels changed the book", &problems)
        return problems
    }

    private static func fingerprintCap() -> [String] {
        var problems: [String] = []
        let cap = AILabelConstants.maxLabelFingerprints
        expect(cap == 50, "the fingerprint cap was \(cap)", &problems)
        var book = AILabelBook()
        _ = make(&book, "ai.1", seed: 0, now: 0)
        for seed in 1...(cap + 9) {
            book.markUsed(labelID: "ai.1", fingerprint: Fixture.fingerprint(seed), now: at(TimeInterval(seed)))
        }
        let held = book.labels.first?.fingerprints ?? []
        expect(held.count == cap, "a label held \(held.count) fingerprints", &problems)
        expect(held.first == Fixture.fingerprint(10) && held.last == Fixture.fingerprint(cap + 9),
               "the label held an older set than the newest \(cap)", &problems)
        expect(book.reusableLabel(for: Fixture.fingerprint(cap + 9), now: at(100)) != nil
               && book.reusableLabel(for: Fixture.fingerprint(0), now: at(100)) == nil,
               "the newest fingerprint was not reused or the evicted one still was", &problems)
        book.markUsed(labelID: "ai.1", fingerprint: Fixture.fingerprint(30), now: at(200))
        expect(book.labels.first?.fingerprints == held, "using a fingerprint already held changed the set", &problems)
        return problems
    }

    private static func forgetting() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        let list = ["a"]
        let answers: [AIAnswer] = [.pick("custom.a"), .label("ai.x"), .proposed(id: "ai.x", name: "Poems"), .none, .label("ai.y")]
        for (index, answer) in answers.enumerated() {
            book.recordAnswer(answer, recordID: UUID(), fingerprint: Fixture.fingerprint(index), offered: list, now: at(0))
        }
        book.forget(labelID: "ai.x")
        expect(book.answers.map(\.fingerprint) == [0, 3, 4].map { Fixture.fingerprint($0) },
               "forgetting a label left \(book.answers.count) answers", &problems)
        expect(book.cachedAnswer(for: Fixture.fingerprint(1), offered: list, now: at(1)) == nil
               && book.cachedAnswer(for: Fixture.fingerprint(2), offered: list, now: at(1)) == nil,
               "an answer naming a forgotten label was still cached", &problems)
        expect(book.cachedAnswer(for: Fixture.fingerprint(4), offered: list, now: at(1)) == .label("ai.y"),
               "an answer naming another label was lost", &problems)
        let before = book
        book.forget(labelID: "ai.unknown")
        expect(book == before, "forgetting a label no answer names changed the book", &problems)
        return problems
    }

    private static func unkeptShadowed() -> [String] {
        var problems: [String] = []
        let names = ["Break", "Old projects", words[20], "Gossip", "Poetry", "Film"]
        let labels = names.enumerated().map { Fixture.label("ai.\($0.offset)", $0.element, seed: $0.offset) }
        let many = words.prefix(21).enumerated().map { (id: "custom.\($0.offset + 1)", name: $0.element) }
        func resolve(_ name: String, from list: [(id: String, name: String)] = offered, removed: [String] = []) -> AIAnswer {
            AIAnswerResolver.resolve(choice: "new", label: name, offered: list, unofferedNames: others, unkeptLabels: labels,
                                     removedNames: removed, newID: { "ai.new" })
        }
        // A live unkept label holds each of these names, yet the name is the person's already: none, not the label.
        for name in ["Break", "break", "Old projects", "old project"] {
            expect(resolve(name) == AIAnswer.none, "\"\(name)\" reused an unkept label: \(resolve(name))", &problems)
        }
        expect(resolve("uniform", from: many) == AIAnswer.none,
               "a name beyond the 20th reused an unkept label: \(resolve("uniform", from: many))", &problems)
        expect(resolve("Gossip", removed: ["gossip"]) == AIAnswer.none,
               "a removed name reused an unkept label: \(resolve("Gossip", removed: ["gossip"]))", &problems)
        expect(resolve("Gossip") == .label("ai.3") && resolve("poetry") == .label("ai.4"),
               "an unkept label's own name did not reuse it", &problems)
        expect(resolve("film") == .pick("custom.film"),
               "an offered name did not beat an unkept label of that name: \(resolve("film"))", &problems)
        return problems
    }

    private static func futureMakes() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        // A make dated two days ahead, as a clock set forward and back leaves behind: it is not in the last day.
        book.madeAt = [at(2 * day)]
        expect(book.canMakeLabel(now: at(0)), "a make dated two days ahead blocked a label", &problems)
        expect(make(&book, "ai.1", seed: 1, now: 0) != nil, "a label was refused while a make dated ahead was held", &problems)
        expect(book.madeAt == [at(0)], "the record held \(book.madeAt) after a make beside one dated ahead", &problems)
        book.madeAt = [at(-60), at(2 * day)]
        expect(!book.canMakeLabel(now: at(0)), "a make a minute ago stopped counting beside one dated ahead", &problems)
        book.madeAt = [at(0)]
        expect(!book.canMakeLabel(now: at(0)), "a make at this very moment did not count", &problems)
        return problems
    }
}
