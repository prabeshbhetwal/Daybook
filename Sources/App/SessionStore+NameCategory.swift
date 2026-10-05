import Foundation

/// Sessions and rules whose name spells one category while they are filed
/// under another, gathered by the category the name spells.
struct NameCategoryTidy: Equatable {
    /// The category the name spells, and so where the goal looks.
    let target: WorkType
    /// The sessions' threads, the running one included.
    let threads: [UUID]
    /// Where those sessions are filed now, for the sentence.
    let filedUnder: [WorkType]
    let rules: [ActivityRule]

    /// Changes when a session or rule joins, so a kept tidy-up comes back.
    var signature: String {
        (threads.map(\.uuidString) + rules.map(\.id.uuidString)).sorted().joined(separator: ",")
    }

    /// "2 sessions named “Coding” are filed under Deep work, and the rule
    /// “Coding” files new ones there. They don't count toward Coding."
    var sentence: String {
        let name = "“\(target.displayName)”"
        let places = filedUnder.map(\.displayName).joined(separator: " and ")
        var parts: [String] = []
        if !threads.isEmpty {
            let noun = threads.count == 1 ? "1 session named \(name) is" : "\(threads.count) sessions named \(name) are"
            parts.append("\(noun) filed under \(places)")
        }
        if !rules.isEmpty {
            let ruleNoun = rules.count == 1 ? "the rule \(name) files" : "\(rules.count) rules named \(name) file"
            let destination = Set(rules.map(\.workType)) == Set(filedUnder) && !threads.isEmpty
                ? "there" : "under " + rules.map(\.workType.displayName).uniqued().joined(separator: " and ")
            parts.append("\(ruleNoun) new ones \(destination)")
        }
        let opening = parts.joined(separator: ", and ")
        let subject = threads.isEmpty ? "They" : (threads.count == 1 && rules.isEmpty ? "It" : "They")
        let verb = subject == "It" ? "doesn’t" : "don’t"
        return opening.prefix(1).uppercased() + opening.dropFirst() + ". \(subject) \(verb) count toward \(target.displayName)."
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// What one Move did, so Undo can put it back exactly.
struct NameCategoryTidyUndo {
    let corrections: [UUID]
    let rules: [ActivityRule]
}

extension SessionStore {
    func nameCategoryTidies(rules: [ActivityRule]) -> [NameCategoryTidy] {
        var threads: [UUID: (name: String, type: WorkType)] = [:]
        for record in engine.archive.records where record.workType.countsAsFocus {
            threads[record.threadID] = (record.name, record.workType)
        }
        if engine.state != .idle {
            threads[engine.activeThreadID] = (engine.sessionName, engine.activeWorkType)
        }
        var byTarget: [WorkType: (threads: [UUID], filed: [WorkType], rules: [ActivityRule])] = [:]
        for (thread, value) in threads.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let target = SessionNaming.contradicts(name: value.name, workType: value.type) else { continue }
            byTarget[target, default: ([], [], [])].threads.append(thread)
            if byTarget[target]?.filed.contains(value.type) == false { byTarget[target]?.filed.append(value.type) }
        }
        for rule in rules {
            guard let target = SessionNaming.contradicts(name: rule.name, workType: rule.workType) else { continue }
            byTarget[target, default: ([], [], [])].rules.append(rule)
        }
        return WorkType.startable.compactMap { target in
            byTarget[target].map { NameCategoryTidy(target: target, threads: $0.threads,
                                                    filedUnder: $0.filed, rules: $0.rules) }
        }
    }

    /// Files each session under the category its name spells and clears the
    /// name it no longer needs, each as an ordinary correction. The rules are
    /// the caller's to save: they live in Settings.
    func fileSessionsUnderTheirNamedCategory(_ tidy: NameCategoryTidy) -> [UUID] {
        var made: [UUID] = []
        for thread in tidy.threads {
            if setWorkType(tidy.target, threadID: thread), let id = lastCorrection?.id { made.append(id) }
            if clearSessionName(threadID: thread), let id = lastCorrection?.id { made.append(id) }
        }
        return made
    }

    /// Puts the sessions back, newest correction first.
    func undoNameCategoryTidy(_ corrections: [UUID]) {
        for id in corrections.reversed() { _ = undoCorrection(expectedID: id) }
    }
}
