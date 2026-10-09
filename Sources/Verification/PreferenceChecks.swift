import Foundation

/// A preference changed in Settings takes effect at once, not at the next
/// launch, and a category the user picked is not reset behind their back.
enum PreferenceChecks {
    static let tests: [(String, () -> [String])] = [
        ("Settings changes reach the menu bar, streaks and suggestions without a relaunch", settingsApplyAtOnce),
        ("A streak cached under one minimum is not reused under another", streakCacheFollowsMinimum),
        ("New sessions start as the saved category, and a picked category survives a refresh", pendingCategory),
        ("A default changed during a session applies once the session ends", defaultChangedMidSession),
        ("Pausing one music player does not silence another that is still playing", musicPlayers)
    ]

    /// Noon, so no fixture straddles midnight.
    private static let noon = Date(timeIntervalSince1970: 1_700_000_000).roundedToNoon

    private final class Fixture {
        let suite = "fc.preferences.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-preferences-\(UUID().uuidString)", isDirectory: true)
        let persistence: PersistenceStore
        let archive: SessionArchive
        let engine: SessionEngine
        lazy var store = SessionStore(engine: engine, schedulesTicker: false, now: { PreferenceChecks.noon })
        lazy var settings = SettingsModel(store: persistence, isTrackingEnabled: false,
                                          onChange: { [unowned self] in self.store.refresh() },
                                          onTrackingChanged: { _ in },
                                          dataDirectory: directory)

        init() {
            persistence = PersistenceStore(defaults: MemoryDefaults.suite(named: suite) ?? .standard)
            persistence.removeAll()
            archive = SessionArchive(directory: directory, now: { PreferenceChecks.noon })
            engine = SessionEngine(store: persistence, archive: archive, ownBundleID: "fc.preferences.test",
                                   schedulesDwell: false, now: { PreferenceChecks.noon })
        }

        func close() {
            MemoryDefaults.suite(named: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func settingsApplyAtOnce() -> [String] {
        var failures: [String] = []
        let fixture = Fixture()
        defer { fixture.close() }
        // Ten minutes today: below the default 25-minute streak minimum. And a
        // named session 30 days ago: outside the default 14-day suggestions.
        _ = fixture.archive.append(SessionRecord(name: "Today", workType: .deepWork,
                                                 start: noon.addingTimeInterval(-1_200),
                                                 end: noon.addingTimeInterval(-600), workSeconds: 600))
        let monthAgo = noon.addingTimeInterval(-30 * 86_400)
        _ = fixture.archive.append(SessionRecord(name: "Old plan", workType: .deepWork, start: monthAgo,
                                                 end: monthAgo.addingTimeInterval(600), workSeconds: 600))
        fixture.store.refresh()
        let before = (fixture.store.streak, fixture.store.quickStarts.contains { $0.name == "Old plan" })

        fixture.settings.menuBarShowsTime = false
        fixture.settings.suggestionWindowDays = 90
        fixture.settings.streakMinimum = 300
        if fixture.store.menuBarShowsTime {
            failures.append("menu bar time: saved false, still showing")
        }
        if fixture.archive.quickStartWindowDays != 90 {
            failures.append("suggestion window: saved 90, archive uses \(fixture.archive.quickStartWindowDays)")
        }
        if fixture.archive.streakMinimum != 300 {
            failures.append("streak minimum: saved 300, archive uses \(fixture.archive.streakMinimum)")
        }
        // What the screens show, not only the copies behind them.
        let after = (fixture.store.streak, fixture.store.quickStarts.contains { $0.name == "Old plan" })
        if before != (0, false) || after != (1, true) {
            failures.append("shown streak and suggestion: expected (0, false) then (1, true), got \(before) then \(after)")
        }
        return failures
    }

    private static func streakCacheFollowsMinimum() -> [String] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-streak-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = SessionArchive(directory: directory, now: { noon })
        _ = archive.append(SessionRecord(name: "Ten minutes", workType: .deepWork,
                                         start: noon.addingTimeInterval(-1_200),
                                         end: noon.addingTimeInterval(-600), workSeconds: 600))
        archive.streakMinimum = 1_500
        let strict = (archive.currentStreak(), archive.bestStreak())
        archive.streakMinimum = 300
        let loose = (archive.currentStreak(), archive.bestStreak())
        return strict == (0, 0) && loose == (1, 1) ? []
            : ["expected streaks (0, 0) then (1, 1), got \(strict) then \(loose)"]
    }

    private static func pendingCategory() -> [String] {
        var failures: [String] = []
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.persistence.defaultWorkType = .learning
        fixture.store.refresh()
        if fixture.store.workType != .learning {
            failures.append("saved default learning, selected \(fixture.store.workType)")
        }
        fixture.store.workType = .admin
        fixture.store.refresh()
        if fixture.store.workType != .admin {
            failures.append("picked admin, a refresh reset it to \(fixture.store.workType)")
        }
        return failures
    }

    private static func defaultChangedMidSession() -> [String] {
        var failures: [String] = []
        let fixture = Fixture()
        defer { fixture.close() }
        _ = fixture.engine.start(workType: .admin, intent: "Invoices")
        fixture.store.refresh()
        fixture.persistence.defaultWorkType = .learning
        fixture.store.refresh()
        if fixture.store.workType != .admin {
            failures.append("while running, the picker should show the session's admin, got \(fixture.store.workType)")
        }
        _ = fixture.engine.stop()
        fixture.store.refresh()
        if fixture.store.workType != .learning {
            failures.append("after the session, the new default learning should apply, got \(fixture.store.workType)")
        }
        return failures
    }

    private static func musicPlayers() -> [String] {
        var music = MusicPlayback()
        music.update(player: "com.apple.Music.playerInfo", state: "Playing")
        music.update(player: "com.spotify.client.PlaybackStateChanged", state: "Paused")
        let stillPlaying = music.isPlaying
        music.update(player: "com.apple.Music.playerInfo", state: "Stopped")
        return stillPlaying && !music.isPlaying ? []
            : ["Music playing and Spotify paused should read playing, then silent once Music stops"]
    }
}

private extension Date {
    var roundedToNoon: Date { Calendar.current.startOfDay(for: self).addingTimeInterval(12 * 3_600) }
}
