import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Historical focus remains a raw session statistic, but every goal claim
    /// must use the same declared-session ∩ authoritative-hands-on measure as
    /// today. Five unattended session hours cannot meet a four-hour goal when
    /// only one hour intersects app usage.
    static func testHistoricalGoalStatusUsesFocusedActiveTime() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.value)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let accurateFrom = calendar.date(byAdding: .day, value: -1, to: yesterday) else {
            return ["could not make authoritative historical days"]
        }
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, calendar: calendar,
                                     now: { clock.value })
        archive.append(SessionRecord(name: "Unattended build", workType: .deepWork,
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(14 * 3_600),
                                     workSeconds: 5 * 3_600))
        let usage = AppUsageArchive(directory: directory, calendar: calendar,
                                    now: { accurateFrom })
        usage.record(AppUsageSession(bundleID: "com.example.editor", appName: "Editor",
                                     start: yesterday.addingTimeInterval(9 * 3_600),
                                     end: yesterday.addingTimeInterval(10 * 3_600)))

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        persistence.dailyGoal = 4 * 3_600
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self",
                                   schedulesDwell: false, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.selectDay(offset: 1)

        expectClose(store.focusedForSelectedDay, 5 * 3_600,
                    "the historical Focused statistic retains raw session work", &problems)
        expectClose(store.selectedDayGoal.achieved, 3_600,
                    "the historical goal ring uses focused-active time", &problems)
        expect(!store.selectedDayGoal.isMet,
               "one hands-on hour cannot meet a four-hour historical goal", &problems)
        let daySummary = SummaryText.plain(store.summarySentences)
        expect(daySummary.contains("3h short of the 4h goal"),
               "historical shortfall copy uses focused-active achievement: \(daySummary)",
               &problems)

        store.period = .week
        let periodSummary = SummaryText.plain(store.summarySentences)
        expect(periodSummary.contains("without meeting the 4h goal on any day"),
               "period goal-day status uses focused-active achievement: \(periodSummary)",
               &problems)
        return problems
    }

    // MARK: - 80

    /// Seven distinct app colours in both appearances, clamped past the end,
    /// and a total work-type mapping. Pins the palette so a later edit cannot
    /// quietly give two apps one colour or leave a work type on a default.
    static func testPalette() -> [String] {
        var problems: [String] = []
        for dark in [false, true] {
            var seen: Set<String> = []
            for rank in 0..<7 {
                let c = Tokens.Palette.resolved(rank: rank, dark: dark)
                seen.insert(String(format: "%.3f-%.3f-%.3f", c.r, c.g, c.b))
            }
            expect(seen.count == 7,
                   "seven distinct app colours in \(dark ? "dark" : "light"), got \(seen.count)",
                   &problems)
        }
        let light0 = Tokens.Palette.resolved(rank: 0, dark: false)
        let dark0 = Tokens.Palette.resolved(rank: 0, dark: true)
        expect(light0 != dark0, "the pair flips with the appearance", &problems)
        let beyond = Tokens.Palette.resolved(rank: 42, dark: false)
        let other = Tokens.Palette.resolved(rank: 6, dark: false)
        expect(beyond == other, "ranks past the end read as Other", &problems)
        let negative = Tokens.Palette.resolved(rank: -1, dark: false)
        let first = Tokens.Palette.resolved(rank: 0, dark: false)
        expect(negative == first, "a negative rank clamps to the first", &problems)
        for type in WorkType.allCases {
            _ = Tokens.Palette.workType(type)   // total: every case compiles to a colour
        }
        return problems
    }

    // MARK: - 81

    /// The status-item ring renders for every state it can be in. A nil image
    /// would fall back to the infinity glyph silently, which is exactly the
    /// kind of quiet regression a test exists to shout about.
    static func testMenuBarGlyph() -> [String] {
        var problems: [String] = []
        let states: [(Double, Bool, Bool, Bool)] = [
            (0, false, false, false), (0.63, false, false, false),
            (0.63, true, false, false), (0.63, false, true, false),
            (1.0, false, false, true)
        ]
        for (progress, paused, attention, met) in states {
            // Booleans out, not the image: `NSImage` is not `Sendable` before
            // macOS 14, and the result only needs to say what was rendered.
            let result: (exists: Bool, template: Bool, sized: Bool) = MainActor.assumeIsolated {
                let image = MenuBarGlyph.image(progress: progress, paused: paused,
                                               attention: attention, isMet: met)
                return (image != nil,
                        image?.isTemplate == true,
                        image.map { $0.size.width == 16 && $0.size.height == 16 } == true)
            }
            expect(result.exists, "glyph renders for progress \(progress) paused \(paused) "
                   + "attention \(attention) met \(met)", &problems)
            expect(result.template, "and is a template image", &problems)
            expect(result.sized, "at 16×16 points", &problems)
        }
        return problems
    }

    // MARK: - 82

    /// Every settings write lands in the store and fires `onChange` exactly
    /// once, so the surfaces that read the store refresh, and a tracking toggle
    /// reaches the owner of the tracker rather than only the preference.
    static func testSettingsModel() -> [String] {
        var problems: [String] = []
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        var changes = 0
        var tracking: [Bool] = []
        var revealCount = 0
        let model = SettingsModel(store: store, isTrackingEnabled: true,
                                  onChange: { changes += 1 },
                                  onTrackingChanged: { tracking.append($0) },
                                  revealDataFolder: { revealCount += 1 })

        model.dailyGoal = 2 * 3_600
        expectClose(store.dailyGoal, 2 * 3_600, "daily goal writes through", &problems)
        model.autoSessionsEnabled = false
        expect(store.autoSessionsEnabled == false, "auto sessions write through", &problems)
        model.rewardsEnabled = false
        expect(store.rewardsEnabled == false, "rewards write through", &problems)
        model.remindersEnabled = false
        expect(store.remindersEnabled == false, "reminders write through", &problems)
        model.breakThreshold = 1_800
        expectClose(store.breakThreshold, 1_800, "ask-me-after writes through", &problems)
        model.longAwayCap = 2 * 3_600
        expectClose(store.longAwayCap, 2 * 3_600, "end-after writes through", &problems)
        model.breakLength = 15 * 60
        expectClose(store.breakLength, 15 * 60, "auto-session gap writes through", &problems)
        model.menuSessionCount = 7
        expect(store.menuSessionCount == 7, "sessions per app writes through", &problems)
        model.fullPromptAfter = 3_600
        expectClose(store.fullPromptAfter ?? -1, 3_600, "full-prompt threshold writes through", &problems)
        model.fullPromptAfter = 0
        expect(store.fullPromptAfter == nil, "zero means Never", &problems)
        expect(changes == 10, "one change notification per write, got \(changes)", &problems)

        model.isTrackingEnabled = false
        expect(tracking == [false], "tracking goes to the tracker's owner", &problems)
        expect(model.isTrackingEnabled == false, "and the model remembers it", &problems)
        expect(changes == 10, "tracking does not double-fire onChange", &problems)
        model.revealDataFolder()
        expect(revealCount == 1, "Reveal data folder invokes its read-only action", &problems)
        expect(changes == 10 && tracking == [false],
               "revealing data changes no setting and sends no preference callback", &problems)
        return problems
    }

    // MARK: - 83

    /// Navigation defaults are user-facing preferences and therefore first-class
    /// persisted settings; corrupted values should never crash the app.
    static func testMainNavigationAndInterfacePreferences() -> [String] {
        var problems: [String] = []
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()

        var preferenceChanges = 0
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                    onChange: { preferenceChanges += 1 },
                                    onTrackingChanged: { _ in })

        expect(settings.defaultAppTab == .focus, "Focus is the default tab", &problems)
        expect(settings.interfaceDensity == .comfortable, "Comfortable is the default density", &problems)
        expect(settings.appearancePreference == .system, "System is the default appearance preference", &problems)
        expect(settings.showsTimelineLabels == true, "Timeline labels are visible by default", &problems)

        expect(AppTab.focus.moved(by: -1) == .settings, "left wrap works", &problems)
        expect(AppTab.settings.moved(by: 1) == .focus, "right wrap works", &problems)

        settings.defaultAppTab = .today
        expect(preferenceChanges == 1, "default tab notifies exactly once", &problems)
        settings.interfaceDensity = .compact
        expect(preferenceChanges == 2, "density notifies exactly once", &problems)
        settings.appearancePreference = .dark
        expect(preferenceChanges == 3, "appearance preference notifies exactly once", &problems)
        settings.showsTimelineLabels = false
        expect(preferenceChanges == 4, "timeline labels preference notifies exactly once", &problems)

        let reloadedSettings = SettingsModel(store: store, isTrackingEnabled: true,
                                            onChange: { },
                                            onTrackingChanged: { _ in })
        expect(reloadedSettings.defaultAppTab == .today, "default tab persists", &problems)
        expect(reloadedSettings.interfaceDensity == .compact, "density persists", &problems)
        expect(reloadedSettings.appearancePreference == .dark, "appearance preference persists", &problems)
        expect(reloadedSettings.showsTimelineLabels == false, "timeline labels preference persists", &problems)

        store.defaultAppTabRawValue = "invalid-tab"
        store.interfaceDensityRawValue = "invalid-density"
        store.appearanceRawValue = "invalid-appearance"
        let fallbackSettings = SettingsModel(store: store, isTrackingEnabled: true,
                                           onChange: { },
                                           onTrackingChanged: { _ in })
        expect(fallbackSettings.defaultAppTab == .focus, "invalid tab falls back to Focus", &problems)
        expect(fallbackSettings.interfaceDensity == .comfortable,
               "invalid density falls back to Comfortable", &problems)
        expect(fallbackSettings.appearancePreference == .system,
               "invalid appearance falls back to System", &problems)

        defaults.removeObject(forKey: "fc.showsTimelineLabels")
        defaults.set(NSNumber(value: 0), forKey: "fc.showsTimelineLabels")
        let malformedBooleanSettings = SettingsModel(store: store, isTrackingEnabled: true,
                                                     onChange: { },
                                                     onTrackingChanged: { _ in })
        expect(malformedBooleanSettings.showsTimelineLabels,
               "a non-Boolean timeline-label value falls back to visible", &problems)
        return problems
    }
}
