import SwiftUI

/// Data states used to build the product-surface matrix. They are deliberately
/// not the Gallery's navigation model; `SnapshotScenario` owns that contract.
enum FixtureState: String {
    case firstRun
    case idleWithHistory
    case running
    case paused
    case needsResolution
}

enum FixtureFactory {
    private static var directories: [URL] = []
    private static var preferenceSuites: [String] = []

    private struct UsageFixtureEnvelope: Codable {
        let metadata: AppUsageMetadata
        let sessions: [AppUsageSession]
    }

    private final class Clock {
        var value: Date
        init(_ start: Date) { value = start }
    }

    static func scratchDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-gallery-\(UUID().uuidString)", isDirectory: true)
        directories.append(directory)
        return directory
    }

    static func installedAppCatalog() -> InstalledAppCatalog {
        InstalledAppCatalog(discoverStandard: {
            [InstalledApplication(bundleID: "com.example.code", name: "Example Code", url: nil),
             InstalledApplication(bundleID: "com.example.shared", name: "Shared Assistant", url: nil)]
        }, discoverSpotlight: { [] }, observed: { [] })
    }

    static func activityRuleStore(ambiguous: Bool) -> SessionStore {
        let store = self.store(for: .firstRun, accurateUsage: true)
        let coding = ActivityRule(name: "Coding", workType: .deepWork,
            bundleIDs: ["com.example.shared"], startAfter: 60)
        let research = ActivityRule(name: "Research", workType: .learning,
            bundleIDs: ["com.example.shared"], startAfter: 60)
        store.engine.store.activityRules = [coding, research]
        store.engine.store.activityRuleAutomationEnabled = true
        let moment = store.engine.snapshot().savedAt
        if ambiguous {
            store.presentActivityChoice(ActivityQuietChoice(id: UUID(),
                candidates: [ActivityCandidate(ruleID: coding.id, name: coding.name,
                                                workType: coding.workType),
                             ActivityCandidate(ruleID: research.id, name: research.name,
                                               workType: research.workType)],
                evidence: DateInterval(start: moment.addingTimeInterval(-60), end: moment),
                ruleVersion: store.engine.store.activityRuleVersion, generation: 1,
                foregroundGeneration: 1))
        } else {
            let action = ActivityAutomaticAction(ruleID: coding.id, ruleName: coding.name,
                workType: coding.workType,
                evidence: DateInterval(start: moment.addingTimeInterval(-60), end: moment),
                reason: "Coding after 60 seconds in Example Code",
                ruleVersion: store.engine.store.activityRuleVersion, generation: 1,
                expectedRecordID: nil)
            _ = store.applyAutomaticActivity(action)
        }
        store.refresh()
        return store
    }

    private static func fixtureDefaults(_ label: String) -> UserDefaults {
        let suite = "com.prabesh.focuscontinuity.gallery.\(label).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Could not create isolated fixture preferences")
        }
        preferenceSuites.append(suite)
        return defaults
    }

    static func cleanUp() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        for suite in preferenceSuites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        directories.removeAll()
        preferenceSuites.removeAll()
    }

    static func store(for fixture: FixtureState, accurateUsage: Bool = false) -> SessionStore {
        // Anchor at 10:00 today, not "now": seeding from a late-evening anchor
        // pushes a session's end past midnight, so it lands on the wrong day and
        // the totals lie. Sessions are attributed to the day they end.
        let calendar = Calendar.current
        let anchor = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())
            ?? Date()
        // Archived morning work precedes the live stretch. Fixture clocks must
        // not jump backwards into the archived session when a new one starts.
        let clock = Clock(anchor.addingTimeInterval(2 * 3_600))
        let defaults = fixtureDefaults(fixture.rawValue)
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let dataDirectory = scratchDirectory()
        let archive = SessionArchive(directory: dataDirectory, now: { clock.value })
        let engine = SessionEngine(store: prefs,
                                   archive: archive,
                                   ownBundleID: FocusConstants.bundleIdentifier,
                                   schedulesDwell: false,
                                   now: { clock.value })

        // Today's work is one thread with two segments, so the Continue
        // section has a multi-segment row to draw.
        let todayThread = UUID()

        func seedWeek(skippingDaysAgo skipped: Set<Int> = []) {
            for daysAgo in 0..<7 where !skipped.contains(daysAgo) {
                let day = anchor.addingTimeInterval(-Double(daysAgo) * 86_400)
                let minutes = [95.0, 145.0, 205.0, 165.0, 120.0, 60.0, 40.0][daysAgo]
                archive.append(SessionRecord(name: ["Refactor", "Standup", "Email",
                                                    "Read paper", "Design review",
                                                    "Refactor", "Refactor"][daysAgo],
                                             workType: [.deepWork, .meetings, .admin,
                                                        .learning, .meetings,
                                                        .deepWork, .deepWork][daysAgo],
                                             start: day,
                                             end: day.addingTimeInterval(minutes * 60),
                                             workSeconds: minutes * 60,
                                             detectedApp: "com.apple.dt.Xcode",
                                             threadID: daysAgo == 0 ? todayThread : UUID()))
            }
            guard !skipped.contains(0) else { return }
            archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                         start: anchor.addingTimeInterval(-5_400),
                                         end: anchor.addingTimeInterval(-3_600),
                                         workSeconds: 1_800,
                                         detectedApp: "com.apple.dt.Xcode",
                                         threadID: todayThread))
        }

        switch fixture {
        case .firstRun:
            break
        case .idleWithHistory:
            seedWeek()
        case .running:
            seedWeek()
            engine.start(workType: .deepWork, intent: "Refactor the parser")
            clock.value = clock.value.addingTimeInterval(2_712)
        case .paused:
            seedWeek()
            engine.start(workType: .deepWork, intent: "Refactor the parser")
            clock.value = clock.value.addingTimeInterval(1_500)
            engine.transition(on: .manualPause)
        case .needsResolution:
            seedWeek()
            engine.start(workType: .deepWork, intent: "Refactor the parser")
            clock.value = clock.value.addingTimeInterval(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.value = clock.value.addingTimeInterval(1_320)
            engine.transition(on: .awayEnded)
        }

        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })

        // Background app usage, so the per-app history renders with real shapes.
        // First run gets the archive too, just empty: the empty state is only a
        // real check if it goes through the same code path.
        let usageDirectory = dataDirectory
        if accurateUsage {
            try? FileManager.default.createDirectory(at: usageDirectory,
                                                     withIntermediateDirectories: true)
            let envelope = UsageFixtureEnvelope(
                metadata: AppUsageMetadata(accurateFrom:
                    anchor.addingTimeInterval(-30 * 86_400)),
                sessions: [])
            if let data = try? JSONEncoder().encode(envelope) {
                try? data.write(to: usageDirectory.appendingPathComponent("app-usage.json"),
                                options: .atomic)
            }
        }
        let usageArchive = AppUsageArchive(directory: usageDirectory,
                                           now: { clock.value })
        if fixture != .firstRun {
            func use(_ bundleID: String, _ name: String,
                     minutes: Double, endingHoursAgo: Double) {
                let end = anchor.addingTimeInterval(-endingHoursAgo * 3_600)
                usageArchive.record(AppUsageSession(bundleID: bundleID, appName: name,
                                                    start: end.addingTimeInterval(-minutes * 60),
                                                    end: end))
            }
            // A week of history, so Week and Month have bars to draw.
            for daysAgo in 1...6 {
                let base = anchor.addingTimeInterval(-Double(daysAgo) * 86_400)
                usageArchive.record(AppUsageSession(
                    bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                    start: base.addingTimeInterval(-Double(daysAgo) * 900),
                    end: base.addingTimeInterval(Double(90 - daysAgo * 10) * 60)))
            }
            // An overnight-sized gap, so the elided separator is visible.
            use("com.apple.Notes", "Notes", minutes: 30, endingHoursAgo: 14)
            // "Codex for 2 hours, 4 hours ago" — the example from the request.
            use("com.apple.dt.Xcode", "Xcode", minutes: 120, endingHoursAgo: 4)
            use("com.apple.dt.Xcode", "Xcode", minutes: 55, endingHoursAgo: 7)
            use("com.apple.dt.Xcode", "Xcode", minutes: 25, endingHoursAgo: 9)
            use("com.google.Chrome", "Chrome", minutes: 40, endingHoursAgo: 1)
            use("com.google.Chrome", "Chrome", minutes: 15, endingHoursAgo: 5)
            use("com.apple.Terminal", "Terminal", minutes: 35, endingHoursAgo: 3)
            use("com.spotify.client", "Spotify", minutes: 20, endingHoursAgo: 6)
        }

        let tracker = AppUsageTracker(archive: usageArchive,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      now: { clock.value })
        store.attach(tracker: tracker, usage: usageArchive)

        store.refresh()
        return store
    }

    /// Screenshot-matched interaction states. The bars are derived from these
    /// isolated app-use intervals, never random heights or production records.
    static func storyInteractionStore(for scenario: SnapshotScenario) -> SessionStore {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        let clock = Clock(time(12))
        let preferences = PersistenceStore(defaults: fixtureDefaults(scenario.rawValue))
        preferences.dailyGoal = 4 * 3_600
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        let engine = SessionEngine(store: preferences, archive: archive,
            ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false, now: { clock.value })
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelope = UsageFixtureEnvelope(metadata: AppUsageMetadata(accurateFrom: today), sessions: [])
        if let bytes = try? JSONEncoder().encode(envelope) {
            try? bytes.write(to: directory.appendingPathComponent("app-usage.json"), options: .atomic)
        }
        let usage = AppUsageArchive(directory: directory, calendar: calendar, now: { clock.value })
        func use(_ id: String, _ name: String, from start: Date, to end: Date) {
            usage.record(AppUsageSession(bundleID: id, appName: name, start: start, end: end))
        }
        let xcode = "com.apple.dt.Xcode"
        let shapeStart = time(9, 12)
        archive.append(SessionRecord(name: "Refactor the parser", workType: .deepWork,
            start: shapeStart, end: time(10, 48), workSeconds: 80 * 60, detectedApp: xcode))
        // Eight twelve-minute bins with genuine variation and explicit gaps.
        for (index, minutes) in [7, 10, 11, 9, 4, 10, 12, 7].enumerated() {
            let start = shapeStart.addingTimeInterval(Double(index * 12 * 60))
            let identity: (String, String) = index == 4 ? ("com.apple.Safari", "Safari")
                : index == 7 ? ("com.apple.Terminal", "Terminal") : (xcode, "Xcode")
            use(identity.0, identity.1, from: start, to: start.addingTimeInterval(Double(minutes * 60)))
        }
        // More than four apps makes the bounded Apps tile visible in the matrix.
        use("com.apple.iCal", "Calendar", from: time(8), to: time(8, 10))
        use("com.apple.Notes", "Notes", from: time(8, 10), to: time(8, 25))

        if scenario != .storyShape {
            archive.append(SessionRecord(name: "Spec review", workType: .meetings,
                start: time(11, 5), end: time(11, 40), workSeconds: 35 * 60,
                detectedApp: "us.zoom.xos"))
            use("us.zoom.xos", "Zoom", from: time(11, 5), to: time(11, 40))
        }
        if scenario == .storyLive || scenario == .storyDecision {
            archive.append(SessionRecord(name: "Lunch", workType: .breakTime,
                start: time(12, 10), end: time(13), workSeconds: 50 * 60))
            clock.value = scenario == .storyDecision ? time(13) : time(14, 41)
            engine.start(workType: .deepWork, intent: "Refactor the parser")
            if scenario == .storyDecision {
                use(xcode, "Xcode", from: time(13), to: time(13, 12))
                clock.value = time(13, 12)
                engine.transition(on: .awayBegan(trigger: .screenLock))
                clock.value = time(14, 40)
                engine.transition(on: .awayEnded)
                _ = engine.decide(.tookBreak)
                clock.value.addTimeInterval(43 * 60 + 58)
            } else {
                clock.value.addTimeInterval(51 * 60 + 6)
            }
            if let span = engine.runningSpan {
                let width = span.end.timeIntervalSince(span.start) / 8
                for (index, share) in [0.45, 0.72, 0.95, 0.70, 0.89, 1.0, 0.91, 0.82].enumerated() {
                    let start = span.start.addingTimeInterval(Double(index) * width)
                    use(xcode, "Xcode", from: start, to: start.addingTimeInterval(width * share))
                }
            }
        }
        let tracker = AppUsageTracker(archive: usage, ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.setDashboardVisible(true)
        store.refresh()
        return store
    }

    static let decisionSaveError = "The session archive is unavailable. Check its folder access or free space, then retry."

    /// A real rejected write, not just a painted error label. The same pending
    /// decision and retry state drive the operational sheet and menu popover.
    static func failingDecisionStore() -> SessionStore {
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        let clock = Clock(start)
        let archive = SessionArchive(directory: scratchDirectory(), now: { clock.value },
                                     writeOverride: { _ in decisionSaveError })
        let engine = SessionEngine(store: PersistenceStore(defaults: fixtureDefaults("failed-answer")),
            archive: archive, ownBundleID: FocusConstants.bundleIdentifier,
            schedulesDwell: false, now: { clock.value })
        engine.start(workType: .deepWork, intent: "Refactor the parser")
        clock.value.addTimeInterval(600)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.value.addTimeInterval(1_200)
        engine.transition(on: .awayEnded)
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        store.resolve(.tookBreak, label: "Walk")
        return store
    }

    /// Task 8's visual pair needs a stable noon cutoff and non-zero historical
    /// pace samples. The general gallery intentionally keeps its older 10:00
    /// fixtures; this isolated record avoids changing accepted surfaces while
    /// exercising every production Insights gate with canonical archives.
    static func insightsStore(withEvidence: Bool) -> SessionStore {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let anchor = today.addingTimeInterval(12 * 3_600)
        let clock = Clock(anchor)
        let defaults = fixtureDefaults("insights.\(withEvidence)")
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let dataDirectory = scratchDirectory()
        let archive = SessionArchive(directory: dataDirectory,
                                     calendar: calendar, now: { clock.value })
        let engine = SessionEngine(store: prefs,
                                   archive: archive,
                                   ownBundleID: FocusConstants.bundleIdentifier,
                                   schedulesDwell: false,
                                   now: { clock.value })

        let usageDirectory = dataDirectory
        try? FileManager.default.createDirectory(at: usageDirectory,
                                                 withIntermediateDirectories: true)
        let accurateFrom = calendar.date(byAdding: .day, value: -40, to: today) ?? today
        let envelope = UsageFixtureEnvelope(
            metadata: AppUsageMetadata(accurateFrom: accurateFrom),
            sessions: [])
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: usageDirectory.appendingPathComponent("app-usage.json"),
                            options: .atomic)
        }
        let usage = AppUsageArchive(directory: usageDirectory,
                                    calendar: calendar, now: { clock.value })

        if withEvidence {
            let types: [WorkType] = [.deepWork, .learning, .admin, .meetings]
            for daysAgo in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: -daysAgo,
                                              to: today) else { continue }
                let focusStart = day.addingTimeInterval(9 * 3_600)
                let minutes = 75 + (daysAgo % 4) * 10
                let focusEnd = focusStart.addingTimeInterval(Double(minutes * 60))
                archive.append(SessionRecord(
                    name: daysAgo.isMultiple(of: 2) ? "Build the interface" : "Review evidence",
                    workType: types[daysAgo % types.count],
                    start: focusStart,
                    end: focusEnd,
                    workSeconds: Double(minutes * 60)))
                let appSwitch = min(focusEnd,
                                    focusStart.addingTimeInterval(55 * 60))
                usage.record(AppUsageSession(
                    bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                    start: focusStart, end: appSwitch))
                if focusEnd > appSwitch {
                    usage.record(AppUsageSession(
                        bundleID: "com.apple.Terminal", appName: "Terminal",
                        start: appSwitch, end: focusEnd))
                }
            }
        }

        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        store.refreshInsights()
        return store
    }
}

@MainActor private final class GalleryModel: ObservableObject {
    @Published var scenario: SnapshotScenario = .focusRunning
}

struct GalleryView: View {
    @StateObject private var model = GalleryModel()

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                Text("FocusContinuity — product surface catalogue")
                    .font(.largeTitle.weight(.semibold))
                Picker("Scenario", selection: $model.scenario) {
                    ForEach(SnapshotScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 340, alignment: .leading)

                ForEach(model.scenario.presentations, id: \.rawValue) { presentation in
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text(presentation.title).font(.headline)
                        HStack(alignment: .top, spacing: Tokens.Space.xl) {
                            labelled("Light") {
                                Snapshotter.view(for: SnapshotRender(
                                    scenario: model.scenario,
                                    appearance: .light,
                                    presentation: presentation))
                            }
                            labelled("Dark") {
                                Snapshotter.view(for: SnapshotRender(
                                    scenario: model.scenario,
                                    appearance: .dark,
                                    presentation: presentation))
                            }
                        }
                    }
                    Divider()
                }
            }
            .padding(Tokens.Space.xl)
        }
    }

    private func labelled<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel)
                    .strokeBorder(.quaternary))
        }
    }
}

struct GalleryApp: App {
    var body: some Scene {
        Window("Gallery", id: "gallery") {
            GalleryView()
        }
        .defaultSize(width: 1_420, height: 920)
    }
}
