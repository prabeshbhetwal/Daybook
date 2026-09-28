import Foundation

/// A copy of everything FocusContinuity keeps, made only when asked: the data
/// folder, plus the preferences that live outside it (categories, activity
/// rules, saved activities). Each backup is a new dated folder, and none is
/// ever overwritten.
enum DataBackup {
    /// iCloud Drive's folder on this Mac. Anything written here syncs to the
    /// user's iCloud like any other document; the app needs no iCloud
    /// entitlement to do it.
    static var iCloudDriveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static let folderName = "FocusContinuity Backups"
    static let preferencesFile = "preferences.plist"

    enum Failure: LocalizedError {
        case noDestination

        var errorDescription: String? {
            "iCloud Drive is not turned on for this Mac, so nothing was backed up."
        }
    }

    /// Copies `dataDirectory` and `preferences` into
    /// `<root>/FocusContinuity Backups/<yyyy-MM-dd HHmm>` and returns that
    /// folder. A folder already taken gets " 2", " 3" and so on.
    static func make(from dataDirectory: URL, preferences: [String: Any]?,
                     into root: URL, at date: Date,
                     fileManager: FileManager = .default) throws -> URL {
        // The root is iCloud Drive itself: if it is missing, iCloud Drive is
        // off, and creating it would make an ordinary folder that never syncs.
        guard fileManager.fileExists(atPath: root.path) else { throw Failure.noDestination }
        let parent = root.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let stamp = stampFormatter.string(from: date)
        var destination = parent.appendingPathComponent(stamp, isDirectory: true)
        var copy = 1
        while fileManager.fileExists(atPath: destination.path) {
            copy += 1
            destination = parent.appendingPathComponent("\(stamp) \(copy)", isDirectory: true)
        }

        if fileManager.fileExists(atPath: dataDirectory.path) {
            try fileManager.copyItem(at: dataDirectory, to: destination)
        } else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        }
        if let preferences {
            let data = try PropertyListSerialization.data(fromPropertyList: preferences,
                                                          format: .xml, options: 0)
            try data.write(to: destination.appendingPathComponent(preferencesFile), options: .atomic)
        }
        return destination
    }

    /// Western digits whatever the user's locale, so folder names sort by date.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }()
}
