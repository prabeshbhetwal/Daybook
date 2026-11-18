import Foundation

/// Activity-aware sessions: the evidence store, and the helper-to-app resolver
/// the screen-held reading depends on.
enum ActivityEvidenceStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A browser's helper reads as the browser", helperReadsAsBrowser),
        ("A helper whose parent is the launch daemon resolves by its bundle prefix, or to nothing", orphanResolvesByPrefix),
        ("A dictation app's helper never resolves to a browser", dictationNeverBrowser),
        ("A keep-awake utility resolves to nothing", keepAwakeResolvesToNothing),
        ("A parent loop ends", parentLoopEnds),
        ("A parent loop is cut by the visited set, one lookup, not by the depth bound", parentLoopIsCutAtOnce),
        ("A regular app exactly four parents up is found", fourthParentIsFound),
        ("A running session writes a beat every 30 seconds", writesEveryThirtySeconds),
        ("No beats are written with no session and automatic sessions off", writesNothingWhenOff),
        ("A partial beat is written once when recording stops", endsOnceWhenRecordingStops),
        ("A watching pause is written as one, any other pause as paused", pausesAreWrittenAsPauses),
        ("An app switch splits the beat's input by app", appSwitchSplitsInput),
        ("A beat names the app in front at launch", launchSeedsTheFrontApp),
        ("After a break or a wake the seconds go to the app now in front", resumeMovesToTheFrontApp),
        ("A beat's presence and holders are what the sampler read", presenceIsWhatTheSamplerRead),
        ("Holders not yet read are written as unread", holdersAreUnreadUntilRead),
        ("Recording never changes what the session counts", recordingChangesNothingCounted),
        ("A beat that cannot be written is dropped without an alert", failedWriteIsDropped),
        ("Expired beats are pruned on the first tick of a day", prunesOncePerDay),
        ("Nothing is recorded while Record app use is off, and it resumes when it is on", trackingOffRecordsNothing),
        ("Turning Record app use off mid-run writes the partial beat once", turningTrackingOffEndsOnce),
        ("A ticker that stops because app use is no longer recorded ends recording with it", tickerStopEndsRecording),
        ("Turning Record app use off ends recording before the next tick", settingOffEndsRecordingAtOnce),
        ("A quit writes the beat in progress, once", quitWritesThePartialBeat),
        ("A clock stepped back reads the counters once, not on every tick", steppedBackClockReadsOnce),
        ("An activation confirmed during a break is not recorded", waitingActivationIsNotDeliveredOnABreak),
        ("A backup leaves the beats out", backupLeavesBeatsOut),
    ]

    private static func proc(_ pid: Int32, parent: Int32?, _ bundle: String?, regular: Bool = false) -> ProcessInfoLite {
        ProcessInfoLite(pid: pid, parent: parent, bundleID: bundle, isRegularApp: regular)
    }

    private static func table(_ list: [ProcessInfoLite]) -> (Int32) -> ProcessInfoLite? {
        let byPid = Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
        return { byPid[$0] }
    }

    private static func helperReadsAsBrowser() -> [String] {
        var problems: [String] = []
        let browser = proc(100, parent: 1, "com.google.Chrome", regular: true)
        let mid = proc(150, parent: 100, "com.google.Chrome.helper")
        let helper = proc(200, parent: 150, "com.google.Chrome.helper.audio")
        let lookup = table([browser, mid, helper])
        let viaMid = OwningApp.resolve(helper, lookup: lookup, runningApps: ["com.google.Chrome"])
        expect(viaMid == "com.google.Chrome", "a helper under a helper under the browser names the browser, got \(String(describing: viaMid))", &problems)
        let direct = OwningApp.resolve(browser, lookup: lookup, runningApps: [])
        expect(direct == "com.google.Chrome", "a regular app names itself, got \(String(describing: direct))", &problems)
        var deep: [ProcessInfoLite] = []
        for n in 1...5 {
            let pid = Int32(300 + n)
            deep.append(proc(pid, parent: n == 1 ? 100 : pid - 1, "x.h\(n)"))
        }
        let tooDeep = OwningApp.resolve(deep[4], lookup: table([browser] + deep), runningApps: [])
        expect(tooDeep == nil, "an ancestor more than 4 parents away is not followed, got \(String(describing: tooDeep))", &problems)
        return problems
    }

    private static func orphanResolvesByPrefix() -> [String] {
        var problems: [String] = []
        let helper = proc(200, parent: 1, "com.google.Chrome.helper")
        let launchd = proc(1, parent: 0, nil)
        let lookup = table([helper, launchd])
        let hit = OwningApp.resolve(helper, lookup: lookup, runningApps: ["com.google.Chrome", "com.example.dictation"])
        expect(hit == "com.google.Chrome", "an orphaned helper matches its running app by prefix, got \(String(describing: hit))", &problems)
        let miss = OwningApp.resolve(helper, lookup: lookup, runningApps: ["com.example.dictation"])
        expect(miss == nil, "with no matching app running it resolves to nothing, got \(String(describing: miss))", &problems)
        let lookalike = OwningApp.resolve(proc(201, parent: 1, "com.google.ChromeX.helper"), lookup: lookup, runningApps: ["com.google.Chrome"])
        expect(lookalike == nil, "a prefix must end on a dot-separated component, got \(String(describing: lookalike))", &problems)
        let longest = OwningApp.resolve(helper, lookup: lookup, runningApps: ["com.google", "com.google.Chrome", "com"])
        expect(longest == "com.google.Chrome", "the longest matching prefix wins, got \(String(describing: longest))", &problems)
        return problems
    }

    private static func dictationNeverBrowser() -> [String] {
        var problems: [String] = []
        let helper = proc(200, parent: 1, "com.example.dictation.audio")
        let lookup = table([helper, proc(1, parent: 0, nil), proc(100, parent: 1, "com.google.Chrome", regular: true)])
        let alone = OwningApp.resolve(helper, lookup: lookup, runningApps: ["com.google.Chrome"])
        expect(alone == nil, "a dictation helper with only a browser running resolves to nothing, got \(String(describing: alone))", &problems)
        let both = OwningApp.resolve(helper, lookup: lookup, runningApps: ["com.google.Chrome", "com.example.dictation"])
        expect(both == "com.example.dictation", "it resolves to its own app, never the browser, got \(String(describing: both))", &problems)
        return problems
    }

    private static func keepAwakeResolvesToNothing() -> [String] {
        let util = proc(200, parent: 1, "com.example.keepawake")
        let got = OwningApp.resolve(util, lookup: table([util, proc(1, parent: 0, nil)]),
                                    runningApps: ["com.google.Chrome"])
        return expectNil(got, "a menu-bar keep-awake utility names no app")
    }

    private static func parentLoopEnds() -> [String] {
        let a = proc(200, parent: 201, "com.example.loop.a")
        let b = proc(201, parent: 200, "com.example.loop.b")
        let got = OwningApp.resolve(a, lookup: table([a, b]), runningApps: [])
        return expectNil(got, "a parent cycle ends without an answer")
    }

    private static func parentLoopIsCutAtOnce() -> [String] {
        var problems: [String] = []
        let a = proc(200, parent: 201, "com.example.loop.a")
        let b = proc(201, parent: 200, "com.example.loop.b")
        let known = table([a, b])
        var lookups = 0
        _ = OwningApp.resolve(a, lookup: { lookups += 1; return known($0) }, runningApps: [])
        // 200 to 201 and back to 200: the visited set stops it after one lookup; the bound of four alone would make four.
        expect(lookups == 1, "a cycle costs one lookup, got \(lookups)", &problems)
        return problems
    }

    private static func fourthParentIsFound() -> [String] {
        var problems: [String] = []
        let browser = proc(201, parent: 1, "com.google.Chrome", regular: true)
        let chain = [proc(202, parent: 201, "x.h1"), proc(203, parent: 202, "x.h2"),
                     proc(204, parent: 203, "x.h3"), proc(205, parent: 204, "x.h4")]
        let found = OwningApp.resolve(chain[3], lookup: table([browser] + chain), runningApps: [])
        expect(found == "com.google.Chrome", "the fourth parent is followed, got \(String(describing: found))", &problems)
        return problems
    }

    private static func expectNil(_ value: String?, _ what: String) -> [String] {
        var problems: [String] = []
        expect(value == nil, "\(what), got \(String(describing: value))", &problems)
        return problems
    }
}
