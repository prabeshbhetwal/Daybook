import SwiftUI
import AppKit

/// `--snapshot <dir>` renders every gallery fixture to PNG in both appearances.
/// The gallery window is for a human; this is how the design gets checked without
/// a screen-recording grant, and it doubles as a visual regression artefact.
@MainActor
enum Snapshotter {

    /// The screen the harness pretends to be on. Two-pane output needs a wide
    /// one; pass `--snapshot-narrow` for the single-column artefacts.
    static var screen: CGSize {
        // 13" MacBook Pro by default: the tightest machine the panel must fit,
        // so the regression artefacts show the layout under real pressure
        // rather than on a display with room to hide mistakes.
        if CommandLine.arguments.contains("--wide") {
            return CGSize(width: 2_560, height: 1_440)
        }
        return CGSize(width: 1_440, height: 845)
    }

    static func run(directory: URL) -> Bool {
        // ImageRenderer needs AppKit initialised for text and symbol rendering.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("cannot create \(directory.path)\n".utf8))
            return false
        }

        var wrote = 0
        for fixture in Fixture.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let store = FixtureFactory.store(for: fixture)
                let name = "\(fixture.rawValue)-\(scheme == .light ? "light" : "dark").png"
                // Unscrolled: `ScrollView` has no intrinsic content under
                // `ImageRenderer`, so the harness would render an empty panel.
                let metrics = PopoverMetrics.fitting(Snapshotter.screen)
                let view = PopoverView(store: store,
                                       metricsOverride: metrics,
                                       scrolls: false)
                    .environment(\.colorScheme, scheme)
                    // The canvas follows the panel. Hard-coding the single-column
                    // width cropped every two-pane render in half, which looked
                    // like a layout fault and was a harness fault.
                    .frame(width: metrics.width)
                    .background(scheme == .light ? Color.white : Color.black)

                let dashName = "dashboard-\(fixture.rawValue)-\(scheme == .light ? "light" : "dark").png"
                // Taller than the window's default: the harness cannot scroll,
                // and the day view with a session running is about 900pt.
                let dash = DashboardView(store: store, scrolls: false)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 1020, height: 1240, alignment: .top)
                    .background(scheme == .light ? Color.white : Color.black)
                _ = render(dash, to: directory.appendingPathComponent(dashName))

                // The ordinary dashboard view returns to today on appearance.
                // Preserve yesterday only for this historical snapshot, so the
                // harness proves the past-day surface without changing app use.
                if fixture == .idleWithHistory {
                    store.stepDay(by: -1)
                    let pastDay = DashboardView(store: store, scrolls: false,
                                                returnsToTodayOnAppear: false)
                        .environment(\.colorScheme, scheme)
                        .frame(width: 1020, height: 1240, alignment: .top)
                        .background(scheme == .light ? Color.white : Color.black)
                    _ = render(pastDay, to: directory.appendingPathComponent(
                        "dashboard-past-idleWithHistory-\(scheme == .light ? "light" : "dark").png"))
                    store.goToToday()
                }

                // Week and Month share a code path, so one fixture with history
                // covers both; the empty state needs a fixture with none.
                let periods: [TrackingPeriod]
                switch fixture {
                case .idleWithHistory: periods = [.week, .month]
                case .firstRun: periods = [.week]
                default: periods = []
                }
                for period in periods {
                    store.period = period
                    let periodName = "period-\(period.rawValue)-\(fixture.rawValue)"
                        + "-\(scheme == .light ? "light" : "dark").png"
                    let periodView = DashboardView(store: store, scrolls: false)
                        .environment(\.colorScheme, scheme)
                        // Taller than the dashboard frame: a period's log is long,
                        // and the harness cannot scroll.
                        .frame(width: 1020, height: 1500, alignment: .top)
                        .background(scheme == .light ? Color.white : Color.black)
                    _ = render(periodView, to: directory.appendingPathComponent(periodName))
                }
                store.period = .day

                if render(view, to: directory.appendingPathComponent(name)) {
                    wrote += 1
                    print("  wrote \(name)")
                } else {
                    print("  FAILED \(name)")
                }
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            let strip = ComponentStrip()
                .environment(\.colorScheme, scheme)
                .frame(width: 2200)
            _ = render(strip, to: directory.appendingPathComponent(
                "components-\(scheme == .light ? "light" : "dark").png"))
            let quick = AwayAnswerGrid(away: 22 * 60,
                                       range: (Date().addingTimeInterval(-22 * 60), Date()),
                                       compact: true, onAnswer: { _ in }, onReason: { _ in })
                .padding(Tokens.Space.m).frame(width: 300)
                .background(Tokens.Surface.card)
                .environment(\.colorScheme, scheme)
            _ = render(quick, to: directory.appendingPathComponent(
                "awayPrompt-quick-\(scheme == .light ? "light" : "dark").png"))
            let full = AwayAnswerGrid(away: 72 * 60,
                                      range: (Date().addingTimeInterval(-72 * 60), Date()),
                                      showsCaptions: true, onAnswer: { _ in }, onReason: { _ in })
                .padding(Tokens.Space.xl).frame(width: 520)
                .background(Tokens.Surface.card)
                .environment(\.colorScheme, scheme)
            _ = render(full, to: directory.appendingPathComponent(
                "awayPrompt-full-\(scheme == .light ? "light" : "dark").png"))
        }
        print("\(wrote)/\(Fixture.allCases.count * 2) snapshots written to \(directory.path)")
        return wrote == Fixture.allCases.count * 2
    }

    @MainActor
    private static func render<V: View>(_ view: V, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
