import Foundation

/// The corrections file on its own: saved beside the sessions, read again after a relaunch, kept safe
/// when it cannot be read or a newer Daybook wrote it, and carried by the data folder's backups.
enum CorrectionsFileChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Remembered choices are saved beside the sessions and read again after a relaunch", survivesRelaunch),
        ("A corrupt corrections file reads empty, is set aside, and is not written over until the next record",
         corruptFileIsSetAside),
        ("A corrections file from a newer Daybook is left exactly as it is", newerFileIsLeftAlone),
        ("A backup of the data folder holds the corrections file", backupHoldsTheFile),
    ]

    private static let typical = CategoryCorrectionChecks.fingerprint()

    /// A scratch folder that exists, for a check that puts a file in it before the store does.
    private static func folder() -> URL {
        let directory = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func survivesRelaunch() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let store = CorrectionsStore(directory: directory)
        expect(store.record(fingerprint: typical, chosen: "learning", vetoed: "deepWork", at: SelfTest.base) == nil,
               "the choice was not saved", &problems)
        expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("corrections.json").path),
               "no corrections.json beside the sessions", &problems)
        let reopened = CorrectionsStore(directory: directory)
        expect(reopened.suggestion(for: typical, now: SelfTest.base) == "learning"
               && reopened.corrections.entries.first?.vetoed == ["deepWork"],
               "a relaunch read \(reopened.corrections.entries)", &problems)
        return problems
    }

    private static func corruptFileIsSetAside() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let file = directory.appendingPathComponent("corrections.json")
        let junk = Data("{ not json".utf8)
        try? junk.write(to: file)
        let store = CorrectionsStore(directory: directory)
        expect(store.corrections.entries.isEmpty && store.suggestion(for: typical, now: SelfTest.base) == nil,
               "an unreadable file read as \(store.corrections.entries)", &problems)
        expect(!FileManager.default.fileExists(atPath: file.path), "loading wrote or kept a corrections.json", &problems)
        func aside() -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("corrections-corrupt-") }
        }
        expect(aside().count == 1 && aside().first.flatMap { try? Data(contentsOf: $0) } == junk,
               "the unreadable bytes were not kept aside: \(aside())", &problems)
        expect(store.record(fingerprint: typical, chosen: "learning", vetoed: nil, at: SelfTest.base) == nil
               && CorrectionsStore(directory: directory).suggestion(for: typical, now: SelfTest.base) == "learning",
               "the next record did not start a fresh file", &problems)
        expect(aside().count == 1 && aside().first.flatMap { try? Data(contentsOf: $0) } == junk,
               "the set-aside copy changed with the next record", &problems)
        return problems
    }

    private static func newerFileIsLeftAlone() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let file = directory.appendingPathComponent("corrections.json")
        let newer = Data(#"{"version":2,"entries":[],"somethingNew":true}"#.utf8)
        try? newer.write(to: file)
        let store = CorrectionsStore(directory: directory)
        expect(store.record(fingerprint: typical, chosen: "learning", vetoed: nil, at: SelfTest.base) != nil,
               "a newer Daybook's file was written over", &problems)
        expect((try? Data(contentsOf: file)) == newer, "a newer Daybook's file changed", &problems)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        expect(names == ["corrections.json"], "a newer Daybook's file was set aside: \(names)", &problems)
        return problems
    }

    private static func backupHoldsTheFile() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        _ = CorrectionsStore(directory: directory).record(fingerprint: typical, chosen: "learning", vetoed: nil,
                                                         at: SelfTest.base)
        let manager = FileManager.default
        if let clone = try? DataBackup.clone(of: directory) {
            defer { try? manager.removeItem(at: clone) }
            expect(manager.fileExists(atPath: clone.appendingPathComponent("corrections.json").path),
                   "the temporary clone left the corrections out", &problems)
        } else {
            problems.append("no clone was made")
        }
        let root = folder()
        if let backup = try? DataBackup.make(from: directory, preferences: nil, into: root, at: SelfTest.base,
                                             isICloudDrive: false) {
            expect(manager.fileExists(atPath: backup.appendingPathComponent("corrections.json").path),
                   "the backup left the corrections out", &problems)
        } else {
            problems.append("no backup was made")
        }
        return problems
    }
}
