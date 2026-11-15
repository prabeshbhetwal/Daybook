import AppKit
import Foundation
import SwiftUI

/// Every Settings panel explains itself in plain words through the info mark
/// at its corner. These break if a panel is added without an explanation or a
/// commented reason, an explanation names a control Settings does not show, the
/// words slip into jargon, a dash or an exclamation, or the mark leaves its card.
enum SettingsHelpChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every Settings panel has an explanation, or a commented reason it has none", everyPanelExplained),
        ("Every explanation names controls by the labels Settings shows", namesMatchLabels),
        ("Explanations use plain words, no dash or exclamation, at most 240 characters an entry", plainWords),
        ("The info mark sits inside its panel's top-right corner at 100% and 160% zoom", markInCorner),
    ]

    /// Words a person who has never used a time tracker should not meet, with
    /// their -s, -es, -d, -ed and -ing forms.
    static let bannedWords: Set<String> = ["foreground", "process", "evidence", "heuristic", "toggle", "enable",
                                           "persist", "bundle", "daemon", "api", "state", "simply", "just"]
    static let bannedPhrases = ["idle threshold", "note that"]

    // MARK: - Panels

    private static func everyPanelExplained() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let drawn = drawnPanels()
            let help = SettingsHelpText.groups
            for (title, panel) in drawn.sorted(by: { $0.key < $1.key }) {
                let skipped = SettingsHelpText.unexplained.contains(title)
                expect(panel.hasMark || skipped, "\(title) has no info mark and no reason on the list", &problems)
                expect(!(panel.hasMark && skipped), "\(title) has a mark but is listed as unexplained", &problems)
                expect(panel.hasMark == (help[title] != nil), "\(title)'s mark does not follow its help", &problems)
            }
            for title in Set(help.keys).union(SettingsHelpText.unexplained) where drawn[title] == nil {
                problems.append("\(title) is explained or listed, but Settings draws no such panel")
            }
            return problems
        }
    }

    private static func namesMatchLabels() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let help = SettingsHelpText.groups
            for (title, panel) in drawnPanels() {
                guard let entries = help[title] else { continue }
                // The labels Settings search finds on the panel's page.
                let labels = Set(SettingsPage(section: panel.section).sections.flatMap(\.controlLabels))
                for entry in entries where !labels.contains(entry.name) {
                    problems.append("\(title) explains \"\(entry.name)\", which its page does not show")
                }
                let names = entries.map(\.name)
                expect(Set(names).count == names.count, "\(title) explains a control twice: \(names)", &problems)
            }
            return problems
        }
    }

    private static func plainWords() -> [String] {
        var problems: [String] = []
        for (title, entries) in SettingsHelpText.groups {
            for entry in entries {
                let place = "\(title) › \(entry.name)"
                for mark in ["—", "–", "!"] where (entry.name + entry.text).contains(mark) {
                    problems.append("\(place) contains \(mark)")
                }
                let lower = entry.text.lowercased()
                for phrase in bannedPhrases where lower.contains(phrase) {
                    problems.append("\(place) says \"\(phrase)\"")
                }
                for word in lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
                    where isBanned(word) {
                    problems.append("\(place) says \"\(word)\"")
                }
                expect(entry.text.count <= 240,
                       "\(place) is \(entry.text.count) characters, over 240", &problems)
                expect(!entry.text.isEmpty, "\(place) says nothing", &problems)
            }
        }
        return problems
    }

    static func isBanned(_ word: String) -> Bool {
        if bannedWords.contains(word) { return true }
        return ["s", "es", "d", "ed", "ing"].contains { suffix in
            word.hasSuffix(suffix) && bannedWords.contains(String(word.dropLast(suffix.count)))
        }
    }

    // MARK: - The mark

    private static func markInCorner() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let entries = SettingsHelpText.groups["Goal"] else { return ["Goal has no explanation"] }
            for percent in [100, 160] {
                InterfaceZoomChecks.withZoom(percent) {
                    for density in [InterfaceDensity.comfortable, .compact] {
                        let layout = density.layout
                        let panel = SurfacePanel(title: "Goal", layout: layout) { Text("Daily goal") }
                            .environment(\.panelHelp, ["Goal": entries])
                            .frame(width: SettingsLayout.detailMeasure)
                        let (card, marks) = controlFrames(panel)
                        let label = "at \(percent)% \(density.rawValue)"
                        guard marks.count == 1, let mark = marks.first else {
                            problems.append("\(label) the panel drew \(marks.count) controls, not one mark")
                            continue
                        }
                        expect(card.insetBy(dx: -0.5, dy: -0.5).contains(mark),
                               "\(label) the mark \(mark) leaves its card \(card)", &problems)
                        expect(abs(card.maxX - mark.maxX - layout.insetPadding) <= 1,
                               "\(label) the mark ends \(card.maxX - mark.maxX) pt from the card's edge, "
                               + "not \(layout.insetPadding)", &problems)
                        expect(mark.midY < layout.insetPadding + AccessibilityMetrics.minimumTargetSize,
                               "\(label) the mark's centre is \(mark.midY) pt down, below the title's line",
                               &problems)
                    }
                }
            }
            return problems
        }
    }

    // MARK: - Drawing

    private final class Evidence {
        var value: [String: Bool] = [:]
    }

    struct DrawnPanel {
        let hasMark: Bool
        let section: SettingsSection
    }

    /// Every section drawn with Settings' explanations, the welcome's replay
    /// and both rule forms included, so a panel shown only sometimes is seen.
    @MainActor static func drawnPanels() -> [String: DrawnPanel] {
        let suite = "fc-selftest-settings-help-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return [:] }
        defer { MemoryDefaults.remove(named: suite) }
        let scratch = SelfTest.scratchDirectory()
        let model = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                  onChange: {}, onTrackingChanged: { _ in }, replayWelcome: {},
                                  dataDirectory: scratch, backupRoot: scratch,
                                  installedAppCatalog: FixtureFactory.installedAppCatalog())
        let rule = ActivityRule(name: "Coding", workType: .deepWork, bundleIDs: ["com.example.code"],
                                startAfter: 180)
        model.saveActivityRule(rule)
        let editor = SettingsDrafts.of(model).rule
        var drawn: [String: DrawnPanel] = [:]
        func draw(_ section: SettingsSection) {
            for (title, hasMark) in evidence(SettingsGroups(model: model, section: section)) {
                drawn[title] = DrawnPanel(hasMark: hasMark, section: section)
            }
        }
        SettingsSection.allCases.forEach(draw)
        editor.beginNew()
        draw(.activities)
        editor.edit(rule)
        draw(.activities)
        editor.close()
        return drawn
    }

    @MainActor private static func evidence<V: View>(_ view: V) -> [String: Bool] {
        let found = Evidence()
        let host = hosted(view.environment(\.panelHelp, SettingsHelpText.groups)
            .frame(width: SettingsLayout.detailMeasure)
            .onPreferenceChange(PanelHelpEvidenceKey.self) { found.value = $0 })
        host.window?.orderOut(nil)
        host.window?.close()
        return found.value
    }

    /// The card's bounds and the frames of the controls the keyboard can reach
    /// in it: the stand-in view SwiftUI gives each one.
    @MainActor private static func controlFrames<V: View>(_ view: V) -> (NSRect, [NSRect]) {
        let host = hosted(view)
        defer { host.window?.orderOut(nil); host.window?.close() }
        var frames: [NSRect] = []
        func walk(_ view: NSView) {
            if String(describing: type(of: view)).contains("KeyViewProxy") {
                frames.append(view.convert(view.bounds, to: host))
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        return (host.bounds, frames)
    }

    /// Laid out offscreen at its own fitting size, so the card fills the host
    /// and every frame is the card's, after a turn of the run loop.
    @MainActor private static func hosted<V: View>(_ view: V) -> NSView {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        return host
    }
}
