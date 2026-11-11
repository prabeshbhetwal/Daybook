import Foundation

/// Settings opens in a window of its own, beside the story, not as a sheet
/// over it; Awards and Ask still attach to the main window.
enum SettingsWindowChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Settings opens in its own window, never as a sheet over the story", settingsIsNotASheet),
    ]

    private static func settingsIsNotASheet() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let settings = MainWindowView.nativeSheet(.settings)
            expect(settings == nil, "the main window attaches no Settings sheet, got \(String(describing: settings))",
                   &problems)
            for kind in [StorySheetKind.awards, .ask] {
                let shown = MainWindowView.nativeSheet(kind)
                expect(shown == kind, "\(kind) still attaches as a sheet, got \(String(describing: shown))", &problems)
            }
            expect(MainWindowView.nativeSheet(nil) == nil, "no sheet stays no sheet", &problems)
        }
        return problems
    }
}
