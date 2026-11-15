import Foundation

extension FixtureFactory {
    /// History's first view over a record of three lengths, every day counted
    /// back from today: about four months inside this year (root rows are
    /// months), about fourteen months over two years (years), or this month
    /// alone (weeks).
    /// shortcut: a record is clipped to the start of its year or month, so from
    /// January to March the months record holds fewer months, and in a month's
    /// first week the month record opens on days; that is the calendar, not a bug.
    static func historyFrontStore(for scenario: SnapshotScenario) -> SessionStore {
        let calendar = Calendar.current.forPeriods
        let today = calendar.startOfDay(for: Date())
        let thisYear = HistoryTreeBuilder.period(.year, containing: today, calendar: calendar).start
        let first: Date
        switch scenario {
        case .historyFrontYears:
            let lastYear = calendar.date(byAdding: .year, value: -1, to: thisYear) ?? thisYear
            first = max(lastYear, calendar.date(byAdding: .month, value: -14, to: today) ?? today)
        case .historyFrontMonth:
            first = HistoryTreeBuilder.period(.month, containing: today, calendar: calendar).start
        default:
            first = max(thisYear, calendar.date(byAdding: .month, value: -4, to: today) ?? today)
        }
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today) ?? today

        let preferences = PersistenceStore(defaults: fixtureDefaults(scenario.rawValue))
        // A made category in Meetings' hue, so the split bar mutes one of a pair.
        let calls = WorkType(rawValue: "custom.snapshot.history.calls")
        preferences.workTypeDefinitions = [
            WorkTypeDefinition(id: calls.rawValue, name: "Client calls", symbolName: "phone.fill",
                               hue: .orange, countsWhileWatching: true)
        ]
        // A week of minutes by category: a day off, then every step of the
        // ramp from under 2h to 8h and more. Admin stays just over 3%.
        let week: [[(WorkType, Int)]] = [
            [],
            [(.deepWork, 60), (.admin, 20)],
            [(.deepWork, 120), (.meetings, 60), (calls, 30)],
            [(.deepWork, 200), (.meetings, 60), (calls, 40), (.admin, 20)],
            [(.deepWork, 360), (.meetings, 90), (calls, 60)],
            [(.deepWork, 150), (.meetings, 45), (calls, 30), (.admin, 15)],
            [(.deepWork, 90)]
        ]
        var records: [SessionRecord] = []
        var usage: [AppUsageSession] = []
        var day = first
        var index = 0
        while day <= today {
            // Today's work ends before the fixture's noon.
            var sessions = day == today ? [(WorkType.deepWork, 90)] : week[index % week.count]
            // Learning, an hour a month, folds into Other (about 1%).
            if index % 30 == 3 { sessions.append((.learning, 60)) }
            let opening = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            var start = opening
            for (workType, minutes) in sessions {
                let end = start.addingTimeInterval(Double(minutes * 60))
                records.append(SessionRecord(name: "", workType: workType, start: start, end: end,
                                             workSeconds: Double(minutes * 60)))
                start = end
            }
            if start > opening {
                usage.append(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                             start: opening, end: start))
            }
            day = HistoryTreeBuilder.dayAfter(day, calendar: calendar)
            index += 1
        }

        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // One write each: appending day by day rewrote the file hundreds of times.
        let envelope = UsageFixtureEnvelope(metadata: AppUsageMetadata(accurateFrom: first), sessions: usage)
        if let bytes = try? JSONEncoder().encode(envelope) {
            try? bytes.write(to: directory.appendingPathComponent("app-usage.json"), options: .atomic)
        }
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { now })
        _ = archive.edit(adding: records)
        let engine = SessionEngine(store: preferences, archive: archive,
                                   ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false, now: { now })
        let usageArchive = AppUsageArchive(directory: directory, calendar: calendar, now: { now })
        let tracker = AppUsageTracker(archive: usageArchive, ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled, now: { now })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { now })
        store.attach(tracker: tracker, usage: usageArchive)
        store.refresh()
        return store
    }
}
