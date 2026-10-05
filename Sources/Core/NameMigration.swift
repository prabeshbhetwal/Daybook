import Foundation

/// The app was called FocusContinuity until October 2026. Its first launch
/// under the new name carries the history folder and the preferences across
/// to the new names before anything opens them; the iCloud Drive backups
/// folder follows on the next backup, when the app is in iCloud Drive anyway.
/// Nothing is deleted: the old preferences stay where they were, and a folder
/// that cannot be moved is used where it is.
///
/// This file keeps the old name on purpose; it is the only place that may.
enum NameMigration {
    static let legacyFolderName = "FocusContinuity"
    static let legacyBackupFolderName = "FocusContinuity Backups"
    static let legacyDomain = "com.prabesh.focuscontinuity"
    /// Written to the new preferences once the old ones have been carried;
    /// after that the old domain is not read again. No `fc.` prefix, so it
    /// stays out of backups.
    static let carriedKey = "NameMigration.carriedLegacyPreferences"
    /// The files that make a folder a history folder.
    static let historyFiles = ["sessions.json", "app-usage.json"]

    /// Set at launch only when the old history folder had to stay where it
    /// was; `SessionArchive.defaultDirectory` then keeps using it.
    private(set) static var keptLegacyDirectory: URL?

    /// Runs once, at launch, before the app's stores exist.
    static func run(defaults: UserDefaults = .standard,
                    domain: String = FocusConstants.bundleIdentifier) {
        keptLegacyDirectory = carryFolders(support: SessionArchive.supportDirectory,
                                           named: SessionArchive.namedDirectory)
        carryPreferences(from: legacyDomain, to: domain, in: defaults)
    }

    /// Carries `<support>/FocusContinuity` to `named`. Returns the old folder
    /// when it has to stay in use, nil when `named` is the one to use.
    static func carryFolders(support: URL, named: URL,
                             fileManager: FileManager = .default,
                             log: (String) -> Void = Diagnostics.log) -> URL? {
        let legacy = support.appendingPathComponent(legacyFolderName, isDirectory: true)
        let used = carryFolder(from: legacy, to: named, fileManager: fileManager, log: log)
        return used.standardizedFileURL == named.standardizedFileURL ? nil : used
    }

    /// Moves the folder `legacy` to `current` and returns the folder to use.
    /// A new folder with nothing in it (Open data folder creates one) gives
    /// way to the old. When the new folder already holds history, it is used
    /// and the old one is left as it is; when it holds anything else, the old
    /// one stays in use, so history is never hidden behind a stray file.
    @discardableResult
    static func carryFolder(from legacy: URL, to current: URL,
                            fileManager: FileManager = .default,
                            log: (String) -> Void = Diagnostics.log) -> URL {
        var isFolder: ObjCBool = false
        guard legacy.standardizedFileURL != current.standardizedFileURL,
              fileManager.fileExists(atPath: legacy.path, isDirectory: &isFolder),
              isFolder.boolValue else { return current }
        if fileManager.fileExists(atPath: current.path) {
            let contents = ((try? fileManager.contentsOfDirectory(atPath: current.path)) ?? [""])
                .filter { $0 != ".DS_Store" }
            if contents.contains(where: historyFiles.contains) {
                log("both \(legacy.lastPathComponent) and \(current.lastPathComponent) hold history; "
                    + "using \(current.lastPathComponent) and leaving the other as it is")
                return current
            }
            guard contents.isEmpty else {
                log("\(current.lastPathComponent) holds other files, so \(legacy.lastPathComponent) stays in use")
                return legacy
            }
            do {
                try fileManager.removeItem(at: current)
            } catch {
                log("could not clear the empty \(current.lastPathComponent) folder, so "
                    + "\(legacy.lastPathComponent) stays in use: \(error)")
                return legacy
            }
        }
        do {
            try fileManager.moveItem(at: legacy, to: current)
            return current
        } catch {
            log("could not rename \(legacy.lastPathComponent) to \(current.lastPathComponent), "
                + "so it stays in use where it is: \(error)")
            return legacy
        }
    }

    /// Copies the old preferences under the new domain, once. Keys the new
    /// domain already has are kept; the old domain is left untouched.
    static func carryPreferences(from legacyDomain: String, to domain: String, in defaults: UserDefaults) {
        guard legacyDomain != domain else { return }
        var current = defaults.persistentDomain(forName: domain) ?? [:]
        guard current[carriedKey] == nil else { return }
        let legacy = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        current.merge(legacy) { kept, _ in kept }
        current[carriedKey] = true
        defaults.setPersistentDomain(current, forName: domain)
    }
}
