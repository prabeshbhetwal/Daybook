import AppKit
import Foundation
import SwiftUI

/// Settings' menus share one width, so a page's menus form a single column
/// rather than each hugging its own longest item ("4h" beside "last 14
/// days"). This breaks if a row goes back to a menu `Picker`, which sizes
/// itself to its items whatever frame it is given.
enum SettingsMenuWidthChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every menu in Settings' Goal panel is the same width", menusShareOneWidth),
    ]

    /// The Goal panel's seven rows are all menus, from "4h" to a category
    /// with its symbol, and nothing else there takes a keyboard stop; a page
    /// with a checkbox would mix its width in.
    private static func menusShareOneWidth() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let suite = "fc-selftest-settings-menu-width-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no isolated preferences"] }
            defer { MemoryDefaults.remove(named: suite) }
            let model = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                      onChange: {}, onTrackingChanged: { _ in })
            let widths = SettingsAlignmentChecks.controlFrames(SettingsGroups(model: model, section: .focus))
                .map(\.width)
            expect(widths.count >= 7, "the Goal panel's seven menus are drawn, found \(widths.count)", &problems)
            if let narrowest = widths.min(), let widest = widths.max() {
                expect(widest - narrowest <= 1, "every menu is one width, got \(widths.sorted())", &problems)
            }
            return problems
        }
    }
}
