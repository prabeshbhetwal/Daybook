import Foundation

/// Walking away from an unlocked Mac with an AI app in front and a keep-awake
/// app holding the screen on. Neither is a person: both stay exactly so after
/// the person has gone. Counting them held an hour of absence as work until
/// the long-away cap, then asked about only the minutes after it.
enum WalkAwayChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Walking away is an absence from the last input, whatever is in front or still working", walkAwayIsAnAbsence),
        ("A film watched past the long-away cap does not end the session when it stops", filmPastCapKeepsSession),
    ]

    private static func filmPastCapKeepsSession() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(sessionAge: 900, countsInput: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            r.persistence.idlePauseThreshold = 300
            r.persistence.longAwayCap = 3_600
            r.persistence.noticesAppsAtWork = false
            let playing = BreakStoreChecks.Box(true)
            r.store.readWatching = {
                .init(watching: playing.value, keptAwake: false, watchedApps: playing.value ? ["com.example.player"] : [])
            }
            let left = r.clock.value
            r.store.runTick()
            for seconds in [600.0, 3_600, 5_400, 5_430] {
                playing.value = seconds <= 5_400
                r.idle.value = seconds
                r.clock.value = left.addingTimeInterval(seconds)
                r.store.runTick()
            }
            // The film itself is kept as a watching rest; no session was ended.
            let ended = r.engine.archive.records.filter { $0.breakOrigin != .watching }
            expect(ended.isEmpty, "the film's end is presence, not an absence past the cap, got \(ended.count) records",
                   &problems)
            expect(r.engine.state == .running, "the session carries on after the film, got \(r.engine.state)", &problems)
            return problems
        }
    }

    private static func walkAwayIsAnAbsence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // (label, minutes away, last agent ping and autoplay start, in
            // seconds after leaving). 88 minutes passes the cap; 20 is asked about.
            let cases: [(String, Int, TimeInterval?, TimeInterval?)] = [
                ("AI app in front, keep-awake on, 88m", 88, nil, nil),
                ("AI app in front, keep-awake on, 20m", 20, nil, nil),
                ("agent pinging until the cap, 88m", 88, 3_590, nil),
                ("agent stopping at 40m, 88m", 88, 2_400, nil),
                ("agent stopping at 40m, then autoplay during the pause, 88m", 88, 2_400, 3_590),
            ]
            for (label, minutes, lastPing, autoplayFrom) in cases {
                guard let r = ActivityEvidenceStoreChecks.rig(sessionAge: 900, countsInput: true) else {
                    return ["could not create isolated preferences"]
                }
                defer { r.close() }
                // The retired opt-ins, on as they were on the Mac that found this.
                MemoryDefaults.suite(named: r.suite)?.set(true, forKey: "fc.countsAgentAppInFront")
                MemoryDefaults.suite(named: r.suite)?.set(true, forKey: "fc.countsKeepAwake")
                r.persistence.idlePauseThreshold = 300
                r.persistence.breakThreshold = 300
                r.persistence.longAwayCap = 3_600
                r.persistence.noticesAppsAtWork = false
                let autoplay = BreakStoreChecks.Box(false)
                r.store.readWatching = {
                    .init(watching: autoplay.value, keptAwake: true,
                          watchedApps: autoplay.value ? ["com.example.player"] : [])
                }
                r.activate("com.anthropic.claudefordesktop")

                let left = r.clock.value
                r.store.runTick()
                for seconds in [60.0, 600, 1_800, 2_400, 2_700, 3_590, 3_600, 4_200] where seconds < Double(minutes * 60) {
                    r.idle.value = seconds
                    r.clock.value = left.addingTimeInterval(seconds)
                    if let lastPing, seconds <= lastPing { r.store.lastAgentPing = r.clock.value }
                    autoplay.value = autoplayFrom.map { seconds >= $0 } ?? false
                    r.store.runTick()
                    if let record = r.engine.archive.records.first {
                        // Once the session has ended at the cap, its record is what counts.
                        SelfTest.expectClose(record.workSeconds, 900,
                                             "\(label): at \(Int(seconds))s the session has ended with its work", &problems)
                        expect(r.engine.state != .running, "\(label): nothing runs on after the cap, got \(r.engine.state)",
                               &problems)
                    } else if seconds > 3_600 {
                        problems.append("\(label): at \(Int(seconds))s the session should have ended at the cap")
                    } else if lastPing == nil, seconds >= 600 {
                        SelfTest.expectClose(r.engine.elapsed, 900,
                                             "\(label): at \(Int(seconds))s away nothing more counts", &problems)
                    }
                }
                r.clock.value = left.addingTimeInterval(Double(minutes * 60))
                r.idle.value = 0
                r.keys.value += 1
                r.store.runTick()
                if minutes == 88 {
                    // Past the cap the session ends where the person left.
                    let record = r.engine.archive.records.first
                    SelfTest.expectClose(record?.workSeconds ?? -1, 900,
                                         "\(label): only the work before leaving is kept", &problems)
                    SelfTest.expectClose(record?.end.timeIntervalSince(left) ?? -1, 0,
                                         "\(label): the session ends at the last input", &problems)
                } else {
                    let range = r.engine.pendingAwayRange
                    expect(range?.start == left && range?.end == r.clock.value,
                           "\(label): the question covers the last input to the return, got \(String(describing: range))",
                           &problems)
                    SelfTest.expectClose(r.engine.elapsed, 900, "\(label): the absence is out until answered", &problems)
                }
            }
            return problems
        }
    }
}
