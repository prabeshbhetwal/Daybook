import Foundation
import SwiftUI
import AppKit

/// Settings reads the same to a keyboard, a screen reader and a low-vision
/// reader as it does to the eye. These break if a refused value is quietly
/// accepted, the sidebar's arrows wrap or skip, a page tile's glyph falls
/// under 3:1, or a renamed row can no longer be searched for.
enum SettingsAccessibilityChecks {
    static let tests: [(String, () -> [String])] = [
        ("A custom number of minutes is refused outside 1 to 1,440 or when not whole", customMinutes),
        ("Settings sidebar arrows move one page and stop at either end", sidebarNeighbours),
        ("Every Settings page tile's glyph reaches 3:1 in light and dark", tileGlyphContrast),
        ("Settings search finds the plainly worded rows by their new names", plainWordsSearch),
        ("An archive that needed nothing says so plainly", plainRecovery)
    ]

    private static func customMinutes() -> [String] {
        var failures: [String] = []
        for (text, expected) in [("1", 1), ("1440", 1_440), (" 30 ", 30)] {
            if ThresholdControl.minutes(from: text) != expected {
                failures.append("\"\(text)\" was not read as \(expected) minutes")
            }
        }
        for text in ["0", "1441", "2.5", "", "abc", "-5", "1,440"] {
            if let minutes = ThresholdControl.minutes(from: text) {
                failures.append("\"\(text)\" was accepted as \(minutes) minutes")
            }
        }
        if !ThresholdControl.rejection.contains("1,440") {
            failures.append("the refusal no longer states the accepted range")
        }
        return failures
    }

    private static func sidebarNeighbours() -> [String] {
        var failures: [String] = []
        let all = SettingsPage.allCases
        if SettingsPage.general.neighbour(in: all, by: -1) != nil {
            failures.append("up from the first page wrapped or moved")
        }
        if all.last?.neighbour(in: all, by: 1) != nil {
            failures.append("down from the last page wrapped or moved")
        }
        if SettingsPage.general.neighbour(in: all, by: 1) != .sessions {
            failures.append("down from General did not open Sessions")
        }
        // A search that hides pages moves between the pages still listed.
        let filtered: [SettingsPage] = [.general, .recording, .privacy]
        if SettingsPage.recording.neighbour(in: filtered, by: -1) != .general
            || SettingsPage.recording.neighbour(in: filtered, by: 1) != .privacy {
            failures.append("arrows moved to a page the search had hidden")
        }
        if SettingsPage.sessions.neighbour(in: filtered, by: 1) != nil {
            failures.append("a page missing from the list still had a neighbour")
        }
        return failures
    }

    private static func tileGlyphContrast() -> [String] {
        var failures: [String] = []
        for page in SettingsPage.allCases {
            for dark in [false, true] {
                guard let tile = srgb(Tokens.Palette.hue(page.hue), dark: dark),
                      let glyph = srgb(page.glyphColour, dark: dark) else {
                    failures.append("\(page.title) tile colours could not be resolved")
                    continue
                }
                let ratio = contrast(tile, glyph)
                if ratio < 3 {
                    failures.append("\(page.title) glyph is \(String(format: "%.2f", ratio)):1 in "
                                    + (dark ? "dark" : "light"))
                }
            }
        }
        return failures
    }

    private static func plainWordsSearch() -> [String] {
        var failures: [String] = []
        let expectations: [(String, SettingsPage)] = [
            ("Guess sessions", .sessions),
            ("paused automatic session", .sessions),
            ("measured precisely", .privacy),
            ("backup", .privacy)
        ]
        for (query, page) in expectations where SettingsPage.matching(query) != [page] {
            failures.append("searching \"\(query)\" returned \(SettingsPage.matching(query).map(\.title))")
        }
        let jargon = SettingsSection.allCases.flatMap(\.controlLabels).filter {
            $0.localizedCaseInsensitiveContains("legacy") || $0.localizedCaseInsensitiveContains("epoch")
        }
        if !jargon.isEmpty { failures.append("search still lists \(jargon)") }
        return failures
    }

    private static func plainRecovery() -> [String] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-settings-a11y-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = SettingsDiagnostics.live(usage: AppUsageArchive(directory: directory, now: { now }),
                                               sessions: SessionArchive(directory: directory, now: { now }),
                                               dataDirectory: directory).recoverySummary
        return summary == "Nothing needed recovering."
            ? [] : ["a clean archive's recovery reads: \(summary)"]
    }

    // MARK: - Colour

    private static func srgb(_ colour: Color, dark: Bool) -> (Double, Double, Double)? {
        let resolved = NSColor(colour)
        var result: (Double, Double, Double)?
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            if let rgb = resolved.usingColorSpace(.sRGB) {
                result = (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
            }
        }
        return result
    }

    private static func contrast(_ first: (Double, Double, Double), _ second: (Double, Double, Double)) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func luminance(_ rgb: (Double, Double, Double)) -> Double {
            0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
        }
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}
