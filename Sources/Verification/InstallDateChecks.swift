import Foundation

/// History starts the day before Daybook was installed on this Mac. A record
/// dated earlier is malformed: one dated about 4713 BC made History build some
/// 6,700 year rows and stall. The install date is saved once, from when the
/// history folder was created, which no record can move.
enum InstallDateChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The install date is saved once, from when the history folder was created, and never ahead of the clock",
         installDateComesFromFolder),
        ("History leaves out and discloses records from before the install date, and keeps the day before it",
         historyStartsAtInstall),
    ]

    private static func installDateComesFromFolder() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-install-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated defaults suite"] }
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let now = SelfTest.anchoredNow()
        let created = now.addingTimeInterval(-50 * 86_400)
        let folder = folderCreated(at: created)
        let store = PersistenceStore(defaults: defaults)

        expect(store.installDate == nil, "a new store should have no install date, got \(String(describing: store.installDate))",
               &problems)
        PersistenceStore.recordInstallDate(folder: folder, now: now, in: defaults)
        expect(store.installDate.map { abs($0.timeIntervalSince(created)) < 1 } == true,
               "the install date should be the folder's creation, \(created), got \(String(describing: store.installDate))",
               &problems)

        PersistenceStore.recordInstallDate(folder: folderCreated(at: now), now: now, in: defaults)
        expect(store.installDate.map { abs($0.timeIntervalSince(created)) < 1 } == true,
               "a saved install date should never move, got \(String(describing: store.installDate))", &problems)

        store.removeAll()
        expect(store.installDate == nil,
               "clearing the store should clear the install date, got \(String(describing: store.installDate))", &problems)

        // No folder yet is a fresh install before its first save, and a folder
        // dated ahead of the clock cannot be trusted: neither saves anything.
        PersistenceStore.recordInstallDate(folder: SelfTest.scratchDirectory(), now: now, in: defaults)
        expect(store.installDate == nil,
               "with no folder nothing should be saved, got \(String(describing: store.installDate))", &problems)
        PersistenceStore.recordInstallDate(folder: folderCreated(at: now.addingTimeInterval(86_400)), now: now, in: defaults)
        expect(store.installDate == nil,
               "a folder dated ahead of the clock should save nothing, got \(String(describing: store.installDate))",
               &problems)

        // A saved date ahead of the clock, or a value that is not a date, is
        // worked out again rather than hiding history for good.
        for wrong in [now.addingTimeInterval(365 * 86_400) as Any, "not a date" as Any] {
            defaults.set(wrong, forKey: "fc.installDate")
            PersistenceStore.recordInstallDate(folder: folder, now: now, in: defaults)
            expect(store.installDate.map { abs($0.timeIntervalSince(created)) < 1 } == true,
                   "a saved \(wrong) should be replaced by the folder's creation, got \(String(describing: store.installDate))",
                   &problems)
        }
        return problems
    }

    private static func historyStartsAtInstall() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let clock = TestClock(SelfTest.anchoredNow())
            let installed = clock.value.addingTimeInterval(-10 * 86_400)
            let installDay = calendar.startOfDay(for: installed)
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: installDay) else {
                return ["no day before the install day"]
            }
            // Where Calendar clamps a stored date of -1e300.
            let ancient = Date(timeIntervalSinceReferenceDate: -211_845_140_000)
            // The first session can start before the app first saves.
            let evening = dayBefore.addingTimeInterval(20 * 3_600)
            let records = [
                SessionRecord(name: "Corrupted date", workType: .deepWork, start: ancient,
                              end: ancient.addingTimeInterval(3_600), workSeconds: 3_600),
                SessionRecord(name: "First session", workType: .deepWork, start: evening,
                              end: evening.addingTimeInterval(3_600), workSeconds: 3_600),
                SessionRecord(name: "Today", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-2 * 3_600),
                              end: clock.value.addingTimeInterval(-3_600), workSeconds: 3_600)
            ]
            let usageSessions = [
                AppUsageSession(bundleID: "org.example.old", appName: "Old",
                                start: ancient, end: ancient.addingTimeInterval(600))
            ]

            // The builder itself: no install date leaves History as it was.
            let unbounded = HistoryStats.build(sessionRecords: records, usage: usageSessions, calendar: calendar)
            expect(unbounded.days.contains { $0.date < dayBefore },
                   "with no install date History should keep every record as before", &problems)
            let bounded = HistoryStats.build(sessionRecords: records, usage: usageSessions,
                                             calendar: calendar, installedOn: installed)
            expect(bounded.droppedBeforeInstall == 2,
                   "two records predate the install date, got \(bounded.droppedBeforeInstall)", &problems)

            // The store, with the date saved the way launch saves it.
            let suite = "fc-selftest-install-\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated defaults suite"] }
            defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
            PersistenceStore.recordInstallDate(folder: folderCreated(at: installed), now: clock.value, in: defaults)
            let usage = SelfTest.makeUsageArchive(clock, sessions: usageSessions)
            let archive = SelfTest.makeArchive(clock, records: records, calendar: calendar)
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            // A decision receipt adds its own days to History after the builder.
            var saved = engine.snapshot()
            saved.awayDecisions = [AwayDecisionReceipt(
                id: UUID(), range: DateInterval(start: ancient, end: ancient.addingTimeInterval(600)),
                name: "Corrupted away", workType: .breakTime, threadID: UUID(), sessionStart: ancient,
                decision: .tookBreak, insertedRecord: nil, creditedSeconds: 0)]
            engine.restore(from: saved)
            expect(engine.awayDecisions.count == 1,
                   "the check should plant one corrupted receipt, got \(engine.awayDecisions.count)", &problems)
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview()

            let oldest = store.historyDays.map(\.date).min()
            expect(oldest == dayBefore,
                   "History should start on the day before the install day, \(dayBefore), got \(String(describing: oldest))",
                   &problems)
            expect(store.historyIntegrityNotices.contains {
                $0.contains("2 records") && $0.contains("before Daybook was installed")
                    && $0.contains(Tokens.longDate(installed))
                    && $0.localizedCaseInsensitiveContains("source records remain preserved")
            }, "History should disclose the 2 records from before the install date, got \(store.historyIntegrityNotices)",
                   &problems)
            expect(archive.records == records && usage.sessions == usageSessions,
                   "leaving records out of History should never rewrite either source archive", &problems)

            // A live update rebuilds from the oldest changed day, which an
            // app-use record dated far back moves to that record's day.
            let checkpointed = usage.checkpoint(AppUsageSession(
                bundleID: "org.example.older", appName: "Older",
                start: ancient.addingTimeInterval(7_200), end: ancient.addingTimeInterval(7_800)))
            expect(checkpointed, "the check should save a far-back app-use record", &problems)
            store.refreshReview(rebuildingHistory: false)
            let liveOldest = store.historyDays.map(\.date).min()
            expect(liveOldest == dayBefore,
                   "after a live update History should still start on \(dayBefore), got \(String(describing: liveOldest))",
                   &problems)
            return problems
        }
    }

    /// A scratch folder whose creation date is `date`, as the system stamps it.
    private static func folderCreated(at date: Date) -> URL {
        let folder = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: folder.path)
        return folder
    }
}
