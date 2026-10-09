import Foundation
import SwiftUI
import Combine
import AppKit

/// Headless logic tests (§7). Pure state-machine and time arithmetic with an
/// injected clock — no UI, no notifications, no run loop.
enum SelfTest: CheckSuite {

    /// 9:13 am on Wednesday 15 November 2023 wherever the checks run: the
    /// moment 1_700_000_000 is in Sydney. As that fixed moment it fell at
    /// 11 pm in Berlin, and fixtures stepping an hour on crossed midnight.
    static let base = gregorian.date(from: DateComponents(year: 2023, month: 11, day: 15,
                                                          hour: 9, minute: 13, second: 20))!
    /// One preferences suite per run. A fixed name let two runs at once, such
    /// as two worktrees building together, overwrite each other's settings
    /// mid-check and fail checks that were fine.
    static let suiteName = "com.prabesh.daybook.selftest.\(ProcessInfo.processInfo.processIdentifier)"
    static var scratchDirectories: [URL] = []

    static func cleanUp() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories.removeAll()
        FixtureFactory.cleanUp()
        // Empty this run's suite. Its plist goes in a sweep once cfprefsd has
        // written it: here, or when the next run starts.
        MemoryDefaults.suite(named: suiteName)?.removePersistentDomain(forName: suiteName)
        removeEmptiedPreferenceFiles()
    }

    /// Deletes the plists that emptied suites leave in Preferences. Emptying a
    /// suite is not enough: cfprefsd writes the empty plist about 15 seconds
    /// later, after the check that owned it has finished, so a file deleted at
    /// cleanup time comes straight back. Sweeping when each run starts and ends
    /// removes every one written by then, whichever run or check made it. Only
    /// a file that holds nothing is removed, so no setting is ever lost, and
    /// the app's own preferences file is never touched.
    static func removeEmptiedPreferenceFiles(in folder: URL = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")) {
        let prefix = FocusConstants.bundleIdentifier + "."
        let appFile = FocusConstants.bundleIdentifier + ".plist"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".plist") && name != appFile {
            let file = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file),
                  let contents = (try? PropertyListSerialization.propertyList(from: data, format: nil))
                    as? [String: Any],
                  contents.isEmpty else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Runner

    static func run() -> Bool {
        // Earlier runs' suites that cfprefsd emptied after those runs ended.
        removeEmptiedPreferenceFiles()
        var failures: [String] = []
        var passed = 0
        let tests = registeredTests

        print("Daybook self-test")
        for (index, test) in tests.enumerated() {
            let problems = test.1()
            let number = index < 9 ? " \(index + 1)" : "\(index + 1)"
            if problems.isEmpty {
                passed += 1
                print("  [PASS] \(number). \(test.0)")
            } else {
                print("  [FAIL] \(number). \(test.0)")
                for problem in problems {
                    print("         - \(problem)")
                    failures.append("\(index + 1): \(problem)")
                }
            }
        }
        cleanUp()
        print("\(passed)/\(tests.count) passed")
        return failures.isEmpty
    }

    static func expectClose(_ actual: TimeInterval,
                                    _ expected: TimeInterval,
                                    _ label: String,
                                    _ problems: inout [String]) {
        if abs(actual - expected) > 0.001 {
            problems.append("\(label): expected \(expected), got \(actual)")
        }
    }

    /// WCAG 2.x contrast from literal sRGB values. Test-only and independent
    /// of the production colour provider under test.
    static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let component = Double((hex >> UInt32(shift)) & 0xFF) / 255
                return component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let values = [luminance(first), luminance(second)]
        return ((values.max() ?? 0) + 0.05) / ((values.min() ?? 0) + 0.05)
    }
}
