import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// An explicit appearance may override macOS, but returning to System must
    /// remove that override so a live system appearance change reaches the app.
    static func testSystemAppearanceClearsApplicationOverride() -> [String] {
        var problems: [String] = []
        let defaults = MemoryDefaults.suite(named: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }

        let model = SettingsModel(
            store: store,
            isTrackingEnabled: true,
            onChange: {},
            onTrackingChanged: { _ in },
            onAppearanceChanged: { preference in preference.apply(to: NSApp) })

        model.appearancePreference = .dark
        expect(NSApp.appearance?.name == .darkAqua,
               "Dark sets an explicit application appearance", &problems)

        model.appearancePreference = .system
        expect(NSApp.appearance == nil,
               "System clears the override so macOS appearance is inherited", &problems)
        return problems
    }

    /// The Settings information architecture is searchable because its real
    /// controls carry metadata, and every mutable row resolves to one concrete
    /// SettingsModel property rather than a placeholder preference.
    /// The window opens on the day's story, and a sheet-backed tab must
    /// present its sheet on construction — otherwise restoring a surface shows
    /// the story with no sign of what was asked for.
    static func testWindowOpensOnPreferredStory() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let window = MainWindowModel(opening: .story)
            expect(window.workspace == .story && window.sheet == nil,
                   "a window built on the story opens the day's story", &problems)
            expect(!SettingsControlKey.allCases.map(\.rawValue).contains("opensOn"),
                   "no setting offers a story other than the day", &problems)

            let settings = MainWindowModel(opening: .settings)
            expect(settings.sheet == .settings,
                   "a window built on Settings is already presenting Settings", &problems)
            let awards = MainWindowModel(opening: .awards)
            expect(awards.sheet == .awards,
                   "a window built on Awards is already presenting Awards", &problems)
            settings.closeSheet()
            expect(settings.sheet == nil, "closing the sheet returns the story", &problems)
        }
        return problems
    }

    /// The card's actions are only real if the day the story shows changes.
    /// Exercises them through the store, not the archive beneath it.
    static func testStoryCorrectionsReachTheDay() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.setDashboardVisible(true)
            store.refresh()

            func firstSession() -> DaySession? {
                for entry in store.daySessions {
                    if case .session(let session) = entry { return session }
                }
                return nil
            }

            guard let original = firstSession() else {
                problems.append("the fixture day has no session to correct")
                return
            }

            store.renameSession(original, to: "Parser rewrite")
            expect(firstSession()?.name == "Parser rewrite",
                   "renaming a session renames it in the day the story shows", &problems)

            // The shape describes the recording, so it must survive a rename
            // and change only when the recording it describes changes.
            let shapeBefore = firstSession().flatMap { store.sessionShape($0) }

            guard let renamed = firstSession() else {
                problems.append("the session vanished after being renamed")
                return
            }
            let focusedBefore = store.focusedForSelectedDay
            store.setWorkType(.breakTime, for: renamed)
            expect(store.focusedForSelectedDay < focusedBefore,
                   "correcting work to rest removes it from the day's focus", &problems)

            // Rest is not a session, so the entry becomes a rest row rather
            // than a card — the story stops calling it work.
            expect(firstSession() == nil,
                   "work corrected to rest is no longer a session entry", &problems)
            let restNames = store.daySessions.compactMap { entry -> String? in
                if case .rest(let rest) = entry { return rest.name }
                return nil
            }
            expect(restNames.contains("Parser rewrite"),
                   "the corrected entry appears as rest, under its own name", &problems)
            let asRest = DaySession(id: renamed.id, threadID: renamed.threadID,
                                    name: renamed.name, workType: .breakTime,
                                    start: renamed.start, end: renamed.end,
                                    worked: renamed.worked, stretches: renamed.stretches,
                                    spans: renamed.spans, isRunning: false)
            expect(!store.canContinue(asRest),
                   "rest offers nothing to continue", &problems)
            expect(!store.canContinue(renamed),
                   "a historical work row does not offer a hidden continuation", &problems)

            store.setWorkType(.deepWork, for: renamed)
            expect(abs(store.focusedForSelectedDay - focusedBefore) < 1,
                   "correcting the correction restores the day exactly", &problems)
            expect(firstSession().flatMap { store.sessionShape($0) } == shapeBefore,
                   "a name change never alters what the recording shows", &problems)
        }
        return problems
    }

    /// A stored arrangement is a preference, not a schema. It must survive a
    /// release that adds, removes or renames a tile without losing one.
    static func testStoredTileOrderIsRepaired() -> [String] {
        var problems: [String] = []
        expect(StoryTileKind.order(from: "") == StoryTileKind.allCases,
               "no stored order yields the shipped order", &problems)
        expect(StoryTileKind.order(from: "streak,apps") ==
               [.streak, .apps, .focus, .mac, .rhythm],
               "a partial order keeps its choices and appends the rest", &problems)
        expect(StoryTileKind.order(from: "apps,ghost,apps,mac").count
               == StoryTileKind.allCases.count,
               "unknown and duplicate names never shrink or grow the rail", &problems)
        expect(Set(StoryTileKind.order(from: "ghost,ghost")) == Set(StoryTileKind.allCases),
               "an unusable stored order still yields every tile", &problems)

        let order = StoryTileKind.allCases
        expect(StoryTileKind.moving(.streak, before: .focus, in: order)
               == [.streak, .focus, .mac, .apps, .rhythm],
               "a tile dropped on the first one takes first place", &problems)
        expect(StoryTileKind.moving(.focus, before: nil, in: order)
               == [.mac, .apps, .rhythm, .streak, .focus],
               "a tile dropped past the end takes last place", &problems)
        expect(StoryTileKind.moving(.mac, before: .mac, in: order) == order,
               "a tile dropped on itself changes nothing", &problems)
        expect(StoryTileKind.moving(.apps, before: .rhythm, in: order) == order,
               "a tile dropped on its own successor changes nothing", &problems)
        return problems
    }

    /// Segments of one piece of work share a name and a kind, so a correction
    /// applies to the thread — otherwise a renamed stretch would split the work
    /// into two differently-named halves.
    static func testCorrectingASessionRewritesItsThread() -> [String] {
        var problems: [String] = []
        let clock = TestClock(anchoredNow())
        let thread = UUID()
        let other = UUID()
        let base = Calendar.current.startOfDay(for: clock.value).addingTimeInterval(9 * 3_600)
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let seed = [
            SessionRecord(name: "Refactor", workType: .deepWork,
                          start: base, end: base.addingTimeInterval(1_800),
                          workSeconds: 1_800, threadID: thread),
            SessionRecord(name: "Refactor", workType: .deepWork,
                          start: base.addingTimeInterval(3_600),
                          end: base.addingTimeInterval(5_400),
                          workSeconds: 1_800, threadID: thread),
            SessionRecord(name: "Email", workType: .admin,
                          start: base.addingTimeInterval(7_200),
                          end: base.addingTimeInterval(8_100),
                          workSeconds: 900, threadID: other)
        ]
        if let data = try? JSONEncoder().encode(seed) {
            try? data.write(to: directory.appendingPathComponent("sessions.json"),
                            options: .atomic)
        }
        let archive = SessionArchive(directory: directory, now: { clock.value })

        expect(archive.rename(thread: thread, to: "Parser rewrite"),
               "renaming a thread that needs it reports a change", &problems)
        let renamed = archive.records.filter { $0.threadID == thread }
        expect(renamed.count == 2 && renamed.allSatisfy { $0.name == "Parser rewrite" },
               "every stretch of the thread carries the new name", &problems)
        expect(archive.records.first { $0.threadID == other }?.name == "Email",
               "another thread is left alone", &problems)
        expect(!archive.rename(thread: thread, to: "Parser rewrite"),
               "renaming to the same name reports no change", &problems)
        expect(!archive.rename(thread: thread, to: "   "),
               "an empty name is refused", &problems)

        expect(archive.setWorkType(.breakTime, forThread: thread),
               "reclassifying a thread that needs it reports a change", &problems)
        expect(archive.records.filter { $0.threadID == thread }
            .allSatisfy { $0.workType == .breakTime },
               "every stretch of the thread carries the new kind", &problems)
        expect(archive.workSeconds(on: clock.value) == 900,
               "time corrected to rest leaves the day's focused total", &problems)

        // The correction must survive a reopen: it is a write, not a view.
        let reopened = SessionArchive(directory: directory, now: { clock.value })
        expect(reopened.records.filter { $0.threadID == thread }
            .allSatisfy { $0.name == "Parser rewrite" && $0.workType == .breakTime },
               "corrections are persisted, not merely held in memory", &problems)
        return problems
    }
}
