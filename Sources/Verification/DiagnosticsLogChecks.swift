import Foundation

/// The self-test's deliberate failures stay out of the unified log, where
/// they read as the app's own errors, and still reach the observer.
enum DiagnosticsLogChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The self-test's own failure lines stay out of the person's log", selfTestStaysOutOfUnifiedLog),
    ]

    private static func selfTestStaysOutOfUnifiedLog() -> [String] {
        var problems: [String] = []
        expect(!Diagnostics.writesUnifiedLog,
               "the self-test should not write to the unified log, got writesUnifiedLog = \(Diagnostics.writesUnifiedLog)",
               &problems)
        var seen: [String] = []
        let previous = Diagnostics.observer
        Diagnostics.observer = { seen.append($0) }
        Diagnostics.log("diagnostics check line", level: .info)
        Diagnostics.observer = previous
        expect(seen == ["diagnostics check line"], "the observer should still see the line, got \(seen)", &problems)
        return problems
    }
}
