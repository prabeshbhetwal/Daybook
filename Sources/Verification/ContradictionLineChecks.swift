import Foundation

/// The report's one factual line when what a session was filed under and what its time went on part
/// ways (spec section 6): only for a category the person or a rule chose, strictly under 30% of the
/// credited time for what the category stands for and strictly over 60% for one other purpose.
enum ContradictionLineChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The contradiction line fires under 30% and over 60% of credited time, and at neither edge", edges),
        ("The contradiction line shows only for a category the person or a rule chose", onlyTheirOwnChoices),
        ("Each built-in category reads the purposes that suit it, Break has no line, a custom one reads the focused ones",
         categoryMapping),
        ("The line counts minutes from credited seconds, names the activity as the phase strip does and keeps quiet on thin evidence",
         wording),
    ]

    /// Registered at the end of the registry, so the numbers cited in comments stay where they were.
    static let watchingTests: [(String, () -> [String])] = [
        ("A category that counts while watching also stands for media: held time never contradicts it",
         watchingCategories),
    ]
    /// Credited minutes by purpose, in the seconds a stored shape keeps.
    static func credited(_ minutes: [AppPurpose: Double]) -> [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: minutes.map { ($0.key.rawValue, $0.value * 60) })
    }

    private static func line(_ category: WorkType, _ minutes: [AppPurpose: Double],
                             source: DecisionSource = .user, watching: Bool? = nil) -> String? {
        ContradictionLine.text(category: category, source: source, credited: credited(minutes),
                               countsWhileWatching: watching ?? category.countsWhileWatching)
    }

    private static func edges() -> [String] {
        var problems: [String] = []
        expect(line(.deepWork, [.coding: 29, .media: 61, .utility: 10]) == "Mostly entertainment: 61 of 100 minutes",
               "29% focused and 61% media did not say so: \(String(describing: line(.deepWork, [.coding: 29, .media: 61, .utility: 10])))",
               &problems)
        expect(line(.deepWork, [.coding: 30, .media: 61, .utility: 9]) == nil,
               "exactly 30% focused still fired", &problems)
        expect(line(.deepWork, [.coding: 29, .media: 60, .utility: 11]) == nil,
               "exactly 60% of one other purpose still fired", &problems)
        expect(line(.deepWork, [.coding: 30, .media: 70]) == nil, "a 30/70 session fired", &problems)
        expect(line(.deepWork, [.media: 100]) == "Mostly entertainment: 100 of 100 minutes",
               "a session with no focused time at all did not fire", &problems)
        expect(line(.deepWork, [:]) == nil && line(.deepWork, [.coding: 0]) == nil, "no evidence fired", &problems)
        return problems
    }

    private static func onlyTheirOwnChoices() -> [String] {
        var problems: [String] = []
        let shape = credited([.coding: 29, .media: 61, .utility: 10])
        for source in [DecisionSource.user, .rule] {
            expect(ContradictionLine.text(category: .deepWork, source: source, credited: shape, countsWhileWatching: false) != nil,
                   "a category from \(source) got no line", &problems)
        }
        for source in [DecisionSource.builtIn, .correction, .ai] {
            expect(ContradictionLine.text(category: .deepWork, source: source, credited: shape, countsWhileWatching: false) == nil,
                   "a category from \(source) got a line: Daybook's own guess is not contradicted", &problems)
        }
        return problems
    }

    private static func categoryMapping() -> [String] {
        var problems: [String] = []
        // Deep work: the three focused purposes together are what it stands for.
        expect(line(.deepWork, [.coding: 15, .writingAI: 9, .design: 5, .media: 61, .utility: 10]) != nil,
               "29% across three focused purposes did not fire", &problems)
        expect(line(.deepWork, [.coding: 15, .writingAI: 10, .design: 5, .media: 61, .utility: 9]) == nil,
               "30% across three focused purposes fired", &problems)
        expect(line(.deepWork, [.coding: 20, .writingAI: 70, .utility: 10]) == nil,
               "mostly Writing & AI contradicted Deep work", &problems)
        // Meetings: communication, and media too, since a meeting counts while watching.
        expect(line(.meetings, [.communication: 20, .media: 70, .utility: 10]) == nil,
               "a meeting held in a browser, read as video, was contradicted", &problems)
        expect(line(.meetings, [.communication: 20, .utility: 80]) == "Mostly other apps: 80 of 100 minutes",
               "meetings spent in utilities did not say so", &problems)
        expect(line(.meetings, [.communication: 100]) == nil, "an all-communication meeting fired", &problems)
        expect(line(.meetings, [.communication: 25, .coding: 75]) == "Mostly coding: 75 of 100 minutes",
               "meetings spent coding did not say so", &problems)
        // Admin: utility and communication together.
        expect(line(.admin, [.utility: 14, .communication: 15, .media: 71]) != nil,
               "29% across utility and communication did not fire", &problems)
        expect(line(.admin, [.utility: 15, .communication: 15, .media: 70]) == nil,
               "30% across utility and communication fired", &problems)
        // Learning: research, media and the focused purposes.
        expect(line(.learning, [.research: 5, .media: 5, .coding: 19, .communication: 71])
                == "Mostly chat & email: 71 of 100 minutes",
               "learning spent in messages did not say so", &problems)
        for suiting in [AppPurpose.research, .media, .coding, .writingAI, .design] {
            expect(line(.learning, [suiting: 100]) == nil, "learning spent on \(suiting) fired", &problems)
        }
        // Break stands for no purpose; a category of the person's own reads the focused ones.
        expect(line(.breakTime, [.media: 100]) == nil, "a break fired", &problems)
        let custom = WorkType(rawValue: "custom.reading")
        expect(line(custom, [.coding: 20, .media: 80]) == "Mostly entertainment: 80 of 100 minutes",
               "a custom category did not read the focused purposes", &problems)
        expect(line(custom, [.coding: 100]) == nil, "a custom category spent coding fired", &problems)
        return problems
    }

    private static func watchingCategories() -> [String] {
        var problems: [String] = []
        let film: [AppPurpose: Double] = [.coding: 20, .media: 80]
        // Meetings and Learning count while watching, so the film they hold is their work.
        for category in [WorkType.meetings, .learning] {
            expect(category.countsWhileWatching, "\(category) no longer counts while watching", &problems)
            expect(line(category, film) == nil, "\(category) held mostly media and was contradicted", &problems)
        }
        // The flag, not the name, decides: a category of the person's own that sets it, and one that does not.
        let custom = WorkType(rawValue: "custom.screenings")
        expect(line(custom, film, watching: true) == nil, "a watching category of the person's own was contradicted",
               &problems)
        expect(line(custom, film, watching: false) == "Mostly entertainment: 80 of 100 minutes",
               "a category that does not count while watching was not contradicted by media", &problems)
        // Media alone is allowed; any other purpose still contradicts, whatever the category counts.
        expect(line(custom, [.coding: 20, .communication: 80], watching: true) == "Mostly chat & email: 80 of 100 minutes",
               "a watching category tolerated more than media", &problems)
        expect(line(.deepWork, film) == "Mostly entertainment: 80 of 100 minutes", "Deep work tolerated media", &problems)
        return problems
    }
    private static func wording() -> [String] {
        var problems: [String] = []
        for purpose in [AppPurpose.communication, .research, .media, .utility] {
            let expected = "Mostly \(purpose.inSentence): 70 of 95 minutes"
            let text = line(.deepWork, [purpose: 70, .coding: 20, .design: 5])
            expect(text == expected, "\(purpose) read \(String(describing: text)), not \(expected)", &problems)
        }
        expect(line(.meetings, [.writingAI: 80, .communication: 20]) == "Mostly writing & AI: 80 of 100 minutes",
               "only the first letter of an activity name drops to lower case", &problems)
        // Minutes come from the credited seconds, each rounded to the nearest minute.
        let seconds = ContradictionLine.text(category: .deepWork, source: .user,
                                             credited: [AppPurpose.coding.rawValue: 1_000, AppPurpose.media.rawValue: 3_700],
                                             countsWhileWatching: false)
        expect(seconds == "Mostly entertainment: 62 of 78 minutes", "3700 of 4700 seconds read \(String(describing: seconds))", &problems)
        let one = ContradictionLine.text(category: .deepWork, source: .user, credited: [AppPurpose.media.rawValue: 60],
                                          countsWhileWatching: false)
        expect(one == "Mostly entertainment: 1 of 1 minute", "one minute read \(String(describing: one))", &problems)
        let thin = ContradictionLine.text(category: .deepWork, source: .user, credited: [AppPurpose.media.rawValue: 59],
                                           countsWhileWatching: false)
        expect(thin == nil, "under a minute of credit was worth a line", &problems)
        return problems
    }
}
