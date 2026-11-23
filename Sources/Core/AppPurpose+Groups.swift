import Foundation

/// How an app's category is presented: its colour, an example line for the
/// picker, and where the category came from. `PurposeMap.purpose` stays the
/// one place that decides it.
extension AppPurpose {
    /// One colour per category, shared by pills, bars and lists.
    var hue: WorkTypeHue {
        switch self {
        case .coding: return .blue
        case .writingAI: return .purple
        case .design: return .pink
        case .communication: return .green
        case .research: return .orange
        case .media: return .red
        case .utility: return .grey
        }
    }

    /// The words the on-device model reads. Kept apart from `displayName`
    /// so renaming what people see never changes what the model is asked;
    /// "Everything else" would tell it nothing.
    var modelName: String {
        switch self {
        case .coding: return "Coding"
        case .writingAI: return "Writing & AI"
        case .design: return "Design"
        case .communication: return "Communication"
        case .research: return "Research"
        case .media: return "Media"
        case .utility: return "Utility"
        }
    }

    /// The name inside a sentence: "Mostly entertainment", "mostly other apps".
    var inSentence: String {
        if self == .utility { return "other apps" }
        return displayName.prefix(1).lowercased() + displayName.dropFirst()
    }

    /// Shown under each choice in the picker, so the words need no glossary.
    var examples: String {
        switch self {
        case .coding: return "Xcode, VS Code, Terminal"
        case .writingAI: return "Claude, ChatGPT, Notes"
        case .design: return "Figma, Sketch, Photoshop"
        case .communication: return "WhatsApp, Slack, Mail"
        case .research: return "Safari, Chrome, Dia"
        case .media: return "Netflix, Spotify, games"
        case .utility: return "Finder, System Settings"
        }
    }
}

/// Where an app's category came from, in the words Settings shows.
enum PurposeSource: Equatable {
    case yours, builtIn, behaviour, fromApp, unknown

    var label: String {
        switch self {
        case .yours: return "Your choice"
        case .builtIn: return "Built in"
        case .behaviour: return "Follows what you do in it"
        case .fromApp: return "From the app"
        case .unknown: return "Not known yet"
        }
    }
}

extension PurposeMap {
    /// Bundle identifiers are case-insensitive on macOS, and the installed-app
    /// catalog lowercases them while recorded use keeps the app's own case.
    /// Rules and overrides therefore match either way.
    private static let rulesByLowercase: [String: PurposeRule] =
        Dictionary(rules.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })

    static func rule(for bundleID: String) -> PurposeRule? {
        rules[bundleID] ?? rulesByLowercase[bundleID.lowercased()]
    }

    static func override(for bundleID: String, in overrides: [String: String]) -> AppPurpose? {
        (overrides[bundleID] ?? overrides[bundleID.lowercased()]).flatMap(AppPurpose.init(rawValue:))
    }

    /// The overrides with one app's choice set, or cleared with nil. Stored
    /// lowercased, with any other spelling of the same app removed, so one
    /// app never holds two choices.
    static func settingOverride(_ purpose: AppPurpose?, for bundleID: String,
                                in overrides: [String: String]) -> [String: String] {
        let key = bundleID.lowercased()
        var next = overrides.filter { $0.key.lowercased() != key }
        next[key] = purpose?.rawValue
        return next
    }

    /// The category an app's row shows. A browser shows what it counts as
    /// while it is being used, the same figure goals read for active use.
    static func shownPurpose(for bundleID: String, overrides: [String: String]) -> AppPurpose {
        purpose(for: bundleID, activity: .active, overrides: overrides)
    }

    /// Mirrors the precedence of `purpose(for:activity:overrides:)`.
    static func source(for bundleID: String, overrides: [String: String]) -> PurposeSource {
        if override(for: bundleID, in: overrides) != nil { return .yours }
        switch rule(for: bundleID) {
        case .fixed: return .builtIn
        case .ambiguous: return .behaviour
        case nil: return categoryFallback(declaredCategory(bundleID)) == nil ? .unknown : .fromApp
        }
    }
}

/// One category's share of a stretch: its apps, largest first.
struct AppPurposeGroup: Identifiable, Equatable {
    let purpose: AppPurpose
    let apps: [AppRank]
    var total: TimeInterval { apps.reduce(0) { $0 + $1.total } }
    var id: String { purpose.rawValue }
}

/// The session card's apps, grouped by category.
enum AppPurposeGroups {
    static let maximumGroups = 4

    /// Groups largest first, with "Everything else" always last. Past
    /// `maximumGroups`, the smallest groups fold into "Everything else", so
    /// that name never appears twice.
    static func groups(_ apps: [AppRank], purpose: (String) -> AppPurpose) -> [AppPurposeGroup] {
        var byPurpose: [AppPurpose: [AppRank]] = [:]
        for app in apps { byPurpose[purpose(app.bundleID), default: []].append(app) }
        var named = byPurpose.filter { $0.key != .utility }
            .map { AppPurposeGroup(purpose: $0.key, apps: sortedApps($0.value)) }
            .sorted(by: larger)
        var rest = byPurpose[.utility] ?? []
        let room = maximumGroups - 1
        if named.count > maximumGroups || (named.count == maximumGroups && !rest.isEmpty) {
            rest += named[room...].flatMap(\.apps)
            named = Array(named[..<room])
        }
        return rest.isEmpty ? named : named + [AppPurposeGroup(purpose: .utility, apps: sortedApps(rest))]
    }

    /// One line above the groups, or nil when nothing useful can be said.
    static func summary(_ groups: [AppPurposeGroup]) -> String? {
        let total = groups.reduce(0) { $0 + $1.total }
        let ranked = groups.sorted(by: larger)
        guard total > 0, let top = ranked.first, top.purpose != .utility else { return nil }
        if ranked.count == 1 { return "All \(top.purpose.displayName)" }
        if top.total / total > 0.5 { return "Mostly \(top.purpose.displayName)" }
        let second = ranked[1]
        if second.purpose != .utility, (top.total + second.total) / total > 0.8 {
            return "\(top.purpose.displayName) and \(second.purpose.displayName)"
        }
        return "A mix of \(ranked.count) kinds of work"
    }

    private static func sortedApps(_ apps: [AppRank]) -> [AppRank] {
        apps.sorted { $0.total != $1.total ? $0.total > $1.total : $0.bundleID < $1.bundleID }
    }

    /// Larger total first; ties in the enum's order so the result is stable.
    private static func larger(_ a: AppPurposeGroup, _ b: AppPurposeGroup) -> Bool {
        if a.total != b.total { return a.total > b.total }
        let order = AppPurpose.allCases
        return order.firstIndex(of: a.purpose)! < order.firstIndex(of: b.purpose)!
    }
}
