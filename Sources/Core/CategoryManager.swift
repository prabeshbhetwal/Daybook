import Foundation

/// Resolves a bundle identifier to an `AppCategory` using D4 precedence:
/// user override → built-in map → `.neutral`.
final class CategoryManager {

    /// Code-constant. Never written to `UserDefaults`.
    static let builtInMap: [String: AppCategory] = [
        // Work
        "com.todesktop.230313mzl4w4u92": .work,   // Cursor
        "com.microsoft.VSCode": .work,
        "com.microsoft.VSCodeInsiders": .work,
        "com.apple.Terminal": .work,
        "com.googlecode.iterm2": .work,
        "com.docker.docker": .work,
        "dev.warp.Warp-Stable": .work,
        "com.mongodb.compass": .work,
        "com.google.antigravity": .work,
        "com.google.antigravity-ide": .work,
        "com.postmanlabs.mac": .work,
        "com.apple.dt.Xcode": .work,
        "com.jetbrains.WebStorm": .work,
        "com.figma.Desktop": .work,
        "com.tinyapp.TablePlus": .work,
        "com.github.GitHubClient": .work,

        // Break
        "com.spotify.client": .breakTime,
        "com.apple.Music": .breakTime,
        "com.apple.TV": .breakTime,
        "com.netflix.Netflix": .breakTime,
        "com.hnc.Discord": .breakTime,
        "com.apple.iChat": .breakTime,
        "tv.parsec.www": .breakTime,
        "com.valvesoftware.steam": .breakTime,

        // Neutral — listed explicitly so the intent is documented, though the
        // default for any unknown bundle identifier is also `.neutral` (D18).
        "com.apple.Safari": .neutral,
        // Ambiguous in `PurposeMap`; neutral here so it never pauses a session.
        "company.thebrowser.dia": .neutral,
        "com.google.Chrome": .neutral,
        "company.thebrowser.Browser": .neutral,
        "com.apple.finder": .neutral,
        "com.apple.systempreferences": .neutral,
        "com.apple.systemsettings": .neutral,
        "com.apple.mail": .neutral,
        "com.apple.Notes": .neutral
    ]

    /// Advisory only: pre-selects a work type when a session starts. Distinct
    /// from `builtInMap`, which drives auto-pause. The user's choice always wins.
    static let suggestedWorkTypes: [String: WorkType] = [
        "com.apple.dt.Xcode": .deepWork,
        "com.microsoft.VSCode": .deepWork,
        "com.microsoft.VSCodeInsiders": .deepWork,
        "com.todesktop.230313mzl4w4u92": .deepWork,
        "com.googlecode.iterm2": .deepWork,
        "com.apple.Terminal": .deepWork,
        "dev.warp.Warp-Stable": .deepWork,
        "com.google.antigravity": .deepWork,
        "com.google.antigravity-ide": .deepWork,
        "com.mongodb.compass": .admin,
        "com.jetbrains.WebStorm": .deepWork,
        "com.figma.Desktop": .deepWork,
        "us.zoom.xos": .meetings,
        "com.microsoft.teams2": .meetings,
        "com.apple.iChat": .meetings,
        "com.apple.mail": .admin,
        "com.apple.Notes": .admin,
        "com.tinyapp.TablePlus": .admin,
        "com.apple.Safari": .learning,
        "com.spotify.client": .breakTime,
        "com.apple.Music": .breakTime,
        "com.netflix.Netflix": .breakTime,
        "com.hnc.Discord": .breakTime
    ]

    private let store: PersistenceStore

    init(store: PersistenceStore) {
        self.store = store
    }

    /// Falls back to deep work: the most common case, and the least annoying
    /// thing to correct if wrong.
    func suggestedWorkType(for bundleID: String?) -> WorkType {
        guard let bundleID else { return .deepWork }
        if let raw = store.overrides[bundleID], let override = AppCategory(rawValue: raw) {
            // An explicit Break override should suggest a break session too.
            if override == .breakTime { return .breakTime }
        }
        return CategoryManager.suggestedWorkTypes[bundleID] ?? .deepWork
    }

    func category(for bundleID: String?) -> AppCategory {
        guard let bundleID, !bundleID.isEmpty else { return .neutral }
        if let raw = store.overrides[bundleID], let override = AppCategory(rawValue: raw) {
            return override
        }
        return CategoryManager.builtInMap[bundleID] ?? .neutral
    }

    func setOverride(_ category: AppCategory, for bundleID: String) {
        var overrides = store.overrides
        overrides[bundleID] = category.rawValue
        store.overrides = overrides
    }

    func clearOverride(for bundleID: String) {
        var overrides = store.overrides
        overrides.removeValue(forKey: bundleID)
        store.overrides = overrides
    }

    func hasOverride(for bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return store.overrides[bundleID] != nil
    }
}
