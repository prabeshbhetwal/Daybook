import Foundation

/// Verification only: builds beats from minute-level steps.
///
/// Steps are cut at 30-second cells counted from `start`, so a step that ends
/// mid-cell shares that beat with the next step's slice. Slices from different
/// steps are never merged, even for the same app, so each keeps its own input.
/// Holders are read as the sampler reads them, only after a minute of quiet:
/// before that a quiet beat's `watchedApps` is nil, after it the holders its
/// steps name, or [] when they name none. An engaged beat reads nil.
enum BeatTrace {
    struct Step { let app: String; let minutes: Double; let input: Input; var holder: String? = nil
                  var presence: BeatPresence? = nil; var site: SiteKind? = nil }
    enum Input { case keys, clicks(Int), scrolls(Int), none, oneKeyEvery(minutes: Double) }

    /// How long quiet lasts before the sampler reads holders.
    private static let holdersReadAfter: TimeInterval = 60

    static func beats(_ steps: [Step], from start: Date) -> [Beat] {
        let cell = Int(ActivityConstants.beatLength)
        var beats: [Beat] = []
        var cellSteps: [[(seconds: Int, step: Step)]] = []
        var stepStart = 0
        for step in steps {
            let stepEnd = stepStart + Int((step.minutes * 60).rounded())
            var at = stepStart
            while at < stepEnd {
                let cellStart = start.addingTimeInterval(TimeInterval(at / cell * cell))
                let end = min(at / cell * cell + cell, stepEnd)
                let slice = slice(step, from: at - stepStart, to: end - stepStart)
                if beats.last?.start == cellStart {
                    beats[beats.count - 1].slices.append(slice)
                    cellSteps[cellSteps.count - 1].append((end - at, step))
                } else {
                    beats.append(Beat(start: cellStart, slices: [slice], presence: .quiet))
                    cellSteps.append([(end - at, step)])
                }
                at = end
            }
            stepStart = stepEnd
        }

        var quietSince = start
        for index in beats.indices {
            var at = beats[index].start
            var engaged = false
            for slice in beats[index].slices {
                at = at.addingTimeInterval(TimeInterval(slice.seconds))
                if ActivityCredit.isEngaged(slice) { engaged = true; quietSince = at }
            }
            let parts = cellSteps[index]
            if !engaged && beats[index].start.timeIntervalSince(quietSince) >= holdersReadAfter {
                beats[index].watchedApps = Set(parts.compactMap(\.step.holder)).sorted()
            }
            let held = !(beats[index].watchedApps ?? []).isEmpty
            let longest = parts.max { $0.seconds < $1.seconds }?.step
            beats[index].presence = longest?.presence ?? (engaged ? .input : held ? .watched : .quiet)
        }
        return beats
    }

    /// The step's input over its seconds [from, to).
    private static func slice(_ step: Step, from: Int, to: Int) -> BeatSlice {
        var keys = 0, clicks = 0, scrolls = 0
        switch step.input {
        case .keys: keys = 10
        case .clicks(let count): clicks = count
        case .scrolls(let count): scrolls = count
        case .none: break
        case .oneKeyEvery(let minutes):
            // One key at the step's start and every period after it.
            let period = max(1, Int((minutes * 60).rounded()))
            keys = (to - 1) / period - (from + period - 1) / period + 1
        }
        return BeatSlice(app: step.app, seconds: to - from, keys: keys, clicks: clicks, scrolls: scrolls,
                         site: step.site)
    }
}

/// What a sweep row expects of a derived shape; nil fields are not asserted.
struct SweepExpectation {
    let label: ActivityLabel
    var depth: SessionDepth? = nil              // nil: not asserted
    var phases: [PhaseActivity]? = nil          // in order; nil: not asserted
    var counted: [Bool]? = nil                  // per phase; nil: not asserted
    var splitCandidates: Int? = nil
    var creditedSeconds: TimeInterval? = nil    // total, within 30 s
    var purposeSeconds: [AppPurpose: TimeInterval]? = nil   // each within 30 s
}

/// The sweep: one finished session per row, minutes from `SelfTest.base`, every
/// second counted unless the row says otherwise, `countsWhileWatching` false.
///
/// Phase cells at the edges, as they stand (recorded, not asserted by the rows):
/// - "Untouched editor, no media" is one phase, away over 0 to 30.5: its first cell
///   is counted for only 30 of 60 seconds, so no cell is mostly counted.
/// - "Passive browser after coding" has its media phase start at minute 32, the end
///   of the grace (the two cells credited to nothing take coding before them), while
///   its split candidate is at minute 30, where the passive time began.
/// - An agent at work during a watching pause with no holder read is away: the cells
///   are uncounted and no holder gives them a purpose.
enum ActivityTraces {
    static let editor = "com.microsoft.VSCode"
    static let terminal = "com.apple.Terminal"
    static let browser = "com.google.Chrome"
    static let designApp = "com.figma.Desktop"
    static let messaging = "com.tinyspeck.slackmacgap"
    static let callApp = "us.zoom.xos"
    static let mediaPlayer = "com.apple.TV"
    /// Not in the purpose map: utility, with `declaredCategory` nil in checks.
    static let viewer = "com.apple.Preview"

    static func step(_ app: String, _ minutes: Double, _ input: BeatTrace.Input, holder: String? = nil,
                     presence: BeatPresence? = nil) -> BeatTrace.Step {
        BeatTrace.Step(app: app, minutes: minutes, input: input, holder: holder, presence: presence)
    }

    /// A finished session over the steps. `counted` is in minutes; nil counts every second.
    /// `edit` changes each beat after the trace builds it, for evidence the builder does not write.
    static func session(_ steps: [BeatTrace.Step], counted: [(Double, Double)]? = nil,
                        countsWhileWatching: Bool = false, edit: ((inout Beat) -> Void)? = nil) -> DerivationInput {
        let base = SelfTest.base
        var beats = BeatTrace.beats(steps, from: base)
        if let edit { for index in beats.indices { edit(&beats[index]) } }
        let bounds = DateInterval(start: base, end: beats.last?.end ?? base)
        let spans = counted.map { $0.map { DateInterval(start: base.addingTimeInterval($0.0 * 60),
                                                         end: base.addingTimeInterval($0.1 * 60)) } } ?? [bounds]
        return DerivationInput(credit: CreditInput(beats: beats, counted: spans, signals: [], purposeOverrides: [:]),
                               bounds: bounds, countsWhileWatching: countsWhileWatching, isRunning: false,
                               now: bounds.end)
    }

    static let all: [(name: String, input: DerivationInput, expect: SweepExpectation)] = [
        ("a. Video, hands off",
         session([step(browser, 0.5, .keys), step(browser, 9.5, .none, holder: browser)]),
         // A split (the typed half-minute departs for watching) leaves depth out, so it is not asserted.
         SweepExpectation(label: .activity(.media), purposeSeconds: [.media: 570, .research: 30])),
        // The browser holds every beat, typed ones included, so only rule 1 keeps this coding.
        ("b. Coding with a tutorial playing",
         session([step(editor, 30, .keys)], edit: { $0.watchedApps = [browser] }),
         SweepExpectation(label: .activity(.coding), depth: .deep, phases: [.purpose(.coding)])),
        ("c. Editor untouched while video plays",
         session([step(editor, 5, .keys), step(editor, 8, .none, holder: browser)]),
         // Its split leaves depth out, so it is not asserted.
         SweepExpectation(label: .activity(.media), phases: [.purpose(.coding), .purpose(.media)],
                          purposeSeconds: [.coding: 300, .media: 480])),
        ("d. Code, browse, code",
         session([step(editor, 40, .keys), step(browser, 10, .keys), step(editor, 30, .keys)]),
         SweepExpectation(label: .activity(.coding), depth: .deep,
                          phases: [.purpose(.coding), .purpose(.research), .purpose(.coding)], splitCandidates: 0)),
        ("e. A film inside a session",
         session([step(editor, 20, .keys),
                  step(mediaPlayer, 60, .none, holder: mediaPlayer, presence: .watchPause)], counted: [(0, 20)]),
         SweepExpectation(label: .activity(.coding), phases: [.purpose(.coding), .purpose(.media)],
                          counted: [true, false], splitCandidates: 1)),
        ("f. Left and not back",
         session([step(editor, 30, .keys), step(messaging, 25, .keys)]),
         // Its split leaves depth out (nil is not asserted here; the fix-round checks assert it).
         SweepExpectation(label: .activity(.coding),
                          phases: [.purpose(.coding), .purpose(.communication)], splitCandidates: 1)),
        ("Reading-heavy",
         session([step(browser, 30, .scrolls(4))]),
         SweepExpectation(label: .activity(.research), depth: .deep)),
        ("Click-heavy design",
         session([step(designApp, 30, .clicks(5))]),
         SweepExpectation(label: .activity(.design), depth: .deep)),
        ("Code review",
         session([step(editor, 30, .oneKeyEvery(minutes: 3))]),
         SweepExpectation(label: .activity(.coding), depth: .deep)),
        ("Pause to watch a tutorial",
         session([step(editor, 25, .keys), step(browser, 6, .none, holder: browser), step(editor, 25, .keys)]),
         SweepExpectation(label: .activity(.coding), depth: .deep,
                          phases: [.purpose(.coding), .purpose(.media), .purpose(.coding)], splitCandidates: 0,
                          purposeSeconds: [.coding: 3_000, .media: 360])),
        ("Browser meeting",
         session([step(browser, 30, .none, holder: browser)]),
         SweepExpectation(label: .activity(.media), purposeSeconds: [.media: 1_800])),
        ("Call app",
         session([step(callApp, 30, .none, holder: callApp)]),
         SweepExpectation(label: .activity(.communication), depth: .passive, purposeSeconds: [.communication: 1_800])),
        ("Lunch",
         session([step(editor, 30, .keys), step(editor, 60, .none, presence: .paused), step(editor, 20, .keys)],
                 counted: [(0, 30), (90, 110)]),
         SweepExpectation(label: .activity(.coding), phases: [.purpose(.coding), .away, .purpose(.coding)],
                          splitCandidates: 0)),
        ("Long pause, no departure",
         session([step(editor, 20, .keys), step(editor, 9, .none), step(editor, 20, .keys)]),
         SweepExpectation(label: .activity(.coding), depth: .deep, phases: [.purpose(.coding)])),
        ("Single-app run",
         session([step(terminal, 30, .keys)]),
         SweepExpectation(label: .activity(.coding), depth: .deep)),
        ("Passive browser after coding",
         session([step(editor, 30, .keys), step(browser, 10, .none)]),
         SweepExpectation(label: .activity(.coding), phases: [.purpose(.coding), .purpose(.media)], splitCandidates: 1)),
        // As the engine writes it: watched beats until the idle threshold, then the watching
        // pause, backdated to the last input, so nothing after minute 2 is counted.
        ("Video opened, walked away",
         session([step(browser, 2, .keys), step(browser, 10, .none, holder: browser),
                  step(browser, 10, .none, holder: browser, presence: .watchPause)], counted: [(0, 2)]),
         SweepExpectation(label: .activity(.research), phases: [.purpose(.research), .purpose(.media)],
                          counted: [true, false], creditedSeconds: 120)),
        ("Quiet on a non-member app",
         session([step(editor, 20, .keys), step(viewer, 0.5, .clicks(1)), step(viewer, 8, .none),
                  step(editor, 20, .keys)]),
         SweepExpectation(label: .activity(.coding), depth: .light, splitCandidates: 0)),
        ("Untouched editor, no media",
         session([step(editor, 0.5, .keys), step(editor, 30, .none)], counted: [(0, 0.5)]),
         SweepExpectation(label: .unsorted)),
        ("A four-minute watch is a phase",
         session([step(editor, 20, .keys), step(browser, 4, .none, holder: browser), step(editor, 20, .keys)]),
         SweepExpectation(label: .activity(.coding), depth: .deep,
                          phases: [.purpose(.coding), .purpose(.media), .purpose(.coding)], splitCandidates: 0,
                          purposeSeconds: [.media: 240])),
    ]
}
