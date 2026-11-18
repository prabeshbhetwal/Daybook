import Foundation

/// How a session began. Stored on its record; absent on records written
/// before it existed, which read by `SessionRecord.effectiveOrigin`.
enum SessionOrigin: String, Codable {
    case manual, rule, automatic

    /// A value a later build adds reads as automatic: never as the person's own.
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .automatic
    }
}

/// Where a decision came from. One vocabulary shared with the away design,
/// defined once here.
enum DecisionSource: String, Codable {
    case user, rule, correction, ai, builtIn

    /// A value a later build adds reads as built in: never as the person's own.
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .builtIn
    }
}

extension SessionRecord {
    /// A missing origin is what `isAuto` says: the app's own start or the person's.
    var effectiveOrigin: SessionOrigin { origin ?? (isAuto ? .automatic : .manual) }
    /// A missing source reads as the app's guess for an automatic session, else the person's.
    var effectiveCategorySource: DecisionSource { categorySource ?? (isAuto ? .builtIn : .user) }

    /// A copy carrying the running stretch's provenance.
    func stamped(_ provenance: SessionProvenance) -> SessionRecord {
        var copy = self
        copy.origin = provenance.origin
        copy.originRuleID = provenance.ruleID
        copy.originRuleName = provenance.ruleName
        copy.categorySource = provenance.categorySource
        copy.nameByApp = provenance.nameByApp
        return copy
    }

    /// A copy that began as `source` did: for time counted back into a session
    /// or filed under a session's name, which is that session's own time.
    func carryingProvenance(of source: SessionRecord) -> SessionRecord {
        var copy = self
        copy.origin = source.origin
        copy.originRuleID = source.originRuleID
        copy.originRuleName = source.originRuleName
        copy.categorySource = source.categorySource
        copy.nameByApp = source.nameByApp
        return copy
    }

    /// The person's rename: the name is theirs from here. A record that never
    /// said (nil) stays as it was.
    mutating func rename(to proposed: String) {
        guard name != proposed else { return }
        name = proposed
        if nameByApp == true { nameByApp = false }
    }

    /// The person's category change. Choosing the category it already has
    /// changes nothing, as before.
    mutating func recategorise(to proposed: WorkType) {
        guard workType != proposed else { return }
        workType = proposed
        categorySource = .user
    }
}

/// What the running stretch's record will say about how it began. Lives on the
/// engine, travels in `PersistedState`, and is stamped onto each record the
/// stretch writes.
struct SessionProvenance: Codable, Equatable {
    var origin: SessionOrigin
    var ruleID: UUID?
    var ruleName: String?
    var categorySource: DecisionSource
    var nameByApp: Bool

    static let manual = SessionProvenance(origin: .manual, ruleID: nil, ruleName: nil,
                                          categorySource: .user, nameByApp: false)

    /// A learned category does not change the source: it is still the app's guess.
    static func automatic(nameByApp: Bool) -> SessionProvenance {
        SessionProvenance(origin: .automatic, ruleID: nil, ruleName: nil,
                          categorySource: .builtIn, nameByApp: nameByApp)
    }

    /// A rule's name is the person's, so the name is not the app's.
    static func rule(_ action: ActivityAutomaticAction) -> SessionProvenance {
        SessionProvenance(origin: .rule, ruleID: action.ruleID, ruleName: action.ruleName,
                          categorySource: .rule, nameByApp: false)
    }

    /// A state saved before provenance existed: what its ownership flag and
    /// rule action said.
    static func legacy(isAuto: Bool, action: ActivityAutomaticAction?) -> SessionProvenance {
        guard isAuto else { return .manual }
        return action.map(rule) ?? automatic(nameByApp: false)
    }
}

extension SessionProvenance {
    /// What Undo can put back on the running stretch.
    var undoable: SessionArchiveCorrectionSnapshot.Fields.Provenance {
        .init(categorySource: categorySource, nameByApp: nameByApp)
    }

    /// A value missing or malformed reads as the app's own, never the person's,
    /// and never makes the saved state unreadable: the running session outlives
    /// a later build's change here.
    init(from decoder: Decoder) throws {
        let keys = try? decoder.container(keyedBy: CodingKeys.self)
        origin = keys?.lenient(SessionOrigin.self, .origin) ?? .automatic
        ruleID = keys?.lenient(UUID.self, .ruleID)
        ruleName = keys?.lenient(String.self, .ruleName)
        categorySource = keys?.lenient(DecisionSource.self, .categorySource) ?? .builtIn
        nameByApp = keys?.lenient(Bool.self, .nameByApp) ?? false
    }
}

extension KeyedDecodingContainer {
    /// A provenance value that is missing or malformed reads as nil, so a later
    /// build's change to one never makes a record or the running state unreadable.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}

extension SessionArchiveCorrectionSnapshot.Fields.Provenance {
    init(from decoder: Decoder) throws {
        let keys = try? decoder.container(keyedBy: CodingKeys.self)
        categorySource = keys?.lenient(DecisionSource.self, .categorySource)
        nameByApp = keys?.lenient(Bool.self, .nameByApp)
    }
}

extension SessionArchiveCorrectionSnapshot.Fields {
    /// The provenance a correction can change, kept so Undo puts it back. Nil
    /// members are values too: a record that never said stays that way.
    struct Provenance: Codable, Equatable {
        var categorySource: DecisionSource?
        var nameByApp: Bool?
    }

    init(record: SessionRecord) {
        self.init(recordID: record.id, name: record.name, workType: record.workType,
                  provenance: .init(categorySource: record.categorySource, nameByApp: record.nameByApp))
    }
}
