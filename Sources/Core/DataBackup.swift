import Foundation

/// A copy of everything Daybook keeps: the data folder, plus the preferences
/// that live outside it (categories, activity rules, saved activities). Made
/// on request or on the reader's schedule. Each backup is a new dated folder,
/// and none is ever overwritten; only automatic ones past their keeping
/// period are moved to the Trash.
enum DataBackup {
    /// iCloud Drive's folder on this Mac. Anything written here syncs to the
    /// user's iCloud like any other document; the app needs no iCloud
    /// entitlement to do it.
    static var iCloudDriveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static let folderName = "Daybook Backups"
    static let preferencesFile = "preferences.plist"
    /// Marks a backup the schedule made, the only kind ever pruned.
    static let automaticMark = "(automatic)"

    enum Failure: LocalizedError {
        case noDestination
        case folderMissing(String)

        var errorDescription: String? {
            switch self {
            case .noDestination: return "iCloud Drive is not turned on for this Mac, so nothing was backed up."
            case .folderMissing(let name):
                return "The backup folder “\(name)” is not available, so nothing was backed up. "
                    + "If it is on another disk, connect it."
            }
        }
    }

    /// Whether iCloud Drive is on for this Mac: signed in to iCloud with
    /// iCloud Drive turned on, and its folder present.
    static func iCloudDriveIsOn(fileManager: FileManager = .default, root: URL = iCloudDriveRoot) -> Bool {
        fileManager.ubiquityIdentityToken != nil && fileManager.fileExists(atPath: root.path)
    }

    /// Copies `dataDirectory` and `preferences` into
    /// `<root>/Daybook Backups/<yyyy-MM-dd HHmm>` and returns that
    /// folder. A folder already taken gets " 2", " 3" and so on. An automatic
    /// backup's name ends in "(automatic)".
    static func make(from dataDirectory: URL, preferences: [String: Any]?,
                     into root: URL, at date: Date, automatic: Bool = false,
                     isICloudDrive: Bool = true,
                     fileManager: FileManager = .default) throws -> URL {
        // When the root is iCloud Drive itself and it is missing, iCloud Drive
        // is off, and creating it would make an ordinary folder that never
        // syncs. A chosen folder that is missing is a disk not connected.
        guard fileManager.fileExists(atPath: root.path) else {
            throw isICloudDrive ? Failure.noDestination
                : Failure.folderMissing(fileManager.displayName(atPath: root.path))
        }
        let parent = root.appendingPathComponent(folderName, isDirectory: true)
        // Backups made before the rename join the new ones here, not at
        // launch: launch never reaches into iCloud Drive.
        NameMigration.carryFolder(from: root.appendingPathComponent(NameMigration.legacyBackupFolderName,
                                                                    isDirectory: true),
                                  to: parent, fileManager: fileManager)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        // A stage left by a copy that did not live to finish (a quit, a
        // crash, a shutdown). The folder may be shared with another Mac, in
        // iCloud Drive or on a network disk, whose copy is still being
        // written, so only a stage begun over a day ago counts as abandoned.
        // It is a part copy, not a backup. Its start is in its name: a copy
        // keeps its source's dates.
        let now = Int(Date().timeIntervalSince1970)
        for name in (try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? []
        where name.hasPrefix(".") && name.hasSuffix(stageSuffix) {
            if now - stageStart(name, otherwise: 0) > 86_400 {
                try? fileManager.removeItem(at: parent.appendingPathComponent(name, isDirectory: true))
            }
        }

        let stamp = stampFormatter.string(from: date) + (automatic ? " " + automaticMark : "")
        var destination = parent.appendingPathComponent(stamp, isDirectory: true)
        var copy = 1
        while fileManager.fileExists(atPath: destination.path) {
            copy += 1
            destination = parent.appendingPathComponent("\(stamp) \(copy)", isDirectory: true)
        }

        // Copied under a hidden name and renamed once whole, so a copy that
        // fails part-way never stands as a backup or counts as the newest
        // when old ones are pruned. The part is this copy's own, not the
        // reader's data, so it is removed.
        let stage = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).\(now)-\(UUID().uuidString.prefix(8))\(stageSuffix)", isDirectory: true)
        do {
            if fileManager.fileExists(atPath: dataDirectory.path) {
                try fileManager.copyItem(at: dataDirectory, to: stage)
            } else {
                try fileManager.createDirectory(at: stage, withIntermediateDirectories: false)
            }
            if let preferences {
                let data = try PropertyListSerialization.data(fromPropertyList: preferences,
                                                              format: .xml, options: 0)
                try data.write(to: stage.appendingPathComponent(preferencesFile), options: .atomic)
            }
            try fileManager.moveItem(at: stage, to: destination)
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
        return destination
    }

    /// A copy of the data folder in the temporary folder, taken where the
    /// app writes it so no file is caught mid-write. On APFS the copy is a
    /// clone: near-instant, and no extra space until the original changes.
    /// Nil when there is no data folder yet. The running app's lock file is
    /// left out: it marks this Mac's running copy, not history.
    static func clone(of dataDirectory: URL, fileManager: FileManager = .default) throws -> URL? {
        guard fileManager.fileExists(atPath: dataDirectory.path) else { return nil }
        // Clones a quit or crash left before the copy finished. The temporary
        // folder is shared with self-test runs, so only one over an hour old
        // is taken as abandoned: a copy takes seconds.
        // A copy keeps its source's dates, so the time a clone was made is
        // in its name.
        let temporary = fileManager.temporaryDirectory
        let now = Int(Date().timeIntervalSince1970)
        for name in (try? fileManager.contentsOfDirectory(atPath: temporary.path)) ?? []
        where name.hasPrefix(clonePrefix) {
            let made = Int(name.dropFirst(clonePrefix.count).prefix { $0 != "-" }) ?? now
            if now - made > 3_600 {
                try? fileManager.removeItem(at: temporary.appendingPathComponent(name, isDirectory: true))
            }
        }
        let clone = temporary.appendingPathComponent("\(clonePrefix)\(now)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.copyItem(at: dataDirectory, to: clone)
        try? fileManager.removeItem(at: clone.appendingPathComponent(InstanceLock.fileName))
        return clone
    }

    private static let clonePrefix = "daybook-backup-"
    private static let stageSuffix = ".partial"

    /// When a stage named `.<backup>.<seconds>-<id>.partial` was begun, or
    /// `otherwise` for a name without one.
    static func stageStart(_ name: String, otherwise: Int) -> Int {
        let tag = name.dropLast(stageSuffix.count).split(separator: ".").last ?? ""
        return Int(tag.prefix { $0 != "-" }) ?? otherwise
    }

    /// Moves automatic backups in `<root>/Daybook Backups` made before
    /// `cutoff` to the Trash, and returns them. The newest automatic backup
    /// always stays, and a backup made on request is never touched. One the
    /// Trash will not take (a network share has none) is left where it is:
    /// a backup is never deleted outright.
    @discardableResult
    static func pruneAutomatic(in root: URL, before cutoff: Date,
                               fileManager: FileManager = .default,
                               trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
        -> [URL] {
        let parent = root.appendingPathComponent(folderName, isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? []
        let automatic = names.compactMap { name -> (url: URL, made: Date)? in
            guard !name.hasPrefix("."), name.contains(automaticMark),
                  let made = stampFormatter.date(from: String(name.prefix(15)))
            else { return nil }
            return (parent.appendingPathComponent(name, isDirectory: true), made)
        }.sorted { $0.made < $1.made }
        var moved: [URL] = []
        for backup in automatic.dropLast() where backup.made < cutoff {
            do {
                try trash(backup.url)
                moved.append(backup.url)
            } catch {
                Diagnostics.log("old automatic backup left in place, the Trash refused it: \(error)")
            }
        }
        return moved
    }

    /// Whether a backup in iCloud Drive has reached iCloud yet.
    enum UploadState: Equatable {
        case uploaded
        case uploading
        case waiting
        case failed(String)
        /// Not in iCloud Drive, so there is nothing to upload.
        case notInICloud
        case missing
    }

    /// The upload state of every file in `folder`, taken together: the
    /// folder is uploaded only once all of them are.
    static func uploadState(of folder: URL, fileManager: FileManager = .default) -> UploadState {
        guard fileManager.fileExists(atPath: folder.path) else { return .missing }
        guard fileManager.isUbiquitousItem(at: folder) else { return .notInICloud }
        let keys: [URLResourceKey] = [.isRegularFileKey, .ubiquitousItemIsUploadedKey,
                                      .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey]
        var state = UploadState.uploaded
        let files = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        while let file = files?.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            if let error = values.ubiquitousItemUploadingError { return .failed(error.localizedDescription) }
            if values.ubiquitousItemIsUploaded == true { continue }
            state = values.ubiquitousItemIsUploading == true ? .uploading : (state == .uploading ? .uploading : .waiting)
        }
        return state
    }

    /// Western digits whatever the user's locale, so folder names sort by date.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }()
}
