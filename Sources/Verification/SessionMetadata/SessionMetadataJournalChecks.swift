import Foundation

/// Session metadata is a snapshot plus a journal of the changes since it, so a
/// power reading costs one line instead of a rewrite of every session's
/// metadata. These checks hold the journal to what the full rewrite promised:
/// nothing lost across a relaunch, a cut-short write losing only its own
/// change, and a line from a newer build never written over.
enum SessionMetadataJournalChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A power reading adds a journal line and leaves the metadata file as it was", readingIsOneLine),
        ("A cut-short write loses only its own change, never half a move of power", tornMoveIsWhole),
        ("A journal line this build cannot read leaves metadata read-only and untouched", unreadableLineFailsClosed),
        ("Metadata removed through the journal stays removed after a relaunch", removalSurvivesRelaunch),
        ("The journal folds into the metadata file once it reaches its limit", journalCompactsAtLimit),
        ("A journal left beside a newer metadata file replays without changing it", staleJournalReplaysHarmlessly),
        ("A journal line missing only its newline is kept, and the next starts its own line", missingNewlineIsRepaired),
        ("Bytes a failed write left are dropped before the next line, never joined to it", failedWriteTailIsDropped),
        ("Version 1 metadata becomes version 2 before any journal line, and copies with the folder", versionOneUpgradesFirst),
        ("A newer metadata version or an unreadable journal keeps both files untouched", newerOrUnreadableFailsClosed),
        ("A refused metadata file is retried each time the journal grows by its limit, not on every change",
         refusedCompactionRetriesAtLimit),
    ]

    private struct Snapshot: Codable {
        let version: Int
        let entries: [SessionMetadata]
    }

    /// A journal line in the shape the archive writes.
    private struct Line: Codable {
        struct Reading: Codable {
            let recordID: UUID
            let observation: PowerObservation
        }
        var upserts: [SessionMetadata] = []
        var removals: [UUID] = []
        var reading: Reading?
    }

    private static func folder() -> URL {
        let directory = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func snapshot(_ folder: URL) -> URL {
        folder.appendingPathComponent("session-metadata.json")
    }

    private static func journal(_ folder: URL) -> URL {
        folder.appendingPathComponent("session-metadata-journal.jsonl")
    }

    private static func journalLines(_ folder: URL) -> Int {
        guard let data = try? Data(contentsOf: journal(folder)) else { return 0 }
        return data.split(separator: 0x0A).count
    }

    private static func reading(_ minutes: Double, percentage: Double = 80) -> PowerObservation {
        PowerObservation(timestamp: SelfTest.base.addingTimeInterval(minutes * 60),
                         source: .battery, percentage: percentage, charging: .notCharging)
    }

    private static func readingIsOneLine() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let noted = UUID(), powered = UUID()
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Seed", for: noted) == .saved, "could not seed a note", &problems)
        let fileBefore = try? Data(contentsOf: snapshot(directory))
        for minute in [0.0, 5, 10] {
            expect(archive.appendPower(reading(minute), for: powered) == .saved,
                   "reading at minute \(minute) was not saved", &problems)
        }
        expect((try? Data(contentsOf: snapshot(directory))) == fileBefore,
               "a power reading rewrote session-metadata.json instead of appending", &problems)
        expect(journalLines(directory) == 3,
               "three readings should be three journal lines, got \(journalLines(directory))", &problems)

        let journalBefore = try? Data(contentsOf: journal(directory))
        let refusing = SessionMetadataArchive(directory: directory, writeOverride: { _ in "Refused." })
        expect(refusing.appendPower(reading(15), for: powered) == .failed("Refused."),
               "a refused append was not reported as failed", &problems)
        expect((try? Data(contentsOf: journal(directory))) == journalBefore
               && (try? Data(contentsOf: snapshot(directory))) == fileBefore,
               "a refused append changed the journal or the metadata file", &problems)

        let reloaded = SessionMetadataArchive(directory: directory)
        expect(reloaded.metadata(for: powered)?.power.count == 3
               && reloaded.metadata(for: noted)?.note == "Seed",
               "a relaunch read \(reloaded.metadata(for: powered)?.power.count ?? 0) readings and note \(reloaded.metadata(for: noted)?.note ?? "nil")",
               &problems)
        expect((try? Data(contentsOf: snapshot(directory))) == fileBefore,
               "a relaunch rewrote session-metadata.json instead of replaying the journal", &problems)
        return problems
    }

    private static func tornMoveIsWhole() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let source = UUID(), destination = UUID()
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Seed", for: source) == .saved, "could not seed a note", &problems)
        expect(archive.appendPower(reading(0), for: source) == .saved
               && archive.appendPower(reading(10), for: source) == .saved,
               "could not seed two readings", &problems)
        expect(archive.reassignPower(from: source, to: destination,
                                     atOrAfter: SelfTest.base.addingTimeInterval(300)) == .saved,
               "could not move the later reading", &problems)
        expect(journalLines(directory) == 3,
               "a move of power should be one journal line after two readings, got \(journalLines(directory)) lines",
               &problems)

        guard let data = try? Data(contentsOf: journal(directory)), data.count > 2 else {
            return problems + ["the journal could not be read to tear its last line"]
        }
        let lastLineStart = data.dropLast().lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
        let torn = data.prefix(upTo: lastLineStart + (data.endIndex - lastLineStart) / 2)
        try? Data(torn).write(to: journal(directory))

        let reloaded = SessionMetadataArchive(directory: directory)
        expect(reloaded.metadata(for: source)?.power.count == 2
               && reloaded.metadata(for: destination) == nil,
               "after a torn move the source has \(reloaded.metadata(for: source)?.power.count ?? 0) readings and the destination \(reloaded.metadata(for: destination)?.power.count ?? 0)",
               &problems)
        expect(reloaded.appendPower(reading(20), for: source) == .saved,
               "metadata stayed read-only after a torn last line", &problems)
        expect(SessionMetadataArchive(directory: directory).metadata(for: source)?.power.count == 3,
               "the reading saved after a torn line did not survive a relaunch", &problems)
        return problems
    }

    private static func unreadableLineFailsClosed() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let recordID = UUID()
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Seed", for: recordID) == .saved
               && archive.appendPower(reading(0), for: recordID) == .saved,
               "could not seed a note and a reading", &problems)
        guard let handle = try? FileHandle(forWritingTo: journal(directory)) else {
            return problems + ["the reading wrote no journal"]
        }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("{\"future\":true}\n".utf8))
        // A change after the unreadable line may depend on it, so it is not shown.
        if let later = try? JSONEncoder().encode(Line(reading: .init(recordID: recordID, observation: reading(3)))) {
            try? handle.write(contentsOf: later + Data([0x0A]))
        }
        try? handle.close()
        let fileBefore = try? Data(contentsOf: snapshot(directory))
        let journalBefore = try? Data(contentsOf: journal(directory))

        let reloaded = SessionMetadataArchive(directory: directory)
        let appended = reloaded.appendPower(reading(5), for: recordID)
        let noted = reloaded.saveNote("Changed", for: recordID)
        expect(appended != .saved && noted != .saved,
               "an unreadable journal line still let writes through (power \(appended), note \(noted))",
               &problems)
        expect((try? Data(contentsOf: snapshot(directory))) == fileBefore
               && (try? Data(contentsOf: journal(directory))) == journalBefore,
               "loading an unreadable journal line changed the metadata file or the journal", &problems)
        expect(reloaded.metadata(for: recordID)?.note == "Seed"
               && reloaded.metadata(for: recordID)?.power.count == 1,
               "the readable metadata is not shown beside the unreadable line", &problems)
        return problems
    }

    private static func removalSurvivesRelaunch() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let kept = UUID(), removed = UUID()
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Kept", for: kept) == .saved
               && archive.appendPower(reading(0), for: kept) == .saved
               && archive.appendPower(reading(5), for: removed) == .saved,
               "could not seed two sessions' metadata", &problems)
        expect(archive.retain(recordIDs: [kept]) == .saved, "could not remove a session's metadata", &problems)
        let reloaded = SessionMetadataArchive(directory: directory)
        expect(reloaded.metadata(for: removed) == nil,
               "removed metadata came back after a relaunch", &problems)
        expect(reloaded.metadata(for: kept)?.note == "Kept" && reloaded.metadata(for: kept)?.power.count == 1,
               "kept metadata changed after a removal and a relaunch", &problems)
        return problems
    }

    private static func journalCompactsAtLimit() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let recordID = UUID()
        let limit = SessionMetadataArchive.journalCompactionThreshold
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Seed", for: recordID) == .saved, "could not seed a note", &problems)
        for index in 0..<(limit - 1) {
            _ = archive.appendPower(reading(Double(index)), for: recordID)
        }
        expect(journalLines(directory) == limit - 1,
               "one reading short of the limit the journal should hold \(limit - 1) lines, got \(journalLines(directory))",
               &problems)
        expect(archive.appendPower(reading(Double(limit)), for: recordID) == .saved,
               "the reading that reaches the limit was not saved", &problems)
        expect(!FileManager.default.fileExists(atPath: journal(directory).path),
               "the journal was not folded into the metadata file at its limit", &problems)
        expect(SessionMetadataArchive(directory: directory).metadata(for: recordID)?.power.count == limit,
               "the folded metadata file does not hold all \(limit) readings", &problems)
        return problems
    }

    /// The journal a snapshot absorbed stays behind when removing it fails.
    private static func staleJournalReplaysHarmlessly() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let kept = UUID(), removed = UUID(), moved = UUID(), bare = UUID()
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Kept", for: kept) == .saved
               && archive.appendPower(reading(2), for: bare) == .saved
               && archive.appendPower(reading(0), for: kept) == .saved
               && archive.appendPower(reading(10), for: kept) == .saved
               && archive.appendPower(reading(1), for: removed) == .saved
               && archive.retain(recordIDs: [kept]) == .saved
               && archive.reassignPower(from: kept, to: moved,
                                        atOrAfter: SelfTest.base.addingTimeInterval(300)) == .saved,
               "could not seed readings, a removal and a move", &problems)
        var minute = 20.0
        while journalLines(directory) < SessionMetadataArchive.journalCompactionThreshold - 1 {
            guard archive.appendPower(reading(minute), for: moved) == .saved else {
                return problems + ["could not fill the journal"]
            }
            minute += 1
        }
        let absorbed = try? Data(contentsOf: journal(directory))
        let last = reading(minute)
        expect(archive.appendPower(last, for: moved) == .saved && journalLines(directory) == 0,
               "the journal did not fold into the metadata file at its limit", &problems)
        let folded = archive.allMetadata
        // The journal as it stood when the snapshot absorbed it, had removing it failed.
        guard let absorbed,
              let lastLine = try? JSONEncoder().encode(Line(reading: .init(recordID: moved, observation: last))) else {
            return problems + ["could not rebuild the absorbed journal"]
        }
        try? (absorbed + lastLine + Data([0x0A])).write(to: journal(directory))
        let reloaded = SessionMetadataArchive(directory: directory)
        expect(reloaded.allMetadata == folded,
               "replaying the absorbed journal changed the metadata (removed back: \(reloaded.metadata(for: removed) != nil))",
               &problems)
        expect(reloaded.appendPower(reading(minute + 1), for: kept) == .saved
               && SessionMetadataArchive(directory: directory).metadata(for: kept)?.power.count == 2,
               "writing after a stale replay did not survive a relaunch", &problems)
        return problems
    }

    private static func missingNewlineIsRepaired() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let recordID = UUID()
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Seed", for: recordID) == .saved
               && archive.appendPower(reading(0), for: recordID) == .saved,
               "could not seed a note and a reading", &problems)
        if let data = try? Data(contentsOf: journal(directory)), data.last == 0x0A {
            try? data.dropLast().write(to: journal(directory))
        } else {
            problems.append("the reading wrote no ended journal line")
        }
        let reloaded = SessionMetadataArchive(directory: directory)
        expect(reloaded.metadata(for: recordID)?.power.count == 1,
               "a line missing only its newline was lost", &problems)
        expect(reloaded.appendPower(reading(5), for: recordID) == .saved
               && SessionMetadataArchive(directory: directory).metadata(for: recordID)?.power.count == 2,
               "the line after a repaired one did not survive a relaunch", &problems)
        return problems
    }

    private static func failedWriteTailIsDropped() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let recordID = UUID()
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.saveNote("Seed", for: recordID) == .saved
               && archive.appendPower(reading(0), for: recordID) == .saved,
               "could not seed a note and a reading", &problems)
        guard let handle = try? FileHandle(forWritingTo: journal(directory)) else {
            return problems + ["the reading wrote no journal"]
        }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("{\"reading\":{\"recordID\":\"".utf8))
        try? handle.close()
        expect(archive.appendPower(reading(5), for: recordID) == .saved,
               "the reading after a failed write was not saved", &problems)
        let reloaded = SessionMetadataArchive(directory: directory)
        expect(reloaded.metadata(for: recordID)?.power.count == 2,
               "a relaunch read \(reloaded.metadata(for: recordID)?.power.count ?? 0) of 2 saved readings", &problems)
        expect(reloaded.appendPower(reading(10), for: recordID) == .saved,
               "metadata went read-only after a failed write's bytes", &problems)
        return problems
    }

    private static func versionOneUpgradesFirst() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let recordID = UUID()
        let original = SessionMetadata(recordID: recordID, note: "Written by version 1",
                                       power: [reading(0)])
        try? JSONEncoder().encode(Snapshot(version: 1, entries: [original])).write(to: snapshot(directory))
        let archive = SessionMetadataArchive(directory: directory)
        expect(archive.appendPower(reading(5), for: recordID) == .saved,
               "a reading on version 1 metadata was not saved", &problems)
        let upgraded = (try? Data(contentsOf: snapshot(directory)))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        expect(upgraded?.version == 2 && upgraded?.entries.first?.power.count == 2
               && upgraded?.entries.first?.note == "Written by version 1",
               "the first change did not rewrite version 1 as version 2 with everything in it (version \(upgraded?.version ?? 0))",
               &problems)
        expect(journalLines(directory) == 0, "a journal line was written beside version 1 metadata", &problems)
        expect(archive.appendPower(reading(10), for: recordID) == .saved && journalLines(directory) == 1,
               "the next reading did not go to the journal", &problems)

        let copy = folder()
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: directory, to: copy)
        expect(SessionMetadataArchive(directory: copy).metadata(for: recordID)?.power.count == 3,
               "a copy of the data folder lost the journalled reading", &problems)
        return problems
    }

    private static func newerOrUnreadableFailsClosed() -> [String] {
        var problems: [String] = []
        let recordID = UUID()

        let newer = folder()
        try? JSONEncoder().encode(Snapshot(version: 3, entries: [SessionMetadata(recordID: recordID)]))
            .write(to: snapshot(newer))
        try? Data("{\"upserts\":[],\"removals\":[]}\n".utf8).write(to: journal(newer))
        let newerBefore = SessionMetadataChecks.sidecarBytes(in: newer)
        let newerArchive = SessionMetadataArchive(directory: newer)
        expect(newerArchive.appendPower(reading(0), for: recordID) != .saved
               && SessionMetadataChecks.sidecarBytes(in: newer) == newerBefore,
               "a newer version's metadata was written to", &problems)

        let locked = folder()
        let archive = SessionMetadataArchive(directory: locked)
        expect(archive.saveNote("Seed", for: recordID) == .saved
               && archive.appendPower(reading(0), for: recordID) == .saved,
               "could not seed a note and a reading", &problems)
        let lockedBefore = SessionMetadataChecks.sidecarBytes(in: locked)
        let path = journal(locked).path
        try? FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
        guard (try? Data(contentsOf: journal(locked))) == nil else {
            return problems + ["the journal stayed readable, so nothing was tested"]
        }
        let blind = SessionMetadataArchive(directory: locked)
        expect(blind.saveNote("Changed", for: recordID) != .saved
               && blind.appendPower(reading(5), for: recordID) != .saved,
               "metadata was written while its journal could not be read", &problems)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        expect(SessionMetadataChecks.sidecarBytes(in: locked) == lockedBefore
               && SessionMetadataArchive(directory: locked).metadata(for: recordID)?.power.count == 1,
               "an unreadable journal was changed or lost its reading", &problems)
        return problems
    }

    private static func refusedCompactionRetriesAtLimit() -> [String] {
        var problems: [String] = []
        let directory = folder()
        let recordID = UUID()
        let limit = SessionMetadataArchive.journalCompactionThreshold
        expect(SessionMetadataArchive(directory: directory).saveNote("Seed", for: recordID) == .saved,
               "could not seed a note", &problems)
        var snapshotAttempts = 0
        // Journal lines are compact JSON; only the metadata file has "version" in it.
        let archive = SessionMetadataArchive(directory: directory, writeOverride: { data in
            guard String(decoding: data, as: UTF8.self).contains("\"version\"") else { return nil }
            snapshotAttempts += 1
            return "Metadata file refused."
        })
        var saved = 0
        for index in 0..<(limit + 20) {
            if archive.appendPower(reading(Double(index)), for: recordID) == .saved { saved += 1 }
        }
        expect(saved == limit + 20 && snapshotAttempts == 1,
               "with the metadata file refused, \(saved) of \(limit + 20) readings saved and it was tried \(snapshotAttempts) times",
               &problems)
        expect(SessionMetadataArchive(directory: directory).metadata(for: recordID)?.power.count == limit + 20,
               "the journal did not keep every reading while the metadata file was refused", &problems)
        return problems
    }
}
