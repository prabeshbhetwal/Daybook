import SwiftUI

/// `--gallery` renders every surface state from fixtures, light and dark, side by
/// side. It is a design-review surface and a visual regression check, and it
/// never touches real user data — every fixture gets a throwaway directory.
enum Fixture: String, CaseIterable, Identifiable {
    case firstRun
    case idleWithHistory
    case running
    case paused
    case watching
    case needsResolution
    case brokenStreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstRun: return "First run — no history"
        case .idleWithHistory: return "Idle — with history"
        case .running: return "Running"
        case .paused: return "Paused"
        case .watching: return "Watching"
        case .needsResolution: return "Needs resolution"
        case .brokenStreak: return "Broken streak"
        }
    }
}

enum FixtureFactory {

    private final class Clock {
        var value: Date
        init(_ start: Date) { value = start }
    }

    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-gallery-\(UUID().uuidString)", isDirectory: true)
    }

    static func store(for fixture: Fixture) -> SessionStore {
        // Anchor at 10:00 today, not "now": seeding from a late-evening anchor
        // pushes a session's end past midnight, so it lands on the wrong day and
        // the totals lie. Sessions are attributed to the day they end.
        let calendar = Calendar.current
        let anchor = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())
            ?? Date()
        let clock = Clock(anchor)
        let defaults = UserDefaults(suiteName: "com.prabesh.focuscontinuity.gallery.\(fixture.rawValue)")
            ?? .standard
        let prefs = PersistenceStore(defaults: defaults)
        prefs.removeAll()
        let archive = SessionArchive(directory: scratchDirectory(), now: { clock.value })
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
            clock.value = anchor.addingTimeInterval(2_712)
        case .paused:
            seedWeek()
            engine.start(workType: .deepWork, intent: "Refactor the parser")
            clock.value = anchor.addingTimeInterval(1_500)
            engine.transition(on: .manualPause)
        case .watching:
            seedWeek()
            engine.start(workType: .deepWork, intent: "Review the product demo")
            clock.value = anchor.addingTimeInterval(1_500)
            engine.transition(on: .watchingObserved(seconds: 10 * 60))
        case .needsResolution:
            seedWeek()
            engine.start(workType: .deepWork, intent: "Refactor the parser")
            clock.value = anchor.addingTimeInterval(600)
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.value = anchor.addingTimeInterval(600 + 1_320)
            engine.transition(on: .awayEnded)
        case .brokenStreak:
            // Worked solidly until three days ago, then stopped.
            seedWeek(skippingDaysAgo: [0, 1, 2])
        }

        let store = SessionStore(engine: engine)

        // Background app usage, so the per-app history renders with real shapes.
        // First run gets the archive too, just empty: the empty state is only a
        // real check if it goes through the same code path.
        let usageArchive = AppUsageArchive(directory: scratchDirectory(),
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
}

struct GalleryView: View {
    private let fixtures: [(Fixture, SessionStore, SessionStore)]

    init() {
        // Two independent stores per fixture: SwiftUI would otherwise share one
        // object across both colour schemes and the focus state would fight.
        fixtures = Fixture.allCases.map {
            ($0, FixtureFactory.store(for: $0), FixtureFactory.store(for: $0))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                Text("FocusContinuity — state catalogue")
                    .font(.largeTitle.weight(.semibold))
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("Components").font(.headline)
                    ComponentStrip()
                }
                Divider()
                ForEach(fixtures, id: \.0.id) { fixture, lightStore, darkStore in
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text(fixture.title).font(.headline)
                        HStack(alignment: .top, spacing: Tokens.Space.xl) {
                            labelled("Light") {
                                PopoverView(store: lightStore).preferredColorScheme(.light)
                            }
                            labelled("Dark") {
                                PopoverView(store: darkStore).preferredColorScheme(.dark)
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
                .clipShape(RoundedRectangle(cornerRadius: Tokens.cardCorner))
                .overlay(RoundedRectangle(cornerRadius: Tokens.cardCorner)
                    .strokeBorder(.quaternary))
        }
    }
}

struct GalleryApp: App {
    var body: some Scene {
        Window("Gallery", id: "gallery") {
            GalleryView()
        }
        .defaultSize(width: 820, height: 900)
    }
}

/// The vocabulary in one row, so a token change can be judged in isolation.
struct ComponentStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                SurfacePanel(title: "Primary shell", layout: InterfaceDensity.compact.layout) {
                    VStack(alignment: .leading, spacing: Tokens.Space.m) {
                        Text("Icon and label")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                        TabRail(selectedTab: .constant(.focus)) { _ in }
                        Text("Label only at compact width")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                        TabRail(selectedTab: .constant(.today)) { _ in }
                            .frame(width: 360)
                    }
                }
                .frame(width: 680)
            }
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                SurfacePanel(title: "Metric line", layout: InterfaceDensity.comfortable.layout) {
                    VStack(spacing: Tokens.Space.s) {
                        MetricLine(label: "Tracked", value: "5h 10m",
                                   note: "3h 5m vs yesterday")
                        MetricLine(label: "Focus", value: "3h 02m",
                                   note: "2h 12m in deep work", tint: Tokens.Colour.focus)
                        GoalRing(progress: 0.63, label: "63%")
                        GoalRing(progress: 1.0, isMet: true)
                    }
                }
                SurfacePanel(title: "Usage rows", layout: InterfaceDensity.compact.layout) {
                    VStack(spacing: Tokens.Space.s) {
                        AppUsageRow(appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                                    rank: 0, seconds: 4_200, share: 0.62,
                                    layout: InterfaceDensity.compact.layout)
                        AppUsageRow(appName: "Chrome", bundleID: "com.google.Chrome",
                                    rank: 1, seconds: 1_950, share: 0.29,
                                    layout: InterfaceDensity.compact.layout)
                        AppUsageRow(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", rank: 2,
                                    seconds: 900, share: 0.09,
                                    layout: InterfaceDensity.compact.layout)
                        EmptyState("No running sessions",
                                   detail: "Start focus and your first session appears here.")
                    }
                }
            }
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                SurfacePanel(title: "Settings and warnings", layout: InterfaceDensity.comfortable.layout) {
                    SettingsRow("Appearance", value: "Dark",
                                layout: InterfaceDensity.comfortable.layout)
                    Divider()
                    SettingsRow("Show timeline labels", value: "On",
                                layout: InterfaceDensity.comfortable.layout)
                    Divider()
                    IntegrityNotice("App usage from before 13 August may include unattended time.")
                }
                SurfacePanel(title: "Density compare", layout: InterfaceDensity.compact.layout) {
                    MetricLine(label: "Compact", value: "44 pt",
                               layout: InterfaceDensity.compact.layout)
                    Divider()
                    MetricLine(label: "Comfortable", value: "52 pt",
                               layout: InterfaceDensity.comfortable.layout)
                }
            }
        }
        .padding(Tokens.Space.l)
        .background(Tokens.Colour.ground)
    }
}
