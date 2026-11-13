import Foundation

/// Every app wears the one app-use accent, so what tells apps apart is a
/// divider where the app changes, an icon where there is room, and a name in
/// the label. Hash colours painted Xcode, Chrome and Spotify the same gold.
enum AppMarkChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("App marks carry no per-app colour: the segment, interval and hour models hold none",
         modelsCarryNoColour),
        ("A strip has one divider between each pair of neighbouring runs and none at its ends",
         dividersSitBetweenRuns),
        ("An app's icon shows in a run only when the run is wide and tall enough, at any zoom",
         iconShowsOnlyWhenWide),
        ("A strip run's and a rhythm bar's accessibility label names the app",
         labelsNameTheApp),
        ("A rhythm hour names its top app, and a clock-hour figure names the app it is for",
         rhythmHoursNameTheirApp),
    ]

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func segment(_ app: String, _ from: TimeInterval, _ to: TimeInterval) -> TimelineSegment {
        TimelineSegment(id: UUID(), bundleID: "test." + app.lowercased(), appName: app,
                        start: start.addingTimeInterval(from), end: start.addingTimeInterval(to))
    }

    private static func fieldNames(_ value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

    /// Fails on the hash colours: a colour slot rode on each of these.
    private static func modelsCarryNoColour() -> [String] {
        var problems: [String] = []
        let models: [(String, Any)] = [
            ("TimelineSegment", segment("Xcode", 0, 60)),
            ("RhythmHour", RhythmHour(hour: start, seconds: 60)),
            ("RecordedActivity.Interval",
             RecordedActivity.Interval(start: start, end: start.addingTimeInterval(60),
                                       bundleID: "test.xcode", appName: "Xcode")),
            ("AppDayHistory", AppDayHistory(bundleID: "test.xcode", appName: "Xcode", total: 60, sessions: [])),
        ]
        for (name, model) in models {
            let colourFields = fieldNames(model).filter { $0.lowercased().contains("colo") }
            expect(colourFields.isEmpty, "\(name) still carries \(colourFields)", &problems)
        }
        let a = segment("Xcode", 0, 60), b = segment("Chrome", 0, 60)
        expect(Set(fieldNames(a)) == Set(fieldNames(b)) && fieldNames(a).count == 6,
               "two different apps' segments differ only by their own fields", &problems)
        return problems
    }

    private static func dividersSitBetweenRuns() -> [String] {
        var problems: [String] = []
        let span = DateInterval(start: start, end: start.addingTimeInterval(1_800))
        let three = RecordedActivity(segments: [segment("A", 0, 600), segment("B", 600, 1_200),
                                                segment("A", 1_200, 1_800)], spans: [span])
        let runs = SessionShape.runs(activity: three, cellCount: 6)
        expect(runs.map(\.bundleID) == ["test.a", "test.b", "test.a"], "three runs, got \(runs.map(\.bundleID))", &problems)
        expect(AppMarkLayout.dividerCells(runs) == [2, 4],
               "one divider at each app switch, got \(AppMarkLayout.dividerCells(runs))", &problems)

        let gapped = RecordedActivity(segments: [segment("A", 0, 300), segment("C", 900, 1_200)],
                                      spans: [DateInterval(start: start, end: start.addingTimeInterval(1_200))])
        let gapRuns = SessionShape.runs(activity: gapped, cellCount: 8)
        expect(AppMarkLayout.dividerCells(gapRuns).count == gapRuns.count - 1,
               "a gap run is divided from its neighbours too: \(AppMarkLayout.dividerCells(gapRuns)) for \(gapRuns.count) runs",
               &problems)
        let total = runs.reduce(0) { $0 + $1.cells }
        expect(AppMarkLayout.dividerCells(runs).allSatisfy { $0 > 0 && $0 < total },
               "no divider at either end of the strip", &problems)

        let one = SessionShape.runs(activity: RecordedActivity(segments: [segment("A", 0, 1_800)], spans: [span]),
                                    cellCount: 6)
        expect(one.count == 1 && AppMarkLayout.dividerCells(one).isEmpty, "one app, no divider", &problems)
        expect(AppMarkLayout.dividerCells([]).isEmpty, "no runs, no divider", &problems)

        // One app across two stretches arrives as two runs: no divider
        // between them and one icon, centred on both.
        let t = start
        let split = [SessionShape.Run(id: 0, start: t, end: t.addingTimeInterval(600), bundleID: "test.a",
                                      cells: 2, recordedSeconds: 600),
                     SessionShape.Run(id: 1, start: t.addingTimeInterval(900), end: t.addingTimeInterval(1_500),
                                      bundleID: "test.a", cells: 2, recordedSeconds: 600),
                     SessionShape.Run(id: 2, start: t.addingTimeInterval(1_500), end: t.addingTimeInterval(1_800),
                                      bundleID: "test.b", cells: 1, recordedSeconds: 300)]
        expect(AppMarkLayout.dividerCells(split) == [4],
               "the same app across two runs has no divider inside it, got \(AppMarkLayout.dividerCells(split))",
               &problems)
        let streaks = AppMarkLayout.streaks(split)
        expect(streaks == [AppMarkLayout.Streak(bundleID: "test.a", startCell: 0, cells: 4),
                           AppMarkLayout.Streak(bundleID: "test.b", startCell: 4, cells: 1)],
               "one icon per unbroken app, got \(streaks)", &problems)
        return problems
    }

    private static func iconShowsOnlyWhenWide() -> [String] {
        var problems: [String] = []
        let needed = AppMarkLayout.iconPoints + 2 * AppMarkLayout.paddingPoints
        expect(needed == 24, "icon plus padding is 24 points at 100%, got \(needed)", &problems)
        expect(AppMarkLayout.showsIcon(width: 24, height: 28, scale: 1), "24 wide fits the icon at 100%", &problems)
        expect(!AppMarkLayout.showsIcon(width: 23.9, height: 28, scale: 1), "23.9 wide does not", &problems)
        expect(!AppMarkLayout.showsIcon(width: 40, height: 20, scale: 1), "a run too short for the icon shows none", &problems)
        expect(!AppMarkLayout.showsIcon(width: 35, scale: 1.5), "35 wide is short of 36 at 150%", &problems)
        expect(AppMarkLayout.showsIcon(width: 36, scale: 1.5), "36 wide fits at 150%", &problems)
        expect(AppMarkLayout.showsIcon(width: 30, scale: 1), "30 wide fits at 100%", &problems)
        expect(!AppMarkLayout.showsIcon(width: 30, scale: 1.5), "the same 30 does not at 150%", &problems)
        expect(AppMarkLayout.showsIcon(width: 20, scale: 0.8), "20 wide fits at 80%", &problems)
        expect(!AppMarkLayout.showsIcon(width: 0, scale: 1), "an empty run shows none", &problems)
        return problems
    }

    private static func labelsNameTheApp() -> [String] {
        var problems: [String] = []
        let end = start.addingTimeInterval(600)
        let run = SessionShape.Run(id: 0, start: start, end: end, bundleID: "test.xcode", cells: 2,
                                   recordedSeconds: 600)
        let named = StoryShapeChart.detail(run, names: ["test.xcode": "Xcode"])
        expect(named.contains("Xcode") && named.contains(Tokens.timeRange(start, end)),
               "a run's label names the app and its time range: \(named)", &problems)
        expect(StoryShapeChart.detail(run, names: [:]).contains("test.xcode"),
               "an unnamed app is still named by its bundle ID", &problems)
        let gap = SessionShape.Run(id: 1, start: start, end: end, bundleID: nil, cells: 2, recordedSeconds: 0)
        expect(!StoryShapeChart.detail(gap, names: ["test.xcode": "Xcode"]).contains("Xcode"),
               "a gap names no app", &problems)

        let hour = RhythmHour(hour: start, seconds: 1_800, topBundleID: "test.xcode", topAppName: "Xcode")
        let label = RhythmChart.label(for: hour)
        expect(label.contains("Xcode") && label.contains(DateFormats.hourLabel(start)),
               "a rhythm bar's label names its hour and app: \(label)", &problems)
        expect(!RhythmChart.label(for: RhythmHour(hour: start, seconds: 1_800)).contains("mostly"),
               "a bar summing many apps names none", &problems)
        expect(!RhythmChart.label(for: RhythmHour(hour: start, seconds: 0, topBundleID: "test.xcode",
                                                  topAppName: "Xcode")).contains("Xcode"),
               "an empty hour names no app", &problems)
        return problems
    }

    private static func rhythmHoursNameTheirApp() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        func seg(_ app: String, _ from: TimeInterval, _ to: TimeInterval) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: "test." + app.lowercased(), appName: app,
                            start: hourStart.addingTimeInterval(from), end: hourStart.addingTimeInterval(to))
        }
        let hours = Rhythm.hours(segments: [seg("Xcode", 0, 1_200), seg("Chrome", 1_200, 3_000)],
                                 window: (hourStart, hourStart.addingTimeInterval(7_200)), calendar: calendar)
        expect(hours.count == 2, "two hours, got \(hours.count)", &problems)
        guard hours.count == 2 else { return problems }
        expect(hours[0].topBundleID == "test.chrome" && hours[0].topAppName == "Chrome",
               "the hour goes to the app with most time, named", &problems)
        expect(hours[1].topBundleID == nil && hours[1].topAppName == nil, "an empty hour names no app", &problems)

        let clock = Rhythm.clockHours(app: ("test.xcode", "Xcode"), calendar: calendar) { $0 == 9 ? 600 : 0 }
        expect(clock.count == 24, "24 clock hours", &problems)
        expect(clock.filter { $0.topBundleID != nil }.count == 1 && clock[9].topAppName == "Xcode",
               "only the hour with use names the app", &problems)
        expect(Rhythm.clockHours(calendar: calendar) { _ in 60 }.allSatisfy { $0.topBundleID == nil },
               "a figure summing every app names none", &problems)
        return problems
    }
}
