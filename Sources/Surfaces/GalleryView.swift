import SwiftUI

/// `--gallery` renders every surface state from fixtures, light and dark, side by
/// side. It is a design-review surface and a visual regression check, and it
/// never touches real user data — every fixture gets a throwaway directory.
enum Fixture: String, CaseIterable, Identifiable {
    case firstRun
    case idleWithHistory
    case running
    case paused
    case needsResolution
    case brokenStreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstRun: return "First run — no history"
        case .idleWithHistory: return "Idle — with history"
        case .running: return "Running"
        case .paused: return "Paused"
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
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            GoalRing(progress: 0.63, label: "63%")
            GoalRing(progress: 1.0, isMet: true)
            StatCard(label: "Tracked", value: "5h 10m", context: "+3h 5m vs yesterday",
                     contextTint: Tokens.Palette.app(rank: 1))
                .frame(width: 150)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                ForEach(0..<7, id: \.self) { rank in
                    HStack(spacing: Tokens.Space.s) {
                        AppSwatch(rank: rank, bundleID: nil, appName: "App \(rank)")
                        DataBar(share: 1 - Double(rank) / 8, tint: Tokens.Palette.app(rank: rank))
                            .frame(width: 120)
                    }
                }
            }
            HStack(spacing: Tokens.Space.s) {
                IconButton(systemImage: "pause.fill", help: "Pause") {}
                IconButton(systemImage: "gearshape", help: "Settings…") {}
                IconButton(systemImage: "power", help: "Quit", prominent: true) {}
            }
            StartButton(fills: false) {}
        }
        .padding(Tokens.Space.l)
        .background(Tokens.Surface.ground)
    }
}
