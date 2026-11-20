import Foundation

/// The colour a category wears. A named hue rather than a stored colour so the
/// Design layer keeps one definition of each pair — light and dark — and a
/// category chosen on one appearance still reads on the other.
enum WorkTypeHue: String, Codable, CaseIterable, Hashable {
    case indigo, orange, teal, pink, blue, purple, green, yellow, red, brown, grey

    var displayName: String {
        switch self {
        case .indigo: return "Indigo"
        case .orange: return "Orange"
        case .teal: return "Teal"
        case .pink: return "Pink"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .brown: return "Brown"
        case .grey: return "Grey"
        }
    }

    /// The hues offered for a new category. Grey is rest's, and rest must
    /// never look like work, so it is not on the list.
    static let selectable: [WorkTypeHue] = allCases.filter { $0 != .grey }
}

/// Everything a category is, apart from its identity: what it is called, how
/// it is drawn, what colour it wears and whether watching counts as doing it.
struct WorkTypeDefinition: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var symbolName: String
    var hue: WorkTypeHue
    /// Whether passive presence is the work itself. Meetings and lectures are
    /// attended; a category the user makes for "Calls" can say the same.
    var countsWhileWatching: Bool
    /// A retired category is offered nowhere new but still describes the
    /// records that were filed under it. Deleting the definition would leave
    /// those records pointing at nothing.
    var isRetired: Bool
    /// A daily goal for this category alone, beside the day's goal. Nil means
    /// none: the category counts toward the day and nothing more.
    var dailyGoal: TimeInterval?
    /// Whether break reminders run while a session of this category is on.
    /// Deep work wants the fifty-minute nudge; a meeting does not want to be
    /// told to stand up.
    var remindsBreaks: Bool
    /// Whether time in this category counts toward focus totals, goals and
    /// streaks. Every category did before this was stored, so a list written
    /// without the key reads true; Break never does.
    var countsTowardFocus: Bool
    /// A label an AI proposed that the person has not kept. Hidden everywhere
    /// and never stored with the person's categories, so it is deliberately
    /// not a coding key.
    var isUnkeptAILabel: Bool

    init(id: String, name: String, symbolName: String, hue: WorkTypeHue,
         countsWhileWatching: Bool = false, isRetired: Bool = false,
         dailyGoal: TimeInterval? = nil, remindsBreaks: Bool = true,
         countsTowardFocus: Bool = true, isUnkeptAILabel: Bool = false) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.hue = hue
        self.countsWhileWatching = countsWhileWatching
        self.isRetired = isRetired
        self.dailyGoal = dailyGoal
        self.remindsBreaks = remindsBreaks
        self.countsTowardFocus = countsTowardFocus
        self.isUnkeptAILabel = isUnkeptAILabel
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbolName, hue, countsWhileWatching, isRetired, dailyGoal, remindsBreaks, countsTowardFocus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName)
            ?? WorkTypeSymbols.fallback
        hue = try container.decodeIfPresent(WorkTypeHue.self, forKey: .hue) ?? .blue
        countsWhileWatching = try container.decodeIfPresent(Bool.self, forKey: .countsWhileWatching) ?? false
        isRetired = try container.decodeIfPresent(Bool.self, forKey: .isRetired) ?? false
        dailyGoal = try container.decodeIfPresent(TimeInterval.self, forKey: .dailyGoal)
        remindsBreaks = try container.decodeIfPresent(Bool.self, forKey: .remindsBreaks) ?? true
        countsTowardFocus = try container.decodeIfPresent(Bool.self, forKey: .countsTowardFocus)
            ?? (id != WorkType.breakTime.rawValue)
        isUnkeptAILabel = false
    }

    /// The goals a category may be given. Shorter steps than the day's goal,
    /// since one category is a slice of it.
    static let goalOptions: [TimeInterval] = [
        900, 1_800, 2_700, 3_600, 5_400, 7_200, 9_000, 10_800, 14_400, 18_000, 21_600, 28_800
    ]

    var workType: WorkType { WorkType(rawValue: id) }

    /// The name as it will be kept: trimmed, one space between words.
    static func normalisedName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static let nameLimit = 24

    /// Why `name`, already normalised and not empty, cannot be category `id`'s among `existing`, or nil: the
    /// one rule the category editor and keeping an AI label share. A retired category's name is free.
    static func nameProblem(_ name: String, for id: String, among existing: [WorkTypeDefinition]) -> String? {
        guard name.count <= nameLimit else { return "Keep the name to \(nameLimit) characters." }
        guard let taken = existing.first(where: {
            $0.id != id && !$0.isRetired
                && LabelAudit.visible($0.name).caseInsensitiveCompare(LabelAudit.visible(name)) == .orderedSame
        }) else { return nil }
        // A hidden label is in no list the person can see, so the message says where it is.
        return taken.isUnkeptAILabel
            ? "An on-device AI category is already called “\(name)”. Keep or remove it from one of its sessions first."
            : "Another category is already called “\(name)”."
    }
}

/// One place that knows what every category is called and how it is drawn.
///
/// `WorkType` values are identifiers; this catalogue resolves them. The
/// built-ins are code constants, the user's edits and additions come from
/// `PersistenceStore`, and the merge is recomputed whenever either side
/// changes. It is a shared instance because `displayName` is read from pure
/// summary code with no store in reach; the store is the only writer.
final class WorkTypeCatalog: ObservableObject {
    static let shared = WorkTypeCatalog()

    /// Bumps on every change so views that only read `WorkType.displayName`
    /// still redraw when a category is renamed.
    @Published private(set) var version: UInt64 = 0

    private let lock = NSLock()
    private var resolved: [String: WorkTypeDefinition]
    private var order: [String]
    private var applied: UInt64 = 0
    /// The labels an AI proposed that the person has not kept (C10), carried by every `apply` so an edit to
    /// the person's own categories cannot drop one; and what was last applied, for `install(aiLabels:)`.
    private var unkept: [WorkTypeDefinition] = []
    private var lastApplied: (customisations: [WorkTypeDefinition], goals: [String: TimeInterval]?) = ([], nil)

    /// Counts every `apply`, on whichever thread and at once (`version` waits for the main queue), so what was
    /// worked out from the categories, such as a total that skips one set not to count, can tell it is stale.
    var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return applied
    }

    static let builtInDefinitions: [WorkTypeDefinition] = [
        WorkTypeDefinition(id: WorkType.deepWork.rawValue, name: "Deep work",
                           symbolName: "brain.head.profile", hue: .indigo),
        WorkTypeDefinition(id: WorkType.meetings.rawValue, name: "Meetings",
                           symbolName: "person.2.fill", hue: .orange, countsWhileWatching: true,
                           remindsBreaks: false),
        WorkTypeDefinition(id: WorkType.admin.rawValue, name: "Admin",
                           symbolName: "tray.full.fill", hue: .teal),
        WorkTypeDefinition(id: WorkType.learning.rawValue, name: "Learning",
                           symbolName: "book.fill", hue: .pink, countsWhileWatching: true),
        WorkTypeDefinition(id: WorkType.breakTime.rawValue, name: "Break",
                           symbolName: "cup.and.saucer.fill", hue: .grey, countsTowardFocus: false)
    ]

    init(customisations: [WorkTypeDefinition] = []) {
        let merged = WorkTypeCatalog.merge(customisations)
        resolved = merged.byID
        order = merged.order
    }

    /// Replaces the user's half of the catalogue. Built-ins that were not
    /// edited return to their defaults; nothing is ever removed from the
    /// resolved table, so a record filed under a retired category still knows
    /// its name.
    ///
    /// `goals` is the daily goal of each category by id, from the goal list: when
    /// given, it replaces whatever goal the definitions carry, so the list is the
    /// one truth. Nil leaves the definitions' own goals, as before the list was used.
    func apply(customisations: [WorkTypeDefinition], goals: [String: TimeInterval]? = nil) {
        lock.lock()
        lastApplied = (customisations, goals)
        let hidden = unkept
        lock.unlock()
        var merged = WorkTypeCatalog.merge(customisations + hidden)
        if let goals {
            for id in merged.byID.keys where id != WorkType.breakTime.rawValue {
                merged.byID[id]?.dailyGoal = goals[id]
            }
        }
        lock.lock()
        resolved = merged.byID
        order = merged.order
        applied &+= 1
        lock.unlock()
        if Thread.isMainThread {
            version &+= 1
        } else {
            DispatchQueue.main.async { self.version &+= 1 }
        }
    }

    /// Sets which unkept AI labels the catalogue resolves (hidden: no picker, list or Settings shows one) and
    /// installs again what was last applied with them. Later `apply` calls keep them until this is called.
    func install(aiLabels labels: [AILabel]) {
        lock.lock()
        unkept = labels.map(\.hiddenDefinition)
        let last = lastApplied
        lock.unlock()
        apply(customisations: last.customisations, goals: last.goals)
    }

    /// Every category that exists, active or retired, in catalogue order.
    var allDefinitions: [WorkTypeDefinition] {
        lock.lock(); defer { lock.unlock() }
        return order.compactMap { resolved[$0] }
    }

    /// The categories offered anywhere new: built-ins, then the user's own,
    /// Break last.
    var activeTypes: [WorkType] {
        allDefinitions.filter { !$0.isRetired }.map(\.workType)
    }

    func definition(for type: WorkType) -> WorkTypeDefinition {
        lock.lock(); defer { lock.unlock() }
        if let known = resolved[type.rawValue] { return known }
        // A record from a build that knew a category this one does not. It
        // keeps a readable name rather than a bare identifier.
        return WorkTypeDefinition(id: type.rawValue, name: "Other",
                                  symbolName: WorkTypeSymbols.fallback, hue: .grey, isRetired: true)
    }

    /// Whether a category counts toward focus, read without copying its whole definition: every total asks it
    /// of every record. One the catalogue never knew counts, as `definition(for:)`'s stand-in does.
    func countsTowardFocus(_ type: WorkType) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved[type.rawValue]?.countsTowardFocus ?? true
    }

    /// A fresh identifier for a category the user is making. Prefixed so it
    /// can never collide with a built-in, however the built-ins grow.
    static func newCustomID() -> String { "custom." + UUID().uuidString.lowercased() }

    private static func merge(_ customisations: [WorkTypeDefinition])
        -> (byID: [String: WorkTypeDefinition], order: [String]) {
        var byID: [String: WorkTypeDefinition] = [:]
        var order: [String] = []
        let edits = Dictionary(customisations.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        // Built-ins keep their identity, order and semantics; the user may
        // change what they are called and how they look, and nothing else.
        for base in builtInDefinitions {
            var definition = base
            if let edit = edits[base.id] {
                let name = WorkTypeDefinition.normalisedName(edit.name)
                if !name.isEmpty { definition.name = name }
                if !edit.symbolName.isEmpty { definition.symbolName = edit.symbolName }
                if base.hue != .grey { definition.hue = edit.hue == .grey ? base.hue : edit.hue }
                // Goal and reminder rule are the user's to set on any
                // category; rest keeps neither.
                if base.id != WorkType.breakTime.rawValue {
                    definition.dailyGoal = edit.dailyGoal
                    definition.remindsBreaks = edit.remindsBreaks
                    definition.countsTowardFocus = edit.countsTowardFocus
                    // A built-in can be retired like any other category;
                    // its records keep it, the pickers drop it. Break stays.
                    definition.isRetired = edit.isRetired
                }
            }
            byID[base.id] = definition
            order.append(base.id)
        }
        byID[unsortedDefinition.id] = unsortedDefinition   // hidden: resolvable, never listed or edited
        for custom in customisations where byID[custom.id] == nil {
            var definition = custom
            definition.name = WorkTypeDefinition.normalisedName(custom.name)
            if definition.name.isEmpty { definition.name = "Untitled" }
            if definition.symbolName.isEmpty { definition.symbolName = WorkTypeSymbols.fallback }
            if definition.hue == .grey { definition.hue = .blue }
            byID[custom.id] = definition
            if !custom.isUnkeptAILabel { order.append(custom.id) }
        }
        // Break stays last so every list of categories ends with rest.
        if let index = order.firstIndex(of: WorkType.breakTime.rawValue) {
            order.append(order.remove(at: index))
        }
        return (byID, order)
    }
}
