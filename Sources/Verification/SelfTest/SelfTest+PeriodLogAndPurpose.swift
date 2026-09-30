import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 42

    static func testPeriodLog() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)

        // Today: two visits four minutes apart — one session, two visits.
        let morning = today.addingTimeInterval(10 * 3_600)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: morning,
                                     end: morning.addingTimeInterval(1_200)))
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: morning.addingTimeInterval(1_440),
                                     end: morning.addingTimeInterval(2_400)))
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            let start = yesterday.addingTimeInterval(9 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.b", appName: "Beta",
                                         start: start,
                                         end: start.addingTimeInterval(1_800)))
        }

        let stats = PeriodStats(sessions: SessionArchive(directory: sessionDir,
                                                         now: { clock.value }),
                                usage: usage, now: { clock.value })
        let log = stats.log(for: .week, containing: base)
        expect(log.count == 2, "two grouped sessions across the week, got \(log.count)",
               &problems)
        expect((log.first?.session.start ?? .distantPast)
               > (log.last?.session.start ?? .distantFuture),
               "the log is reverse chronological", &problems)
        expect(log.first?.session.visits == 2,
               "the two visits group into one session, got "
               + "\(log.first?.session.visits ?? -1)", &problems)
        expectClose(log.first?.session.attended ?? -1, 2_160,
                    "attended excludes the four-minute gap", &problems)

        expect(stats.log(for: .day, containing: base).count == 1,
               "the day period sees only today's session", &problems)

        let totals = stats.dayTotals(for: .week, containing: base)
        expect(totals.count == 2, "two days with totals, got \(totals.count)", &problems)
        expectClose(totals.values.reduce(0, +), 2_160 + 1_800,
                    "day totals sum to the log", &problems)

        // The one-pass rollup is what the dashboard actually calls; it must not
        // drift from the piecewise accessors the tests above pin down.
        let rollup = stats.rollup(for: .week, containing: base)
        expect(rollup.days == stats.days(for: .week, containing: base),
               "rollup days match days()", &problems)
        expect(rollup.log == log, "rollup log matches log()", &problems)
        expect(rollup.dayTotals == totals, "rollup totals match dayTotals()", &problems)
        expect(rollup.summary == stats.summary(for: .week, containing: base),
               "rollup summary matches summary()", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 43

    static func testAppPurpose() -> [String] {
        var problems: [String] = []

        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .active) == .coding,
               "Xcode is coding", &problems)
        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .passive) == .coding,
               "a fixed purpose ignores activity", &problems)
        expect(PurposeMap.purpose(for: "com.anthropic.claudefordesktop", activity: .passive)
               == .writingAI, "Claude is writing/AI", &problems)
        expect(PurposeMap.purpose(for: "com.figma.Desktop", activity: .active) == .design,
               "Figma is design", &problems)

        // The local stack, mapped so it never needs a manual correction. Bundle
        // identifiers read off the installed apps, not guessed.
        for id in ["dev.warp.Warp-Stable", "com.google.antigravity",
                   "com.google.antigravity-ide", "com.mongodb.compass",
                   "com.docker.docker", "com.todesktop.230313mzl4w4u92"] {
            expect(PurposeMap.purpose(for: id, activity: .passive) == .coding,
                   "\(id) is coding whatever the input", &problems)
            expect(CategoryManager.builtInMap[id] == .work,
                   "\(id) is work, so it never pauses a session", &problems)
        }
        // Dia is explicitly neutral: ambiguous purpose must not mean "pauses me".
        expect(CategoryManager.builtInMap["company.thebrowser.dia"] == .neutral,
               "Dia never pauses a session", &problems)
        expect(PurposeMap.purpose(for: "com.netflix.Netflix", activity: .active) == .media,
               "Netflix is media even while typing", &problems)

        // Unmapped falls to utility, not to a guess.
        expect(PurposeMap.purpose(for: "com.example.unknown", activity: .active) == .utility,
               "an unmapped bundle is a utility", &problems)
        expect(PurposeMap.purpose(for: nil, activity: .active) == .utility,
               "no bundle is a utility", &problems)

        // Ambiguous apps are decided by behaviour.
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .active) == .research,
               "Chrome with input is research", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .passive) == .media,
               "Chrome without input is media", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .absent) == .media,
               "an absent user is not doing research", &problems)
        expect(PurposeMap.purpose(for: "company.thebrowser.dia", activity: .active)
               == .writingAI, "Dia with input is writing/AI", &problems)

        // A user override wins over both the map and the behaviour.
        let overrides = ["com.google.Chrome": AppPurpose.coding.rawValue]
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .passive,
                                  overrides: overrides) == .coding,
               "an override beats the ambiguity rule", &problems)
        expect(PurposeMap.purpose(for: "com.example.unknown", activity: .passive,
                                  overrides: ["com.example.unknown": "media"]) == .media,
               "an override maps an unknown app", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .active,
                                  overrides: ["com.google.Chrome": "nonsense"]) == .research,
               "a corrupt override falls back to the rule", &problems)

        return problems
    }

    // MARK: - 44

    static func testSessionKind() -> [String] {
        var problems: [String] = []

        expect(AppPurpose.coding.isFocused, "coding is focused work", &problems)
        expect(AppPurpose.writingAI.isFocused, "writing/AI is focused work", &problems)
        expect(AppPurpose.design.isFocused, "design is focused work", &problems)
        expect(!AppPurpose.research.isFocused,
               "research supports focus but is not focus on its own", &problems)
        expect(!AppPurpose.communication.isFocused, "communication is not focus", &problems)
        expect(!AppPurpose.media.isFocused, "media is not focus", &problems)
        expect(!AppPurpose.utility.isFocused, "a utility is not focus", &problems)

        // Every purpose has a distinct label and symbol, or the UI cannot draw it.
        var labels = Set<String>()
        var symbols = Set<String>()
        for purpose in AppPurpose.allCases {
            labels.insert(purpose.displayName)
            symbols.insert(purpose.symbolName)
            expect(!purpose.displayName.isEmpty, "\(purpose) has a label", &problems)
        }
        expect(labels.count == AppPurpose.allCases.count,
               "labels are distinct, got \(labels.count)", &problems)
        expect(symbols.count == AppPurpose.allCases.count,
               "symbols are distinct, got \(symbols.count)", &problems)

        return problems
    }

    // MARK: - 45

    static func testInputDensity() -> [String] {
        var problems: [String] = []
        let start = base

        func feed(keys: UInt32, clicks: UInt32, scrolls: UInt32,
                  samples: Int, idle: TimeInterval = 0) -> InputDensity {
            let density = InputDensity()
            var k: UInt32 = 1_000, c: UInt32 = 50, s: UInt32 = 500
            for index in 0...samples {
                density.record(InputSample(at: start.addingTimeInterval(Double(index) * 20),
                                           keys: k, clicks: c, scrolls: s, idleSeconds: idle))
                k += keys; c += clicks; s += scrolls
            }
            return density
        }

        // One sample is not enough to measure a rate.
        let single = InputDensity()
        single.record(InputSample(at: start, keys: 0, clicks: 0, scrolls: 0, idleSeconds: 0))
        expect(single.activity == .passive,
               "a single sample cannot prove activity, got \(single.activity)", &problems)

        // 8 keys per 20s sample = 24/min, over the 12/min floor.
        expect(feed(keys: 8, clicks: 0, scrolls: 0, samples: 5).activity == .active,
               "sustained typing is active", &problems)

        // 2 keys per 20s = 6/min, under the floor, and no clicks.
        expect(feed(keys: 2, clicks: 0, scrolls: 0, samples: 5).activity == .passive,
               "occasional keys are not active", &problems)

        // Clicking with some keys is active: 2 clicks per 20s = 6/min.
        expect(feed(keys: 1, clicks: 2, scrolls: 0, samples: 5).activity == .active,
               "clicking with keys is active", &problems)

        // Clicking with no keys at all is not active — that is a video player.
        expect(feed(keys: 0, clicks: 2, scrolls: 0, samples: 5).activity == .passive,
               "clicks alone are not active", &problems)

        // Scrolling never qualifies: a film plays while a hand rests on a trackpad.
        expect(feed(keys: 0, clicks: 0, scrolls: 40, samples: 5).activity == .passive,
               "scrolling alone is passive", &problems)

        // Past the idle cutoff nobody is there, whatever the counters say.
        expect(feed(keys: 40, clicks: 40, scrolls: 40, samples: 5,
                    idle: AppUsageTracker.idleCutoff + 1).activity == .absent,
               "past the idle cutoff the user is absent", &problems)

        return problems
    }
}
