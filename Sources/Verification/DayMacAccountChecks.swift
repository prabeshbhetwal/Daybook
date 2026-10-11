import Foundation

/// The day's Mac card tells the day the way a gap card tells a hole: a lock
/// and its unlock make one line, a quit and its relaunch make one, and the
/// time the Mac was in use is left out.
enum DayMacAccountChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The day's Mac events read as stretches away from the desk, newest first", stretches),
        ("The Mac card's summary adds up locked time and counts quits and restarts", summary),
        ("A day the Mac was only in use has no Mac card", inUseOnly),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }
    private static let day = DateInterval(start: at(0), end: at(200))

    private static func event(_ kind: MachineEvent.Kind, _ minutes: Double, detail: String? = nil) -> MachineEvent {
        MachineEvent(kind: kind, at: at(minutes), detail: detail)
    }

    /// A lock with its display, a quick quit by a script, a quit, a restart.
    private static let morning: [MachineEvent] = [
        event(.lock, 10), event(.displaySleep, 10), event(.unlock, 40), event(.displayWake, 40),
        event(.quitByApp, 60, detail: "osascript"), event(.daybookStarted, 60.25),
        event(.quit, 90), event(.daybookStarted, 100),
        event(.restart, 150), event(.macStarted, 154), event(.daybookStarted, 155),
    ]

    private static func stretches() -> [String] {
        var problems: [String] = []
        let rows = DayMacAccount(span: day, events: morning).rows
        let titles = rows.map(\.title)
        expect(titles == ["Mac restarted", "Daybook quit", "Daybook quit by osascript", "Mac locked"],
               "eleven events make four lines, newest first, got \(titles)", &problems)
        expect(!rows.contains { $0.state == .unexplained },
               "time the Mac was in use is not a line, got \(rows.map(\.state))", &problems)
        if let lock = rows.last {
            expect(lock.span == DateInterval(start: at(10), end: at(40)) && lock.displayOff == lock.span,
                   "the lock and its display are one stretch, got \(lock.span), \(String(describing: lock.displayOff))",
                   &problems)
        }
        return problems
    }

    private static func summary() -> [String] {
        var problems: [String] = []
        let morningSummary = DayMacAccount(span: day, events: morning).summary
        expect(morningSummary == "Locked 30m · Daybook quit 2 times · Mac restarted", "got \(morningSummary)", &problems)
        let scripted = DayMacAccount(span: day, events: [
            event(.quitByApp, 20, detail: "osascript"), event(.daybookStarted, 20.5),
            event(.quitByApp, 30, detail: "osascript"), event(.daybookStarted, 30.5),
            MachineEvent(kind: .crashed, at: at(50), latest: at(52)), event(.daybookStarted, 52),
        ]).summary
        expect(scripted == "Daybook quit by osascript 2 times · Daybook crashed",
               "one quitter is named, and a crash by its own name, got \(scripted)", &problems)
        return problems
    }

    private static func inUseOnly() -> [String] {
        var problems: [String] = []
        let account = DayMacAccount(span: day, events: [event(.daybookStarted, 5)])
        expect(account.rows.isEmpty, "a launch alone leaves nothing to tell, got \(account.rows.map(\.title))", &problems)
        return problems
    }
}
