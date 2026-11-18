import Foundation

/// Activity-aware sessions: every counted second is credited to what the hands
/// and screen were doing (engaged, held, quiet-kept or passive), and counted
/// time is what the engine counted. Traces are seconds from `SelfTest.base`.
enum ActivityCreditChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Any key makes a slice engaged; three clicks or scrolls do; two do not", engagement),
        ("Input beats a held screen", inputBeatsHeldScreen),
        ("Once quiet passes the grace with a holder, the whole stretch is held, including a stretch with no engaged slice after it",
         wholeStretchHeld),
        ("A held run starts after the last beat read empty", heldRunAfterEmptyBeat),
        ("A browser holding the screen is media; a call app holding it is communication", holderPurposes),
        ("An untouched browser keeps its research for the grace, then is media", browserKeepsResearch),
        ("A browser never touched credits nothing during the grace", untouchedBrowser),
        ("Quiet is measured across apps", quietAcrossApps),
        ("Time outside the session's counted spans earns nothing", outsideCounted),
        ("An agent at work credits the anchor", agentCreditsAnchor),
        ("Counted time leaves out a record's pauses", countedTime),
        ("A second two overlapping beats both cover is credited once", overlapCreditedOnce),
        ("A beat held across the end of the grace holds the stretch", graceAtBeatEnd),
    ]

    private static let editor = "com.microsoft.VSCode"
    private static let browser = "com.google.Chrome"
    private static let callApp = "us.zoom.xos"
    private static let chatApp = "com.anthropic.claudefordesktop"

    private static func at(_ seconds: TimeInterval) -> Date { SelfTest.base.addingTimeInterval(seconds) }
    private static func step(_ app: String, _ minutes: Double, _ input: BeatTrace.Input, holder: String? = nil,
                             presence: BeatPresence? = nil) -> BeatTrace.Step {
        BeatTrace.Step(app: app, minutes: minutes, input: input, holder: holder, presence: presence)
    }
    private static func trace(_ steps: [BeatTrace.Step], from seconds: TimeInterval = 0) -> [Beat] {
        BeatTrace.beats(steps, from: at(seconds))
    }

    /// Credits the beats, counted from the first beat to the last unless told otherwise.
    private static func credit(_ beats: [Beat], counted: [DateInterval]? = nil) -> [CreditedSlice] {
        let whole = [DateInterval(start: beats[0].start, end: beats[beats.count - 1].end)]
        return ActivityCredit.credit(CreditInput(beats: beats, counted: counted ?? whole, signals: [],
                                                 purposeOverrides: [:]))
    }

    private static func total(_ slices: [CreditedSlice]) -> TimeInterval {
        slices.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    private static func summary(_ slices: [CreditedSlice]) -> String {
        slices.map { "\(Int($0.start.timeIntervalSince(SelfTest.base)))+\(Int($0.end.timeIntervalSince($0.start))) "
            + "\($0.state.rawValue) \($0.purpose?.rawValue ?? "nil")" }.joined(separator: ", ")
    }

    /// Every second of [from, to) is credited once, with this state and purpose.
    private static func expectAll(_ slices: [CreditedSlice], _ from: TimeInterval, _ to: TimeInterval,
                                  _ state: CreditState, _ purpose: AppPurpose?, _ what: String,
                                  _ problems: inout [String]) {
        let part = slices.filter { $0.start >= at(from) && $0.end <= at(to) }
        let wrong = part.filter { $0.state != state || $0.purpose != purpose }
        expect(wrong.isEmpty && total(part) == to - from,
               "\(what): \(Int(from))..\(Int(to)) s should be \(state.rawValue) \(purpose?.rawValue ?? "nil") throughout, got \(summary(part))",
               &problems)
    }

    private static func engagement() -> [String] {
        var problems: [String] = []
        let cases: [(keys: Int, clicks: Int, scrolls: Int, engaged: Bool)] = [
            (1, 0, 0, true), (0, 3, 0, true), (0, 0, 3, true), (0, 2, 1, true),
            (0, 2, 0, false), (0, 0, 2, false), (0, 1, 1, false), (0, 0, 0, false),
        ]
        for c in cases {
            let slice = BeatSlice(app: editor, seconds: 30, keys: c.keys, clicks: c.clicks, scrolls: c.scrolls)
            expect(ActivityCredit.isEngaged(slice) == c.engaged,
                   "keys \(c.keys), clicks \(c.clicks), scrolls \(c.scrolls) should be engaged \(c.engaged)", &problems)
        }
        return problems
    }

    private static func inputBeatsHeldScreen() -> [String] {
        var problems: [String] = []
        let beats = trace([step(editor, 5, .keys)]).map { beat -> Beat in
            var held = beat
            held.watchedApps = [browser]
            return held
        }
        expectAll(credit(beats), 0, 300, .engaged, .coding, "keys in the editor while a browser holds", &problems)
        return problems
    }

    private static func wholeStretchHeld() -> [String] {
        var problems: [String] = []
        let watched = trace([step(editor, 0.5, .keys), step(editor, 4, .none, holder: browser)], from: -30)
        expect(watched.first { $0.start == at(30) }?.watchedApps == nil
                && watched.first { $0.start == at(60) }?.watchedApps == [browser],
               "the trace should read holders from base+60", &problems)
        let slices = credit(watched)
        expectAll(slices, -30, 0, .engaged, .coding, "the typing before the quiet", &problems)
        expectAll(slices, 0, 240, .held, .media, "four minutes watched", &problems)

        let gone = trace([step(editor, 0.5, .keys), step(editor, 1.5, .none, holder: browser),
                          step(editor, 2.5, .none)], from: -30)
        expectAll(credit(gone), 0, 240, .quietKept, .coding, "a holder gone inside the grace", &problems)
        return problems
    }

    private static func heldRunAfterEmptyBeat() -> [String] {
        var problems: [String] = []
        let beats = trace([step(editor, 0.5, .keys), step(editor, 5, .none),
                           step(editor, 5, .none, holder: browser)], from: -30)
        let slices = credit(beats)
        expectAll(slices, 0, 300, .quietKept, .coding, "quiet while holders read empty", &problems)
        expectAll(slices, 300, 600, .held, .media, "the browser holding after the empty beats", &problems)
        return problems
    }

    private static func holderPurposes() -> [String] {
        var problems: [String] = []
        let film = trace([step(browser, 10, .none, holder: browser)])
        expectAll(credit(film), 0, 600, .held, .media, "a browser holding the screen", &problems)
        let call = trace([step(callApp, 10, .none, holder: callApp)])
        expectAll(credit(call), 0, 600, .held, .communication, "a call app holding the screen", &problems)
        return problems
    }

    private static func browserKeepsResearch() -> [String] {
        var problems: [String] = []
        let slices = credit(trace([step(browser, 0.5, .keys), step(browser, 5, .none)], from: -30))
        expectAll(slices, 0, 120, .passive, .research, "an untouched browser inside the grace", &problems)
        expectAll(slices, 120, 300, .passive, .media, "an untouched browser after the grace", &problems)
        return problems
    }

    private static func untouchedBrowser() -> [String] {
        var problems: [String] = []
        let slices = credit(trace([step(browser, 5, .none)]))
        expectAll(slices, 0, 120, .passive, nil, "a browser never touched, inside the grace", &problems)
        expectAll(slices, 120, 300, .passive, .media, "a browser never touched, after the grace", &problems)
        return problems
    }

    private static func quietAcrossApps() -> [String] {
        var problems: [String] = []
        // Cells from base-20: keys end at base, the switch is at base+100, a cell opens at base+130.
        let slices = credit(trace([step(editor, 20.0 / 60, .keys), step(editor, 100.0 / 60, .none),
                                   step(browser, 3, .none)], from: -20))
        let first = slices.first { $0.app == browser && $0.start == at(100) }
        let later = slices.first { $0.app == browser && $0.start == at(130) }
        expect(first?.state == .passive && first?.purpose == nil,
               "the browser's first slice is inside the grace, got \(summary(first.map { [$0] } ?? []))", &problems)
        expect(later?.state == .passive && later?.purpose == .media,
               "the browser's slice at base+130 is past the grace, got \(summary(later.map { [$0] } ?? []))", &problems)
        expectAll(slices, 0, 100, .quietKept, .coding, "the quiet editor before the switch", &problems)
        return problems
    }

    private static func outsideCounted() -> [String] {
        var problems: [String] = []
        let beats = trace([step(editor, 1, .keys), step(editor, 4, .none)])
        for end in [60.0, 45.0] {
            let slices = credit(beats, counted: [DateInterval(start: at(0), end: at(end))])
            expect(slices.allSatisfy { $0.end <= at(end) } && total(slices) == end,
                   "counted ending at base+\(Int(end)) credits \(Int(end)) s and nothing after, got \(summary(slices))",
                   &problems)
        }
        return problems
    }

    private static func agentCreditsAnchor() -> [String] {
        var problems: [String] = []
        let slices = credit(trace([step(editor, 1, .keys), step(chatApp, 4, .none, presence: .agent)]))
        expectAll(slices, 60, 300, .quietKept, .coding, "an agent at work with a chat app in front", &problems)
        return problems
    }

    private static func countedTime() -> [String] {
        var problems: [String] = []
        let bounds = DateInterval(start: at(0), end: at(3_600))
        let recorded = CountedTime.spans(records: [(bounds, [DateInterval(start: at(1_200), end: at(2_100))])],
                                         beats: [])
        let expected = [DateInterval(start: at(0), end: at(1_200)), DateInterval(start: at(2_100), end: at(3_600))]
        expect(recorded == expected, "recorded pauses leave out 20 to 35 min, got \(recorded)", &problems)

        let beats = trace([step(editor, 20.5, .keys), step(editor, 9.5, .none),
                           step(editor, 5, .none, presence: .paused), step(editor, 25, .keys)])
        let backdated = CountedTime.spans(records: [(bounds, nil)], beats: beats)
        let fromBeats = [DateInterval(start: at(0), end: at(1_230)), DateInterval(start: at(2_100), end: at(3_600))]
        expect(backdated == fromBeats,
               "an idle pause read from beats is backdated to the last engaged slice, got \(backdated)", &problems)

        // As the engine's `enterPause`: with no input before it, a pause reaches back to the session's start.
        let untouched = trace([step(editor, 5, .none), step(editor, 5, .none, presence: .paused),
                               step(editor, 5, .keys)])
        let short = DateInterval(start: at(0), end: at(900))
        let fromStart = CountedTime.spans(records: [(short, nil)], beats: untouched)
        expect(fromStart == [DateInterval(start: at(600), end: at(900))],
               "a pause with no input before it is backdated to the record's start, got \(fromStart)", &problems)
        return problems
    }

    private static func overlapCreditedOnce() -> [String] {
        var problems: [String] = []
        // A clock stepped back: the second beat shares the first's cell and overlaps it by 20 s.
        let typing = BeatSlice(app: editor, seconds: 30, keys: 5, clicks: 0, scrolls: 0)
        let beats = [Beat(start: at(0), slices: [typing], presence: .input),
                     Beat(start: at(0), offset: 10, slices: [typing], presence: .input)]
        let slices = credit(beats, counted: [DateInterval(start: at(0), end: at(40))])
        expect(total(slices) == 40, "40 s covered should credit 40 s, got \(summary(slices))", &problems)
        return problems
    }

    private static func graceAtBeatEnd() -> [String] {
        var problems: [String] = []
        // Quiet from minute 1 to 3.5, holders read from minute 2. The last quiet beat opens
        // exactly at the grace (120 s) and ends past it: measured at its end, it holds.
        let beats = trace([step(editor, 1, .keys), step(editor, 2.5, .none, holder: browser), step(editor, 1, .keys)])
        expectAll(credit(beats), 60, 210, .held, .media, "two and a half minutes watched", &problems)
        return problems
    }
}
