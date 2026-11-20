import Foundation

/// How a session began, in the words its row and its report say it (spec section 4, "Origin is shown,
/// quietly"). One line a fact: who started it, that it carried on after an away answer, and that the app
/// chose its name. The row joins them into one quiet line, the report lists them.
struct OriginText: Equatable {
    enum Kind: Hashable, CaseIterable { case manual, rule, automatic, carriedOn, namedByApp }
    struct Line: Equatable {
        let kind: Kind
        let text: String
    }

    let lines: [Line]

    /// Every fact as one sentence: what VoiceOver hears, whatever width the mark has on screen.
    var sentence: String { lines.map(\.text).joined(separator: ". ") }

    /// `rules` are the person's rules as they are now: a rule is named as it is called today (plan
    /// ruling B4), else as it was when the session began, else just "a rule".
    static func make(_ provenance: SessionProvenance, rules: [ActivityRule], carriedOn: Bool) -> OriginText {
        var lines = [began(provenance, rules: rules)]
        if carriedOn { lines.append(Line(kind: .carriedOn, text: "Carried on after you were away (your answer)")) }
        if provenance.nameByApp { lines.append(Line(kind: .namedByApp, text: "Name chosen by Daybook")) }
        return OriginText(lines: lines)
    }

    private static func began(_ provenance: SessionProvenance, rules: [ActivityRule]) -> Line {
        switch provenance.origin {
        case .manual:
            return Line(kind: .manual, text: "Started by you")
        case .automatic:
            return Line(kind: .automatic, text: "Started automatically")
        case .rule:
            let named = [rules.first { $0.id == provenance.ruleID }?.name, provenance.ruleName]
                .compactMap { $0.map(ActivityRule.normalisedName) }.first { !$0.isEmpty }
            return Line(kind: .rule, text: named.map { "Started by rule ‘\($0)’" } ?? "Started by a rule")
        }
    }
}

extension SessionStore {
    /// The mark for a session's row and report; nil where nothing says how it began.
    func originText(for session: DaySession) -> OriginText? { origin(for: session).text }

    /// The mark and how the session began, from one pass over the archive: the first stretch says how it
    /// began, and a running stretch not yet written says it through the engine.
    func origin(for session: DaySession) -> (text: OriginText?, provenance: SessionProvenance?) {
        origin(of: session, in: records(of: session))
    }

    /// A session row's two marks from that one pass: how it began, and whether the AI set its category (C17).
    func rowMarks(for session: DaySession) -> (origin: OriginText?, aiMark: Bool) {
        let stretches = records(of: session)
        return (origin(of: session, in: stretches).text, aiFiledStretch(of: session, in: stretches) != nil)
    }

    private func origin(of session: DaySession, in stretches: [SessionRecord])
        -> (text: OriginText?, provenance: SessionProvenance?) {
        guard let began = provenance(of: session, in: stretches) else { return (nil, nil) }
        return (OriginText.make(began, rules: began.origin == .rule ? engine.store.activityRules : [],
                                carriedOn: carriedOn(session, in: stretches)), began)
    }

    /// The stretches whose records the archive is searched for. The stretch running now is written to the archive
    /// only when it ends, so it is never among them: the running card reads its origin every second, and waiting
    /// for it would read the whole archive each time.
    func originSearch(for session: DaySession) -> Set<UUID> {
        var wanted = Set(session.recordIDs)
        if session.isRunning, engine.state != .idle { wanted.remove(engine.activeRecordID) }
        return wanted
    }

    /// Newest first, and done once every stretch is found: a session is nearly always among the last records,
    /// and with none to find no record is read. An explicit loop: a lazy filter over the archive looks for its
    /// matches up front, so it would read every record however few are wanted. The origin mark and the AI report
    /// (`SessionStore+AIReport.swift`) read them.
    func records(of session: DaySession) -> [SessionRecord] {
        var wanted = originSearch(for: session), found: [SessionRecord] = []
        for record in engine.archive.records.reversed() {
            if wanted.isEmpty { break }
            guard wanted.remove(record.id) != nil else { continue }
            found.append(record)
        }
        return found
    }

    private func provenance(of session: DaySession, in stretches: [SessionRecord]) -> SessionProvenance? {
        if let first = stretches.min(by: { $0.start < $1.start }) { return first.provenance }
        guard session.isRunning, engine.state != .idle, session.threadID == engine.activeThreadID else { return nil }
        return engine.activeProvenance
    }

    /// An "I was working" answer put time back inside one of the session's stretches (plan ruling B15).
    /// Read from the answers, never stored: today every away answer is the person's own.
    private func carriedOn(_ session: DaySession, in stretches: [SessionRecord]) -> Bool {
        let answers = engine.awayDecisions.filter { $0.decision == .mergeTime && $0.threadID == session.threadID }
            .map(\.range)
        guard !answers.isEmpty else { return false }
        let spans = session.spans.map { ($0.start, $0.end) } + stretches.map { ($0.start, $0.end) }
        return answers.contains { answer in spans.contains { $0.0 <= answer.start && answer.end <= $0.1 } }
    }
}
