import Foundation

/// With the site signal on, a browser's seconds are credited by the kind of site it showed;
/// with it off, sites are ignored. Traces are minutes from `SelfTest.base`.
enum SiteCreditChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Reading documentation hands-off is research, not media", documentationHandsOff),
        ("Typing on a social site is not research", typingOnSocial),
        ("A meeting in the browser is communication", meetingInBrowser),
        ("Social time is outside the work, so it is never deep", socialNeverDeep),
        ("When the site decides the label, it is Mixed", siteDecidesLabel),
        ("A person's purpose for the browser beats the site", overrideBeatsSite),
        ("The fingerprint names the site kind with most time", fingerprintSiteKind),
        ("Signals are listed only when a beat carries a site", signalsCarried),
        ("A watching pause on a meeting site is shown as a call", watchingPauseOnMeeting),
    ]

    /// Registered after the suites that followed this one, so earlier check numbers stay put.
    static let laterTests: [(String, () -> [String])] = [
        ("A browser outside the purpose map is credited by its site too", unmappedBrowser),
        ("A held run is a call only when most of the browser's seconds were on a meeting", meetingMajority),
    ]

    private static let editor = "com.microsoft.VSCode"
    private static let browser = "com.google.Chrome"
    private static let siteOn: Set<SignalKind> = [.siteKind]

    private static func at(_ seconds: TimeInterval) -> Date { SelfTest.base.addingTimeInterval(seconds) }
    private static func step(_ app: String, _ minutes: Double, _ input: BeatTrace.Input, site: SiteKind? = nil,
                             holder: String? = nil) -> BeatTrace.Step {
        BeatTrace.Step(app: app, minutes: minutes, input: input, holder: holder, site: site)
    }
    private static func trace(_ steps: [BeatTrace.Step]) -> [Beat] { BeatTrace.beats(steps, from: SelfTest.base) }

    private static func whole(_ beats: [Beat]) -> DateInterval {
        DateInterval(start: beats[0].start, end: beats[beats.count - 1].end)
    }
    /// Counted from the first beat to the last, or for the first `countedMinutes` only.
    private static func input(_ beats: [Beat], _ signals: Set<SignalKind>, overrides: [String: String] = [:],
                              countedMinutes: Double? = nil) -> CreditInput {
        let counted = countedMinutes.map { DateInterval(start: beats[0].start, duration: $0 * 60) } ?? whole(beats)
        return CreditInput(beats: beats, counted: [counted], signals: signals, purposeOverrides: overrides)
    }
    private static func credit(_ beats: [Beat], _ signals: Set<SignalKind>,
                               overrides: [String: String] = [:]) -> [CreditedSlice] {
        ActivityCredit.credit(input(beats, signals, overrides: overrides))
    }
    private static func derive(_ beats: [Beat], _ signals: Set<SignalKind>, overrides: [String: String] = [:],
                               countedMinutes: Double? = nil) -> SessionActivityShape {
        let credit = input(beats, signals, overrides: overrides, countedMinutes: countedMinutes)
        return ActivityDerivation.derive(DerivationInput(credit: credit, bounds: whole(beats),
                                                         countsWhileWatching: false, isRunning: false,
                                                         now: whole(beats).end))
    }

    private static func summary(_ slices: [CreditedSlice]) -> String {
        slices.map { "\(Int($0.start.timeIntervalSince(SelfTest.base)))+\(Int($0.end.timeIntervalSince($0.start))) "
            + "\($0.state.rawValue) \($0.purpose?.rawValue ?? "nil")" }.joined(separator: ", ")
    }

    /// Every second of [from, to) is credited once, with a state `states` allows and this purpose.
    private static func expectAll(_ slices: [CreditedSlice], _ from: TimeInterval, _ to: TimeInterval,
                                  _ states: Set<CreditState>, _ purpose: AppPurpose?, _ what: String,
                                  _ problems: inout [String]) {
        let part = slices.filter { $0.start >= at(from) && $0.end <= at(to) }
        let seconds = part.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        expect(part.allSatisfy { states.contains($0.state) && $0.purpose == purpose } && seconds == to - from,
               "\(what): \(Int(from))..\(Int(to)) s should be \(states.map(\.rawValue).sorted()) "
                   + "\(purpose?.rawValue ?? "nil") throughout, got \(summary(part))", &problems)
    }

    private static func documentationHandsOff() -> [String] {
        var problems: [String] = []
        let beats = trace([step(browser, 2, .keys, site: .documentation), step(browser, 6, .none, site: .documentation)])
        let on = credit(beats, siteOn)
        expectAll(on, 0, 120, [.engaged], .research, "typing on documentation", &problems)
        expectAll(on, 120, 480, [.quietKept], .research, "reading documentation hands-off", &problems)
        expectAll(credit(beats, []), 240, 480, [.passive], .media, "the same beats with the signal off", &problems)
        return problems
    }

    private static func typingOnSocial() -> [String] {
        var problems: [String] = []
        let slices = credit(trace([step(browser, 10, .keys, site: .social)]), siteOn)
        expectAll(slices, 0, 600, [.engaged], .media, "typing on a social site", &problems)
        return problems
    }

    private static func meetingInBrowser() -> [String] {
        var problems: [String] = []
        for (site, purpose) in [(SiteKind.meeting, AppPurpose.communication), (.video, .media)] {
            let slices = credit(trace([step(browser, 20, .none, site: site, holder: browser)]), siteOn)
            expectAll(slices, 0, 1_200, [.held], purpose, "a browser holding the screen on \(site.rawValue)", &problems)
        }
        return problems
    }

    private static func socialNeverDeep() -> [String] {
        var problems: [String] = []
        for (site, depth) in [(SiteKind.social, SessionDepth.light), (.documentation, .deep)] {
            let shape = derive(trace([step(editor, 20, .keys), step(browser, 10, .keys, site: site),
                                      step(editor, 10, .keys)]), siteOn)
            expect(shape.depth == depth, "coding with 10 min on \(site.rawValue) should be \(depth.rawValue), "
                       + "got \(String(describing: shape.depth))", &problems)
        }
        return problems
    }

    private static func siteDecidesLabel() -> [String] {
        var problems: [String] = []
        for (site, label) in [(SiteKind.video, ActivityLabel.mixed), (.documentation, .activity(.research))] {
            let shape = derive(trace([step(browser, 10, .keys, site: site)]), siteOn)
            expect(shape.label == label, "typing on \(site.rawValue) should label \(label), got \(shape.label)",
                   &problems)
        }
        return problems
    }

    private static func overrideBeatsSite() -> [String] {
        var problems: [String] = []
        let overrides = [browser: AppPurpose.coding.rawValue]
        let beats = trace([step(browser, 10, .keys, site: .video)])
        let slices = credit(beats, siteOn, overrides: overrides)
        expectAll(slices, 0, 600, [.engaged], .coding, "a browser the person set to coding, on a video site", &problems)
        // The purpose is the person's, but the site is still what the browser showed.
        expect(slices.allSatisfy { $0.site == .video }, "each slice should still carry the video site", &problems)
        expect(credit(beats, [], overrides: overrides).allSatisfy { $0.site == nil },
               "with the signal off no slice should carry a site", &problems)
        let label = derive(beats, siteOn, overrides: overrides).label
        expect(label == .activity(.coding), "the label should be coding, got \(label)", &problems)
        let social = derive(trace([step(editor, 20, .keys), step(browser, 10, .keys, site: .social),
                                   step(editor, 10, .keys)]), siteOn, overrides: overrides)
        expect(social.depth != .deep, "coding with 10 min of social on a browser set to coding should not be deep, "
                   + "got \(String(describing: social.depth))", &problems)
        return problems
    }

    private static func watchingPauseOnMeeting() -> [String] {
        var problems: [String] = []
        // As the engine writes it: input, watched beats, then the watching pause; only minutes 0..2 count.
        let beats = trace([step(browser, 2, .keys), step(browser, 10, .none, site: .meeting, holder: browser),
                           BeatTrace.Step(app: browser, minutes: 10, input: .none, holder: browser,
                                          presence: .watchPause, site: .meeting)])
        for (signals, purpose) in [(siteOn, AppPurpose.communication), ([], .media)] {
            let phases = derive(beats, signals, countedMinutes: 2).phases
            expect(phases.last.map { !$0.counted && $0.activity == .purpose(purpose) } == true,
                   "signals \(signals.map(\.rawValue)): the watching pause should be \(purpose.rawValue), got "
                       + "\(phases.map { "\($0.activity) counted \($0.counted)" })", &problems)
        }
        return problems
    }

    private static func fingerprintSiteKind() -> [String] {
        var problems: [String] = []
        let mixed = derive(trace([step(browser, 6, .keys, site: .documentation), step(browser, 4, .keys, site: .video)]),
                           siteOn).fingerprint?.siteKind ?? "nil"
        expect(mixed == "documentation", "6 min documentation and 4 min video should name documentation, got \(mixed)",
               &problems)
        let none = derive(trace([step(browser, 10, .keys)]), siteOn).fingerprint?.siteKind ?? "nil"
        expect(none == "none", "no sites should name none, got \(none)", &problems)
        return problems
    }

    private static func signalsCarried() -> [String] {
        var problems: [String] = []
        var beats = trace([step(browser, 10, .keys)])
        expect(SignalKind.carried(by: beats).isEmpty, "beats without a site should carry no signal", &problems)
        beats[3].slices[0].site = .video
        expect(SignalKind.carried(by: beats) == [.siteKind], "one site should carry the site signal, got "
                   + "\(SignalKind.carried(by: beats))", &problems)
        return problems
    }

    private static func unmappedBrowser() -> [String] {
        var problems: [String] = []
        let unlisted = "com.example.UnlistedBrowser"  // confirmed by the person, unknown to PurposeMap
        expectAll(credit(trace([step(unlisted, 10, .keys, site: .documentation)]), siteOn), 0, 600, [.engaged], .research,
                  "typing in an unlisted browser on documentation", &problems)
        expectAll(credit(trace([step(unlisted, 20, .none, site: .meeting, holder: unlisted)]), siteOn), 0, 1_200, [.held],
                  .communication, "a meeting held in an unlisted browser", &problems)
        let label = derive(trace([step(unlisted, 10, .keys, site: .video)]), siteOn).label
        expect(label == .mixed, "typing in an unlisted browser on video should label mixed, got \(label)", &problems)
        return problems
    }

    private static func meetingMajority() -> [String] {
        var problems: [String] = []
        for (meeting, video, purpose) in [(12.0, 8.0, AppPurpose.communication), (10, 10, .media)] {
            let beats = trace([step(browser, meeting, .none, site: .meeting, holder: browser),
                               step(browser, video, .none, site: .video, holder: browser)])
            expectAll(credit(beats, siteOn), 0, (meeting + video) * 60, [.held], purpose,
                      "\(Int(meeting)) min meeting then \(Int(video)) min video held", &problems)
        }
        return problems
    }
}
