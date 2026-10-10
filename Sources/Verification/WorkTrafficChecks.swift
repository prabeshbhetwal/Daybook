import Foundation

/// Noticing an app at work from what it sends and computes: reading
/// `nettop`, telling counted apps from the rest, and the rule that separates
/// work from an idle app's chatter.
enum WorkTrafficChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("nettop's per-process bytes are read, names with dots included", nettopIsRead),
        ("Coding and AI apps are work apps; a browser or an unknown app is not", workAppsAreKnown),
        ("Steady sending is an agent at work; one burst, a new process or a gap is not",
         busyNeedsSteadySending),
        ("A core kept busy is work going on; an idle app's processor use is not", busyComputing),
        ("The session's own apps are the ones worked in since it began, and the one in front",
         sessionAppsAreItsOwn),
        ("A child's processor time is counted once when it exits into its parent", exitedChildCountsOnce),
        ("A watched app never counts; an untouched coding app counts for sending only", countedAppsAreRight),
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
        let perReading = WorkTraffic.sending.busy / 2          // three of these pass the line
        func app(_ pid: Int32) -> String? { pid == 9 ? nil : "com.todesktop.230313mzl4w4u92" }
        func run(_ sent: [[Int32: UInt64]], gapAfter: Int? = nil) -> WorkTraffic {
            var traffic = WorkTraffic.sending
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

        let burst = run([[1: 0], [1: 3 * WorkTraffic.sending.busy], [1: 3 * WorkTraffic.sending.busy],
                         [1: 3 * WorkTraffic.sending.busy]])
        expect(burst.lastBusy == nil, "one burst between quiet readings is not work", &problems)

        let other = run([[9: 0], [9: perReading], [9: 2 * perReading], [9: 3 * perReading]])
        expect(other.lastBusy == nil, "a process outside the work apps is ignored", &problems)

        let fresh = run([[1: 0], [1: 0, 2: 50 * WorkTraffic.sending.busy], [1: 0, 2: 50 * WorkTraffic.sending.busy]])
        expect(fresh.lastBusy == nil, "a process first seen carries no recent bytes", &problems)

        let gap = run([[1: 0], [1: perReading], [1: 2 * perReading], [1: 3 * perReading]], gapAfter: 1)
        expect(gap.lastBusy == nil, "readings across a gap are not compared", &problems)
        return problems
    }

    private static func busyComputing() -> [String] {
        var problems: [String] = []
        let second: UInt64 = 1_000_000_000
        func run(coresPerReading cores: [Double]) -> Date? {
            var load = WorkTraffic.computing
            var total: UInt64 = 0
            var moment = SelfTest.base
            load.observe(totals: [7: 0], app: { _ in "com.blackmagic-design.DaVinciResolve" }, at: moment)
            for share in cores {
                total += UInt64(share * WorkTraffic.interval) * second
                moment = moment.addingTimeInterval(WorkTraffic.interval)
                load.observe(totals: [7: total], app: { _ in "com.blackmagic-design.DaVinciResolve" }, at: moment)
            }
            return load.lastBusy
        }
        expect(run(coresPerReading: [1.8, 1.8, 1.8]) != nil, "a render using 1.8 cores is work", &problems)
        expect(run(coresPerReading: [0.42, 0.42, 0.42]) == nil,
               "an idle app at 0.42 of a core, the most measured, is not", &problems)
        expect(run(coresPerReading: [3, 0, 0]) == nil, "one busy reading is not work", &problems)
        return problems
    }

    private static func sessionAppsAreItsOwn() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        func use(_ bundleID: String, from: TimeInterval, to: TimeInterval) -> AppUsageSession {
            AppUsageSession(bundleID: bundleID, appName: bundleID, start: start.addingTimeInterval(from),
                            end: start.addingTimeInterval(to), endReason: .appSwitch)
        }
        let apps = WorkTraffic.appsUsed([use("com.dropbox.before", from: -600, to: -60),
                                         use("com.blackmagic-design.DaVinciResolve", from: -60, to: 120),
                                         use("com.google.Chrome", from: 300, to: 400)],
                                        since: start, frontmost: "com.apple.Terminal")
        expect(apps == ["com.blackmagic-design.DaVinciResolve", "com.google.Chrome", "com.apple.Terminal"],
               "apps used in the session and the one in front, not one used only before it, got \(apps)",
               &problems)
        return problems
    }

    private static func exitedChildCountsOnce() -> [String] {
        var problems: [String] = []
        let s: UInt64 = 1_000_000_000
        var load = WorkTraffic.computing
        var moment = SelfTest.base
        // A child that worked long before the readings began, then exits:
        // its whole lifetime passes to the parent at once.
        for totals in [[1: 0, 2: 300 * s], [1: 0, 2: 300 * s], [1: 300 * s], [1: 305 * s]] as [[Int32: UInt64]] {
            load.observe(totals: totals, app: { _ in "com.apple.Terminal" }, at: moment)
            moment = moment.addingTimeInterval(WorkTraffic.interval)
        }
        expect(load.lastBusy == nil,
               "five seconds of new work is not a core for a minute, got \(String(describing: load.lastBusy))",
               &problems)
        return problems
    }

    private static func countedAppsAreRight() -> [String] {
        var problems: [String] = []
        let used: Set<String> = ["us.zoom.xos", "com.blackmagic-design.DaVinciResolve"]
        func counts(_ app: String, sending: Bool, watched: Set<String> = []) -> Bool {
            WorkTraffic.counts(app, used: used, watched: watched, own: "com.prabesh.daybook", sending: sending)
        }
        expect(!counts("us.zoom.xos", sending: true, watched: ["us.zoom.xos"]),
               "a call being watched is not work, however much it uploads", &problems)
        expect(!counts("us.zoom.xos", sending: true), "an audio-only call is not work either", &problems)
        expect(counts("com.blackmagic-design.DaVinciResolve", sending: false), "a render in a used app counts",
               &problems)
        expect(counts("com.todesktop.230313mzl4w4u92", sending: true),
               "an untouched Cursor sending is an agent at work", &problems)
        expect(!counts("com.todesktop.230313mzl4w4u92", sending: false),
               "an untouched Cursor's processor time does not count", &problems)
        expect(!counts("com.dropbox.desktop", sending: true), "an app never used does not count", &problems)
        expect(!counts("com.prabesh.daybook", sending: false), "Daybook never counts itself", &problems)
        return problems
    }
}
