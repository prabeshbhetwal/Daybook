import Foundation

/// A session's name and its category never say two different things: a name
/// spelled like a category is that category, and the record can be tidied.
enum NameCategoryChecks {
    static let tests: [(String, () -> [String])] = [
        ("A name spelled like a category is that category, ignoring case and spacing; other names stay names",
         namingRule),
        ("Starting a session named like a category files it there, unnamed",
         startFilesUnderNamedCategory),
        ("The goal tile's tidy-up names what disagrees, moves it with its rule, and Undo puts it all back",
         tidyMovesAndUndoes)
    ]

    static func namingRule() -> [String] {
        var problems: [String] = []
        if SessionNaming.category(named: "  ADMIN ") != .admin { problems.append("\"  ADMIN \" did not read as Admin") }
        if SessionNaming.category(named: "Admin stuff") != nil { problems.append("a longer name was taken for a category") }
        if SessionNaming.category(named: "") != nil { problems.append("an empty name read as a category") }
        let resolved = SessionNaming.resolve(name: "admin", workType: .deepWork)
        if resolved.name != "" || resolved.workType != .admin { problems.append("\"admin\" under Deep work resolved to \(resolved)") }
        let kept = SessionNaming.resolve(name: "Refactor parser", workType: .deepWork)
        if kept.name != "Refactor parser" || kept.workType != .deepWork { problems.append("an ordinary name was changed") }
        if SessionNaming.contradicts(name: "Admin", workType: .admin) != nil {
            problems.append("a name matching its own category was flagged")
        }
        return problems
    }

    static func startFilesUnderNamedCategory() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.workType = .deepWork
            store.intent = "Admin"
            store.start()
            var problems: [String] = []
            if store.engine.activeWorkType != .admin { problems.append("the session was filed under \(store.engine.activeWorkType)") }
            if !store.engine.sessionName.isEmpty { problems.append("the session kept the name \"\(store.engine.sessionName)\"") }
            if store.workType != .admin { problems.append("the category picker did not follow to Admin") }
            return problems
        }
    }

    static func tidyMovesAndUndoes() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            let end = store.now().addingTimeInterval(-7_200)
            let named = SessionRecord(name: "Admin", workType: .deepWork, start: end.addingTimeInterval(-1_800),
                                      end: end, workSeconds: 1_800)
            store.engine.archive.append(named)
            store.refresh()
            let rule = ActivityRule(name: "Admin", workType: .deepWork, bundleIDs: ["com.example.mail"])
            var problems: [String] = []
            guard let tidy = store.nameCategoryTidies(rules: [rule]).first(where: { $0.target == .admin }) else {
                return ["a session and rule named Admin under Deep work were not offered for tidying"]
            }
            if tidy.threads != [named.threadID] || tidy.rules.map(\.id) != [rule.id] {
                problems.append("the tidy-up gathered \(tidy.threads.count) sessions and \(tidy.rules.count) rules")
            }
            let sentence = "1 session named “Admin” is filed under Deep work, and the rule “Admin” files new ones there. "
                + "They don’t count toward Admin."
            if tidy.sentence != sentence { problems.append("the tidy-up said \"\(tidy.sentence)\"") }

            let corrections = store.fileSessionsUnderTheirNamedCategory(tidy)
            let after = store.engine.archive.records.first { $0.id == named.id }
            if after?.workType != .admin || after?.name != "" {
                problems.append("Move left the session as \(after.map { "\($0.name) / \($0.workType)" } ?? "missing")")
            }
            if store.nameCategoryTidies(rules: []).contains(where: { $0.threads.contains(named.threadID) }) {
                problems.append("a moved session was still offered")
            }
            store.undoNameCategoryTidy(corrections)
            let undone = store.engine.archive.records.first { $0.id == named.id }
            if undone?.workType != .deepWork || undone?.name != "Admin" {
                problems.append("Undo left the session as \(undone.map { "\($0.name) / \($0.workType)" } ?? "missing")")
            }
            return problems
        }
    }
}
