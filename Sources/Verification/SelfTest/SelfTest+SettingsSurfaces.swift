import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The shape must describe the recording, never the session. A session with
    /// no usage evidence has no shape to report.
    static func testSessionShapeReportsOnlyRecordedEvidence() -> [String] {
        var problems: [String] = []
        let base = anchoredNow()
        func segment(_ name: String, _ from: TimeInterval, _ to: TimeInterval,
                     _ reason: UsageEndReason) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: "com.\(name)", appName: name,
                            start: base.addingTimeInterval(from),
                            end: base.addingTimeInterval(to),
                            colorIndex: 0, endReason: reason)
        }

        expect(SessionShape.paragraph(SessionShape.Input(
            segments: [], workType: .deepWork, stretches: 1, worked: 3_600)) == nil,
               "a session with no recording reports no shape", &problems)

        let mixed = SessionShape.sentences(SessionShape.Input(
            segments: [segment("Xcode", 0, 1_800, .idle),
                       segment("Safari", 1_800, 2_400, .appSwitch),
                       segment("Xcode", 2_400, 3_600, .stillOpen)],
            workType: .deepWork, stretches: 1, worked: 3_600))
        let joined = mixed.joined(separator: " ")
        expect(joined.contains("Xcode was in front for 50m of the 1h recorded"),
               "the leading app is stated against recorded time", &problems)
        expect(joined.contains("You moved between apps 2 times."),
               "only real identity changes count as switches", &problems)
        expect(joined.contains("input stopped once"),
               "a recorded idle end is reported", &problems)
        expect(!joined.contains("watching"),
               "deep work never claims watching counts as the work", &problems)
        expect(!joined.contains("no app recording"),
               "a fully recorded session reports no gap", &problems)

        let meeting = SessionShape.sentences(SessionShape.Input(
            segments: [segment("Zoom", 0, 1_800, .idle)],
            workType: .meetings, stretches: 1, worked: 3_600))
        let meetingText = meeting.joined(separator: " ")
        expect(meetingText.contains("Zoom was in front for all 30m recorded."),
               "a single-app session says so plainly", &problems)
        expect(meetingText.contains("Meetings treats watching as the work itself"),
               "the watching rule is stated where it applies", &problems)
        expect(meetingText.contains("30m of this session has no app recording."),
               "worked time beyond the recording is stated, not hidden", &problems)
        return problems
    }

    /// The three parts of the Mac split must be disjoint and sum to the whole,
    /// or the tile would describe more time than the day can account for.
    static func testUnrecordedFocusIsTheUncoveredSpan() -> [String] {
        var problems: [String] = []
        let clock = TestClock(anchoredNow())
        let day = Calendar.current.startOfDay(for: clock.value)
        let start = day.addingTimeInterval(9 * 3_600)
        let archive = makeArchive(clock, records: [
            SessionRecord(name: "Refactor", workType: .deepWork,
                          start: start, end: start.addingTimeInterval(3_600),
                          workSeconds: 3_600, threadID: UUID())
        ])
        // One 15-minute stretch inside the hour, and one entirely outside it.
        let usage = makeUsageArchive(clock, sessions: [
            AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                            start: start, end: start.addingTimeInterval(900),
                            endReason: .appSwitch),
            AppUsageSession(bundleID: "com.google.Chrome", appName: "Chrome",
                            start: start.addingTimeInterval(5_400),
                            end: start.addingTimeInterval(7_200),
                            endReason: .appSwitch)
        ], accurateFrom: day)
        let quality = DashboardStats(sessions: archive, usage: usage).focusQuality(for: day)
        let tracked: TimeInterval = 900 + 1_800
        let inside = tracked * quality.insideSessionShare
        expect(abs(inside - 900) < 1,
               "only usage inside the session counts as inside it", &problems)
        expect(abs(quality.unrecordedFocusSeconds - 2_700) < 1,
               "the focused span usage never saw is 45m", &problems)
        expect(abs((inside + (tracked - inside) + quality.unrecordedFocusSeconds)
                   - (tracked + 2_700)) < 1,
               "the three parts sum to the accounted total", &problems)
        return problems
    }

    static func testSettingsGroupsContainOnlyBackedControls() -> [String] {
        var problems: [String] = []
        let expectedTitles = [
            "General", "Focus sessions", "Categories", "Away and breaks", "Automatic and rewards",
            "Activity rules", "Tracking and apps", "Appearance", "Data and privacy", "Updates", "Advanced"
        ]
        expect(SettingsSection.allCases.map(\.title) == expectedTitles,
               "all eleven Settings groups retain their approved order and titles", &problems)
        expect(SettingsSection.allCases.allSatisfy {
            !$0.symbol.isEmpty && !$0.controlLabels.isEmpty
        }, "every Settings group exposes a symbol and searchable control labels", &problems)
        expect(SettingsSection.matching("goal").map(\.title) == ["Focus sessions"],
               "searching goal returns Focus sessions", &problems)
        expect(SettingsSection.matching("privacy").map(\.title) == ["Data and privacy"],
               "searching privacy returns Data and privacy", &problems)

        let expectedControls: Set<SettingsControlKey> = [
            .dailyGoal, .categories, .breakThreshold, .longAwayCap, .fullPromptAfter,
            .reminders, .activityRuleAutomation, .activityRules,
            .automaticSessions, .automaticGap, .rewards, .sessionsPerApp,
            .usageRecording, .appearance, .density, .timelineLabels, .entryDetails,
            .idlePause, .streakMinimum, .minimumSession, .continueWindow, .defaultCategory,
            .openAtLogin, .menuBarTime, .menuBarIcon, .dockIcon, .updateChecks, .updateFrequency,
            .updateInstall, .railApps, .paceWindow, .suggestionWindow, .breakTiers, .quietFold
        ]
        let listedControls = SettingsSection.allCases.flatMap(\.mutableControlKeys)
        expect(Set(listedControls) == expectedControls,
               "Settings lists exactly the backed mutable controls", &problems)
        expect(listedControls.count == expectedControls.count,
               "no backed mutable control appears in more than one group", &problems)
        expect(Set(listedControls.map(\.modelKeyPath)).count == expectedControls.count,
               "every mutable control maps to a distinct SettingsModel property", &problems)

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.defaultAppTab = .review
        settings.interfaceDensity = .compact
        settings.appearancePreference = .dark
        settings.showsTimelineLabels = false
        let reloaded = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        expect(reloaded.defaultAppTab == .review,
               "Settings default tab survives reload", &problems)
        expect(reloaded.interfaceDensity == .compact
               && reloaded.interfaceLayout.rowHeight == InterfaceDensity.compact.layout.rowHeight,
               "Settings density survives reload and changes layout metrics", &problems)
        expect(reloaded.appearancePreference == .dark,
               "Settings appearance survives reload", &problems)
        expect(!reloaded.showsTimelineLabels,
               "Settings timeline-label choice survives reload", &problems)

        let backupDirectory = scratchDirectory()
        try? FileManager.default.createDirectory(at: backupDirectory,
                                                 withIntermediateDirectories: true)
        let olderBackup = backupDirectory
            .appendingPathComponent("app-usage-v1-backup-1700000000.json")
        let newerBackup = backupDirectory
            .appendingPathComponent("app-usage-v1-backup-1800000000.json")
        try? Data("older".utf8).write(to: olderBackup)
        try? Data("newer".utf8).write(to: newerBackup)
        try? Data("unrelated".utf8).write(
            to: backupDirectory.appendingPathComponent("sessions.json"))
        expect(SettingsDiagnostics.latestLegacyBackup(in: backupDirectory)?
                   .resolvingSymlinksInPath() == newerBackup.resolvingSymlinksInPath(),
               "Data diagnostics rediscover the newest preserved legacy backup after relaunch",
               &problems)
        return problems
    }

    static func testSettingsDiagnosticLayout() -> [String] {
        var problems: [String] = []
        expect(SettingsReadOnlyRowLayout.trailingValue.usesTrailingValue,
               "scalar diagnostics retain the compact trailing-value layout", &problems)
        expect(!SettingsReadOnlyRowLayout.statusBlock.usesTrailingValue,
               "Recovery never compresses into the trailing scalar column", &problems)
        return problems
    }

    static func testSettingsPrivacyDisclosure() -> [String] {
        var problems: [String] = []
        let disclosure = SettingsPrivacyDisclosure.current
        expect(!disclosure.appUsageMonitoringCapturesTextInOtherApps,
               "app-usage monitoring never claims to capture text in other apps", &problems)
        expect(disclosure.locallyStoredFocusInputs == [.sessionName, .intent, .note, .power],
               "session names, intent, notes and power state are disclosed as local data",
               &problems)
        expect(disclosure.storageDetail.contains("notes")
               && disclosure.storageDetail.contains("battery"),
               "privacy copy names the session notes and battery state it stores", &problems)
        expect(disclosure.storageDetail.contains(
            "App-usage monitoring does not capture text in other apps"),
            "privacy copy states the real app-monitoring boundary", &problems)
        expect(disclosure.storageDetail.contains(
            "Session names, intent and notes entered into FocusContinuity are stored locally"),
            "privacy copy states that FocusContinuity-entered text is stored locally", &problems)
        expect(!disclosure.storageDetail.contains("anything you type"),
               "privacy copy makes no blanket claim about typed text", &problems)
        return problems
    }

    static func testSharedPanelDensityEnvironment() -> [String] {
        var problems: [String] = []
        let sizes: (comfortable: CGSize, compact: CGSize) = MainActor.assumeIsolated {
            let comfortablePanel = SurfacePanel(showsHeader: false) {
                Text("Ordinary panel content")
            }
            .environment(\.focusInterfaceDensity, InterfaceDensity.comfortable)
            .frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            let comfortableRenderer = ImageRenderer(content: comfortablePanel)
            comfortableRenderer.scale = 1

            let compactPanel = SurfacePanel(showsHeader: false) {
                Text("Ordinary panel content")
            }
            .environment(\.focusInterfaceDensity, InterfaceDensity.compact)
            .frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            let compactRenderer = ImageRenderer(content: compactPanel)
            compactRenderer.scale = 1

            return (comfortableRenderer.nsImage?.size ?? .zero,
                    compactRenderer.nsImage?.size ?? .zero)
        }
        expect(sizes.comfortable.width > 0 && sizes.compact.width > 0,
               "both shared panel density probes render", &problems)
        expect(sizes.compact.height < sizes.comfortable.height,
               "compact density reduces an actual shared SurfacePanel from "
               + "\(sizes.comfortable.height)pt to \(sizes.compact.height)pt", &problems)
        return problems
    }

    static func testSettingsAccuracyEpochYear() -> [String] {
        var problems: [String] = []
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let label = SettingsDiagnostics.accuracyEpochLabel(epoch)
        expect(label.contains("2023"),
               "accuracy epoch includes its year, got \(label)", &problems)
        return problems
    }
}
