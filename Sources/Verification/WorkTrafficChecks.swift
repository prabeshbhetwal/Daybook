import Foundation

/// Noticing an AI tool at work from what it sends: reading `nettop`, telling
/// work apps from the rest, and the rule that separates a step of work from
/// an idle app's chatter.
enum WorkTrafficChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("nettop's per-process bytes are read, names with dots included", nettopIsRead),
        ("Coding and AI apps are work apps; a browser or an unknown app is not", workAppsAreKnown),
        ("Steady sending is an agent at work; one burst, a new process or a gap is not",
         busyNeedsSteadySending),
    ]

    private static func nettopIsRead() -> [String] {
        var problems: [String] = []
        let csv = """
            ,bytes_out,
            launchd.1,0,
            Cursor Helper (Plugin).4242,123456,
            com.apple.WebKit.Networking.77,900,
            not a row
            claude.55806,7,
            """
        let totals = WorkTraffic.totals(fromNettop: csv)
        expect(totals == [1: 0, 4242: 123_456, 77: 900, 55806: 7],
               "every process row is read by its last dot, got \(totals)", &problems)
        return problems
    }

    private static func workAppsAreKnown() -> [String] {
        var problems: [String] = []
        for app in ["com.todesktop.230313mzl4w4u92", "com.google.antigravity", "com.microsoft.VSCode",
                    "com.apple.Terminal", "com.mitchellh.ghostty", "com.anthropic.claudefordesktop"] {
            expect(AgentPresence.isWorkApp(app), "\(app) is a work app", &problems)
        }
        for app in ["com.apple.Safari", "com.spotify.client", "com.example.unknown"] {
            expect(!AgentPresence.isWorkApp(app), "\(app) is not a work app", &problems)
        }
        return problems
    }

    private static func busyNeedsSteadySending() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        let step = WorkTraffic.interval
        let perReading = WorkTraffic.busyBytes / 2              // three of these pass the line
        func app(_ pid: Int32) -> String? { pid == 9 ? nil : "com.todesktop.230313mzl4w4u92" }
        func run(_ sent: [[Int32: UInt64]], gapAfter: Int? = nil) -> WorkTraffic {
            var traffic = WorkTraffic()
            var moment = start
            for (index, totals) in sent.enumerated() {
                traffic.observe(totals: totals, app: app, at: moment)
                moment = moment.addingTimeInterval(index == gapAfter ? 10 * step : step)
            }
            return traffic
        }
        let starting = run([[1: 0], [1: perReading], [1: 2 * perReading]])
        expect(starting.lastBusy == start.addingTimeInterval(2 * step),
               "two steady readings are busy, got \(String(describing: starting.lastBusy))", &problems)
        let steady = run([[1: 0], [1: perReading], [1: 2 * perReading], [1: 3 * perReading]])
        expect(steady.lastBusy == start.addingTimeInterval(3 * step),
               "steady sending stays busy to the latest reading, got \(String(describing: steady.lastBusy))",
               &problems)
        let one = run([[1: 0], [1: perReading]])
        expect(one.lastBusy == nil, "one reading is not enough, got \(String(describing: one.lastBusy))", &problems)

        let burst = run([[1: 0], [1: 3 * WorkTraffic.busyBytes], [1: 3 * WorkTraffic.busyBytes],
                         [1: 3 * WorkTraffic.busyBytes]])
        expect(burst.lastBusy == nil, "one burst between quiet readings is not work", &problems)

        let other = run([[9: 0], [9: perReading], [9: 2 * perReading], [9: 3 * perReading]])
        expect(other.lastBusy == nil, "a process outside the work apps is ignored", &problems)

        let fresh = run([[1: 0], [1: 0, 2: 50 * WorkTraffic.busyBytes], [1: 0, 2: 50 * WorkTraffic.busyBytes]])
        expect(fresh.lastBusy == nil, "a process first seen carries no recent bytes", &problems)

        let gap = run([[1: 0], [1: perReading], [1: 2 * perReading], [1: 3 * perReading]], gapAfter: 1)
        expect(gap.lastBusy == nil, "readings across a gap are not compared", &problems)
        return problems
    }
}
