import Foundation

/// Settings checks remain separate from the older broad self-test so their
/// bounds, persistence and native-appearance contract stay explicit.
enum StorySettingsChecks {
    static let tests: [(String, () -> [String])] = [
        ("Settings compactly groups every backed preference", pagesAndSearch),
        ("Settings preferences persist without widening their contract", persistence),
        ("Settings sheets are bounded without leaving General blank", sheetBounds)
    ]

    private static func pagesAndSearch() -> [String] {
        var failures: [String] = []
        let expectedPages: [(SettingsPage, [SettingsSection])] = [
            (.general, [.general, .appearance]),
            (.sessions, [.focus, .categories, .automatic]),
            (.activities, [.activities]),
            (.awayAndBreaks, [.away]),
            (.recording, [.tracking]),
            (.privacy, [.data, .advanced])
        ]
        if SettingsPage.allCases.map(\.title) != ["General", "Sessions", "Activities", "Away & Breaks", "Recording", "Privacy"] {
            failures.append("Settings did not expose the six page groups in their required order")
        }
        for (page, sections) in expectedPages where page.sections != sections {
            failures.append("\(page.title) no longer contains its intended logical settings sections")
        }
        if SettingsPage.matching("recent app visits") != [.recording] {
            failures.append("Searching the actual recent app visits control did not retain Recording context")
        }
        if SettingsPage.matching("Story timestamps") != [.general] {
            failures.append("Searching Story timestamps did not retain General context")
        }
        if SettingsPage.matching("recovery") != [.privacy] {
            failures.append("Searching recovery did not retain Privacy context")
        }
        if SettingsPage.matching("new category") != [.sessions] {
            failures.append("Searching new category did not retain Sessions context")
        }
        let listed = SettingsPage.allCases.flatMap(\.sections).flatMap(\.mutableControlKeys)
        if Set(listed) != Set(SettingsControlKey.allCases) || Set(listed).count != listed.count {
            failures.append("A backed control is missing from a page or appears in more than one page")
        }
        return failures
    }

    private static func persistence() -> [String] {
        let suite = "com.prabesh.focuscontinuity.story-settings.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-story-settings-\(UUID().uuidString)", isDirectory: true)
        guard let defaults = UserDefaults(suiteName: suite) else {
            return ["Could not create isolated Settings defaults"]
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        var failures: [String] = []
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        var trackingChanges: [Bool] = []
        var revealedDirectories: [URL] = []
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { trackingChanges.append($0) },
                                     dataDirectory: directory,
                                     openDataFolder: { url in
                                         revealedDirectories.append(url)
                                         return true
                                     })
        settings.defaultStoryScope = .month
        settings.sessionControlsPinned = true
        settings.dailyGoal = FocusConstants.dailyGoalOptions.last ?? settings.dailyGoal
        settings.breakThreshold = FocusConstants.thresholdOptions.last ?? settings.breakThreshold
        settings.longAwayCap = FocusConstants.longAwayCapOptions.last ?? settings.longAwayCap
        settings.fullPromptAfter = FocusConstants.fullPromptAfterOptions.last ?? 0
        settings.remindersEnabled = false
        settings.autoSessionsEnabled = false
        settings.breakLength = FocusConstants.breakLengthOptions.last ?? settings.breakLength
        settings.rewardsEnabled = false
        settings.menuSessionCount = 10
        settings.appearancePreference = .dark
        settings.interfaceDensity = .compact
        settings.showsTimelineLabels = false
        settings.expandsEntryDetails = true
        settings.isTrackingEnabled = false
        let reloaded = SettingsModel(store: store, isTrackingEnabled: false,
                                     onChange: {}, onTrackingChanged: { _ in })
        if reloaded.defaultStoryScope != .month || !reloaded.sessionControlsPinned
            || reloaded.dailyGoal != settings.dailyGoal
            || reloaded.breakThreshold != settings.breakThreshold
            || reloaded.longAwayCap != settings.longAwayCap
            || reloaded.fullPromptAfter != settings.fullPromptAfter
            || reloaded.remindersEnabled != settings.remindersEnabled
            || reloaded.autoSessionsEnabled != settings.autoSessionsEnabled
            || reloaded.breakLength != settings.breakLength
            || reloaded.rewardsEnabled != settings.rewardsEnabled
            || reloaded.menuSessionCount != 10
            || reloaded.appearancePreference != .dark || reloaded.interfaceDensity != .compact
            || reloaded.showsTimelineLabels || !reloaded.expandsEntryDetails {
            failures.append("A compact Settings page did not round-trip every written backed preference")
        }
        if trackingChanges != [false] || reloaded.isTrackingEnabled {
            failures.append("Recording control did not use its coordinator-backed tracking callback")
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if settings.dataDirectoryURL.resolvingSymlinksInPath()
                != directory.resolvingSymlinksInPath() {
                failures.append("Privacy reported a directory other than its injected fixture directory")
            }
            settings.revealDataFolder()
            if revealedDirectories.map({ $0.resolvingSymlinksInPath() })
                != [directory.resolvingSymlinksInPath()] {
                failures.append("Privacy reveal did not send its injected fixture directory to the open callback")
            }
            let backup = directory.appendingPathComponent("app-usage-v1-backup-1800000000.json")
            try Data("evidence".utf8).write(to: backup)
            if SettingsDiagnostics.latestLegacyBackup(in: directory)?.resolvingSymlinksInPath()
                != backup.resolvingSymlinksInPath() {
                failures.append("Privacy diagnostics did not stay inside the isolated temporary directory")
            }
        } catch {
            failures.append("Could not prepare isolated Settings diagnostic evidence: \(error)")
        }
        return failures
    }

    private static func sheetBounds() -> [String] {
        var failures: [String] = []
        for section in SettingsSection.allCases {
            let height = SettingsLayout.sheetHeight(section: section, query: "")
            if height > SettingsLayout.sheetMaximumHeight || height < 49 {
                failures.append("\(section.title) sheet height \(height) escapes the stable native-sheet bound")
            }
        }
        let heights = SettingsSection.allCases.flatMap { section in
            [SettingsLayout.sheetHeight(section: section, query: ""),
             SettingsLayout.sheetHeight(section: section, query: "appearance")]
        }
        if Set(heights).count != 1 {
            failures.append("Settings category or search changed the stable sheet frame")
        }
        return failures
    }

}
