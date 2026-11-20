import Foundation

/// When the on-device model is asked about an ended session, and what it may answer (Phase C, rulings C2, C3
/// and C6): the trigger, the audit of a proposed label, and the resolver that turns the model's choice into
/// a category, an existing label, a new label or nothing.
enum AITriggerChecks: CheckSuite {
    typealias Fixture = AIFixture

    static let tests: [(String, () -> [String])] = [
        ("The model is asked when the top share is under 0.60 and not at 0.60", shareBoundary),
        ("The lead rule asks under 0.15 and not at 0.15, and a top that is not focused asks", leadAndFocus),
        ("A session is not asked about under 600 s, when the person or a rule chose, when manual, or with a correction",
         notAsked),
        ("A label is one to three words of letters, at most 24 characters, and matches ignoring case and plural",
         auditRules),
        ("The model's choice resolves to a category, an existing label, a new label or nothing, never anything else",
         resolverCases),
    ]

    /// Two purposes and a third make the shares exact: every value is a whole number of seconds out of 100.
    private static let unclear: [AppPurpose: TimeInterval] = [.coding: 50, .design: 30, .research: 20]

    private static func asks(_ shape: SessionActivityShape, record: SessionRecord = Fixture.record(),
                             correction: Bool = false) -> Bool {
        AITrigger.shouldAsk(record: record, shape: shape, hasCorrection: correction)
    }

    private static func shareBoundary() -> [String] {
        var problems: [String] = []
        let below = Fixture.shape([.coding: 59, .design: 21, .writingAI: 20])
        let at = Fixture.shape([.coding: 60, .design: 21, .writingAI: 19])
        expect(asks(below), "a top share of 0.59 was not asked about", &problems)
        expect(!asks(at), "a top share of 0.60 was asked about", &problems)
        expect(!asks(Fixture.shape([.coding: 1_000])), "a session wholly in one focused purpose was asked about",
               &problems)
        expect(asks(Fixture.shape([.coding: 55, .design: 45])), "a lead of 10 points was not asked about", &problems)
        expect(asks(Fixture.shape(unclear)), "an unclear session was not asked about", &problems)
        return problems
    }

    private static func leadAndFocus() -> [String] {
        var problems: [String] = []
        // Over shares of whole purposes a top of 0.60 or more always leads by 0.20 or more, so the lead rule
        // is read on the numbers: the edge is still the constant's.
        expect(AITrigger.isUnclear(topShare: 0.60, lead: 0.14, topIsFocused: true), "a lead of 0.14 did not ask", &problems)
        expect(!AITrigger.isUnclear(topShare: 0.60, lead: 0.15, topIsFocused: true), "a lead of 0.15 asked", &problems)
        expect(AITrigger.isUnclear(topShare: 0.59, lead: 0.50, topIsFocused: true), "a share of 0.59 did not ask", &problems)
        expect(!AITrigger.isUnclear(topShare: 0.60, lead: 0.50, topIsFocused: true), "a share of 0.60 asked", &problems)
        expect(AITrigger.isUnclear(topShare: 0.90, lead: 0.80, topIsFocused: false),
               "a clear top that is not focused did not ask", &problems)
        for purpose in AppPurpose.allCases {
            var credited: [AppPurpose: TimeInterval] = [.coding: 20]
            credited[purpose] = 80
            let shape = Fixture.shape(credited)
            expect(asks(shape) == !purpose.isFocused,
                   "a top of \(purpose.rawValue) asked \(asks(shape)) though it is\(purpose.isFocused ? "" : " not") focused",
                   &problems)
        }
        return problems
    }

    private static func notAsked() -> [String] {
        var problems: [String] = []
        let shape = Fixture.shape(unclear)
        expect(!asks(Fixture.shape(unclear, counted: 599)), "599 s of counted time was asked about", &problems)
        expect(asks(Fixture.shape(unclear, counted: 600)), "600 s of counted time was not asked about", &problems)
        for source in [DecisionSource.user, .rule, .correction, .ai] {
            expect(!asks(shape, record: Fixture.record(source: source)),
                   "a category chosen by \(source.rawValue) was asked about", &problems)
        }
        expect(asks(shape, record: Fixture.record(source: .builtIn)), "the app's own guess was not asked about", &problems)
        expect(asks(shape, record: Fixture.record(origin: nil, source: nil)),
               "a record written before provenance was not read as the app's own", &problems)
        expect(!asks(shape, record: Fixture.record(origin: .manual, source: .builtIn, isAuto: false)),
               "a manual session was asked about", &problems)
        expect(!asks(shape, record: Fixture.record(origin: .rule)), "a rule's session was asked about", &problems)
        expect(!asks(shape, record: Fixture.record(origin: nil, source: nil, isAuto: false)),
               "a record written before provenance by the person was asked about", &problems)
        expect(!asks(shape, correction: true), "a session with a remembered correction was asked about", &problems)
        expect(!asks(Fixture.shape(unclear, fingerprint: nil)), "a shape with no fingerprint was asked about", &problems)
        expect(!asks(Fixture.shape([:])), "a shape credited with nothing was asked about", &problems)
        return problems
    }

    private static func auditRules() -> [String] {
        var problems: [String] = []
        let accepted: [(String, String)] = [
            ("Films", "Films"), ("  film   club  ", "film club"), ("Short Films Club", "Short Films Club"),
            ("Фильмы", "Фильмы"), ("映画", "映画"), ("Café", "Café"), ("Films\n", "Films"), ("a\tb", "a b"),
            ("Abcdefghijklmnopqrstuvwx", "Abcdefghijklmnopqrstuvwx"),
        ]
        for (input, expected) in accepted {
            expect(LabelAudit.clean(input) == expected, "\"\(input)\" cleaned to \(String(describing: LabelAudit.clean(input)))",
                   &problems)
        }
        let rejected = ["Short Films Club Night", "Abcdefghijklmnopqrstuvwxy", "Films2", "2", "Film-Club", "Films!", "Film's",
                        "Film\nClub", "Film\r\nClub", "", "   ", "\n", "Film.", "Film_Club", "🎬", "Film 🎬"]
        for input in rejected {
            expect(LabelAudit.clean(input) == nil, "\"\(input)\" was accepted as \(String(describing: LabelAudit.clean(input)))",
                   &problems)
        }
        for (first, second) in [("film", "Films"), ("Classes", "Class"), ("Bus", "Buses"), ("FILMS", "films"),
                                ("Game", "Games"), ("Deep work", "deep work")] {
            expect(LabelAudit.matches(first, second) && LabelAudit.matches(second, first),
                   "\"\(first)\" and \"\(second)\" did not match", &problems)
        }
        for (first, second) in [("Film", "Filming"), ("Class", "Glass"), ("Film", "Movie"), ("Film club", "Film")] {
            expect(!LabelAudit.matches(first, second) && !LabelAudit.matches(second, first),
                   "\"\(first)\" and \"\(second)\" matched", &problems)
        }
        return problems
    }

    private static func resolverCases() -> [String] {
        var problems: [String] = []
        let offered = [(id: "deepWork", name: "Deep work"), (id: "custom.film", name: "Film"),
                       (id: "custom.class", name: "Class")]
        let many = (1...25).map { (id: "custom.\($0)", name: "Category \($0)") }
        let labels = [Fixture.label("ai.games", "Games"), Fixture.label("ai.old", "Chess", archived: true)]
        var made = 0
        func resolve(_ choice: String, _ label: String = "", from list: [(id: String, name: String)] = offered,
                     removed: [String] = []) -> AIAnswer {
            AIAnswerResolver.resolve(choice: choice, label: label, offered: list, unofferedNames: [], unkeptLabels: labels,
                                     removedNames: removed, newID: { made += 1; return "ai.new" })
        }
        expect(resolve("1") == .pick("deepWork") && resolve("3") == .pick("custom.class"), "a number did not pick", &problems)
        expect(resolve("20", from: many) == .pick("custom.20"), "20 did not pick the twentieth", &problems)
        for choice in ["0", "4", "21", "-1", "1a", " 1", "01", "+1", "", "none", "None", "banana", "new "] {
            expect(resolve(choice) == AIAnswer.none, "\"\(choice)\" resolved to \(resolve(choice))", &problems)
        }
        expect(resolve("21", from: many) == AIAnswer.none, "a 21st category was offered or picked", &problems)
        expect(resolve("1", from: []) == AIAnswer.none, "a number picked from an empty list", &problems)
        expect(resolve("new", "films") == .pick("custom.film"), "films did not pick Film", &problems)
        expect(resolve("new", "Classes") == .pick("custom.class"), "Classes did not pick Class", &problems)
        expect(resolve("new", "DEEP  WORK") == .pick("deepWork"), "a case and spacing change did not pick", &problems)
        expect(resolve("new", "games") == .label("ai.games"), "an unkept label's name did not reuse it", &problems)
        expect(made == 0, "an id was made for \(made) answers that proposed nothing", &problems)
        expect(resolve("new", "Chess") == .proposed(id: "ai.new", name: "Chess"),
               "an archived label's name was reused instead of proposed", &problems)
        expect(resolve("new", "Gossip", removed: ["gossip"]) == AIAnswer.none, "a removed name was proposed again", &problems)
        expect(resolve("new", "Gossips", removed: ["Gossip"]) == AIAnswer.none, "a removed name's plural was proposed", &problems)
        expect(resolve("new", "Poetry") == .proposed(id: "ai.new", name: "Poetry"), "a fresh label was not proposed", &problems)
        expect(resolve("new", "  Short  films ") == .proposed(id: "ai.new", name: "Short films"),
               "a proposal was not cleaned", &problems)
        expect(made == 3, "ids were made \(made) times for three proposals", &problems)
        for bad in ["", "Four words in label", "Films2", "Poetry!", "a\nb"] {
            expect(resolve("new", bad) == AIAnswer.none, "the label \"\(bad)\" resolved to \(resolve("new", bad))", &problems)
        }
        // A category beats a removed name: matching what the person has is a pick, not a refusal.
        expect(resolve("new", "Film", removed: ["Film"]) == .pick("custom.film"), "a removed name beat a category", &problems)
        return problems
    }
}
