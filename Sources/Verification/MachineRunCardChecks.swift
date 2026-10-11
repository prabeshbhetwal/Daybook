import Foundation

/// Mac events with nothing between them on the story read as one card, the
/// way a gap card holds a hole's events, instead of a column of lines.
enum MachineRunCardChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Back-to-back Mac events gather into one card; a lone one stays a line", gathered),
        ("A run card names one repeated event by its count, and a mix as Mac events", titles),
        ("Expand all opens a run card", disclosure),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func quit(_ minutes: Double, backAfter seconds: TimeInterval? = 20,
                             kind: MachineEvent.Kind = .quitByApp) -> StoryMoment {
        let event = MachineEvent(kind: kind, at: at(minutes), detail: kind == .quitByApp ? "osascript" : nil)
        return .machine(event, resumed: seconds.map { event.at.addingTimeInterval($0) })
    }

    private static func gap(_ from: Double, _ to: Double) -> StoryTimelineItem {
        .moment(.unrecorded(DateInterval(start: at(from), end: at(to))))
    }

    private static func gathered() -> [String] {
        var problems: [String] = []
        // Newest first, as the story reads: three quits, an undo row, a fourth.
        let night: [StoryTimelineItem] = [
            .moment(quit(52)), .moment(quit(49)), .moment(quit(0)),
            .correction(UUID(), "Counted as focus", DateInterval(start: at(-30), end: at(-14))),
            .moment(quit(-30, backAfter: 960)),
        ]
        let rows = night.groupingQuietRuns()
        expect(rows.count == 3, "three quits, the undo row and the lone quit make 3 rows, got \(rows.count)", &problems)
        guard case .machineRun(let run)? = rows.first else { return problems + ["the three quits did not gather"] }
        expect(run.pins.map(\.event.at) == [at(52), at(49), at(0)],
               "the card keeps every quit newest first, got \(run.pins.map(\.event.at))", &problems)
        expect(run.span == DateInterval(start: at(0), end: at(52)),
               "the card spans the first quit to the last, got \(String(describing: run.span))", &problems)
        expect(run.allQuickReturns, "each quit was back within a minute", &problems)
        if case .item(.moment(.machine)) = rows.last {} else {
            problems.append("a lone quit after the undo row should stay a line, got \(rows.last?.id ?? "nothing")")
        }

        // Anything recorded between two quits keeps them apart.
        let split = [StoryTimelineItem.moment(quit(60)), gap(30, 40), .moment(quit(20))].groupingQuietRuns()
        expect(split.count == 3 && !split.contains { if case .machineRun = $0 { return true }; return false },
               "a gap between two quits keeps them as lines, got \(split.map(\.id))", &problems)
        return problems
    }

    private static func titles() -> [String] {
        var problems: [String] = []
        let same = StoryMachineRun(moments: [quit(2), quit(1)])
        expect(same.title == "Daybook quit by osascript · 2 times", "got \(same.title)", &problems)
        let mixed = StoryMachineRun(moments: [quit(3, kind: .restart), quit(2, backAfter: 300, kind: .crashed),
                                              quit(1)])
        expect(mixed.title == "3 Mac events", "got \(mixed.title)", &problems)
        expect(mixed.ruleKind == .crashed, "a crash flags the rule, got \(String(describing: mixed.ruleKind))", &problems)
        expect(!mixed.allQuickReturns, "a five-minute return is not within a minute", &problems)
        return problems
    }

    private static func disclosure() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let ids = DayStory.expandableIDs(in: [.moment(quit(2)), .moment(quit(1))])
            let run = StoryMachineRun(moments: [quit(2), quit(1)])
            expect(ids == [run.id], "Expand all opens the run card, got \(ids)", &problems)
            return problems
        }
    }
}
