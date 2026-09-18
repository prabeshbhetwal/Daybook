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

    init(id: String, name: String, symbolName: String, hue: WorkTypeHue,
         countsWhileWatching: Bool = false, isRetired: Bool = false,
         dailyGoal: TimeInterval? = nil, remindsBreaks: Bool = true) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.hue = hue
        self.countsWhileWatching = countsWhileWatching
        self.isRetired = isRetired
        self.dailyGoal = dailyGoal
        self.remindsBreaks = remindsBreaks
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbolName, hue, countsWhileWatching, isRetired, dailyGoal, remindsBreaks
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
}

/// The SF Symbols a category may wear. Curated and grouped so the grid and
/// the browse menu stay legible and every name here exists on macOS 13; a
/// name typed by hand is checked by the editor against the symbol library
/// before it is kept.
enum WorkTypeSymbols {
    static let fallback = "tag.fill"

    static let groups: [(title: String, symbols: [String])] = [
        ("Built in", ["brain.head.profile", "person.2.fill", "tray.full.fill", "book.fill",
                      "cup.and.saucer.fill"]),
        ("Making", ["hammer.fill", "chevron.left.forwardslash.chevron.right", "paintbrush.pointed.fill",
                    "pencil.and.outline", "doc.text.fill", "text.book.closed.fill", "camera.fill",
                    "music.note", "film.fill", "waveform", "wand.and.stars", "sparkles"]),
        ("Talking", ["phone.fill", "video.fill", "bubble.left.and.bubble.right.fill", "envelope.fill",
                     "megaphone.fill", "person.3.fill"]),
        ("Thinking and study", ["lightbulb.fill", "graduationcap.fill", "magnifyingglass", "chart.bar.fill",
                                "chart.line.uptrend.xyaxis", "function", "globe", "map.fill"]),
        ("Running things", ["briefcase.fill", "calendar", "checklist", "list.bullet.clipboard.fill",
                            "banknote.fill", "cart.fill", "folder.fill", "gearshape.fill",
                            "wrench.and.screwdriver.fill"]),
        ("Body and rest", ["figure.run", "figure.mind.and.body", "heart.fill", "leaf.fill", "moon.fill",
                           "fork.knife", "house.fill", "gamecontroller.fill"]),
        ("Plain marks", ["tag.fill", "star.fill", "flag.fill", "bolt.fill", "flame.fill", "circle.fill",
                         "square.fill", "diamond.fill", "seal.fill", "target"])
    ]

    /// Every grouped symbol in one list, for the grid.
    static let curated: [String] = groups.flatMap(\.symbols)

    /// A readable title for a symbol name: "chart.line.uptrend.xyaxis" reads
    /// as "Chart line uptrend xyaxis". Good enough for a menu row that also
    /// shows the symbol itself.
    static func title(for symbol: String) -> String {
        let words = symbol.split(separator: ".").map(String.init).filter { $0 != "fill" }
        guard let first = words.first else { return symbol }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    // MARK: Letters and numbers

    /// The shape a letter or number sits in. Both exist for a–z and 0–50.
    enum GlyphStyle: String, CaseIterable, Codable {
        case circle, square

        var displayName: String { self == .circle ? "Circle" : "Square" }
        var suffix: String { self == .circle ? ".circle.fill" : ".square.fill" }
    }

    static let glyphNumberLimit = 50

    /// The characters offered as one-tap glyphs: A–Z, then 0–9.
    static let glyphChoices: [String] = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .compactMap { UnicodeScalar($0).map { String(Character($0)) } } + (0...9).map(String.init)

    /// The symbol for a typed letter or number, or nil when there is none: a
    /// single ASCII letter, or a whole number from 0 to 50.
    static func glyph(for text: String, style: GlyphStyle) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first,
           scalar.value >= UnicodeScalar("a").value, scalar.value <= UnicodeScalar("z").value {
            return trimmed + style.suffix
        }
        if trimmed.allSatisfy(\.isNumber), trimmed.count <= 2, let number = Int(trimmed),
           (0...glyphNumberLimit).contains(number) {
            return String(number) + style.suffix
        }
        return nil
    }

    /// The letter or number a glyph symbol stands for, when it is one.
    static func glyphText(of symbol: String) -> (text: String, style: GlyphStyle)? {
        for style in GlyphStyle.allCases where symbol.hasSuffix(style.suffix) {
            let text = String(symbol.dropLast(style.suffix.count))
            guard glyph(for: text, style: style) == symbol else { continue }
            return (text.uppercased(), style)
        }
        return nil
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
                           symbolName: "cup.and.saucer.fill", hue: .grey)
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
    func apply(customisations: [WorkTypeDefinition]) {
        let merged = WorkTypeCatalog.merge(customisations)
        lock.lock()
        resolved = merged.byID
        order = merged.order
        lock.unlock()
        if Thread.isMainThread {
            version &+= 1
        } else {
            DispatchQueue.main.async { self.version &+= 1 }
        }
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

    /// The user's own categories, including retired ones — the editor lists
    /// those so they can be brought back.
    var customDefinitions: [WorkTypeDefinition] {
        allDefinitions.filter { !WorkType.builtIn.contains($0.workType) }
    }

    func definition(for type: WorkType) -> WorkTypeDefinition {
        lock.lock(); defer { lock.unlock() }
        if let known = resolved[type.rawValue] { return known }
        // A record from a build that knew a category this one does not. It
        // keeps a readable name rather than a bare identifier.
        return WorkTypeDefinition(id: type.rawValue, name: "Other",
                                  symbolName: WorkTypeSymbols.fallback, hue: .grey, isRetired: true)
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
                    // A built-in can be retired like any other category;
                    // its records keep it, the pickers drop it. Break stays.
                    definition.isRetired = edit.isRetired
                }
            }
            byID[base.id] = definition
            order.append(base.id)
        }
        for custom in customisations where byID[custom.id] == nil {
            var definition = custom
            definition.name = WorkTypeDefinition.normalisedName(custom.name)
            if definition.name.isEmpty { definition.name = "Untitled" }
            if definition.symbolName.isEmpty { definition.symbolName = WorkTypeSymbols.fallback }
            if definition.hue == .grey { definition.hue = .blue }
            byID[custom.id] = definition
            order.append(custom.id)
        }
        // Break stays last so every list of categories ends with rest.
        if let index = order.firstIndex(of: WorkType.breakTime.rawValue) {
            order.append(order.remove(at: index))
        }
        return (byID, order)
    }
}
