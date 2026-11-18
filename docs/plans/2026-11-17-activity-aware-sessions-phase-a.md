# Activity-Aware Sessions, Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record what the hands and screen were doing in 30-second beats, credit every counted second from that evidence, and show each session's phases and depth in its row, without changing what any session counts or is called.

**Architecture:** One new Core recorder turns the existing 1 Hz ticker's presence reading and per-app input counter deltas into beats, written one JSON line each to a per-day journal. Pure Core functions credit beats, derive the working set, phases, depth and label, and produce one `SessionActivityShape`; that value is both the snapshot stored on the session's existing metadata sidecar and the read model the session row draws as a phase strip. Nothing re-decides presence: beats copy `QuietSampler`'s reading, and whether a second counted comes from the session's own counted spans.

**Tech Stack:** Swift 5 mode, SwiftUI and AppKit, macOS 14, one module built by `build.sh`. No new dependency.

**Spec:** `docs/specs/2026-11-17-activity-aware-sessions-design.md` (amended 17 November 2026; uncommitted, in the `fable-production-audit-69c872` worktree until it lands). Phase A only: beats, credit states, phases, depth, the phase strip, sweep checks, the cost gate, and the spec's spikes 1 and 2 (screen-held: Task 2; cost: Task 13).

**Amended 17 November 2026:** owner's ruling, for privacy: Daybook reads no audio in Phase A. The microphone and audio-out signals (`micApps`, `audioOut`) are removed entirely, with their probe (Task 1), `BeatFlags`, `AudioActivity`, `callMicShare` and the weak-signal counterfactual in Phase A. A browser holding the screen is always media; a call app stays communication through its own purpose. Task numbers are unchanged.

## Global Constraints

- `./build.sh --check` passes before each commit, sandbox disabled. The final gate also runs `TZ=Europe/Berlin` and `TZ=Pacific/Kiritimati`.
- Core is UI-free and compiles alone: beats, credit, working set, phases, depth, label, fingerprint and the signal gate are Core. Power assertions and input counters are read in App and handed to Core as plain values.
- No new timer. Beat edges ride `SessionStore.runTick()`; counters are read only at a beat edge or an app activation.
- Views never recalculate time: phases and depth reach the row only through `StorySessionDetail.phases`.
- Nothing in this phase changes what counts, a session's name or category, `InputDensity`, automatic mode or any engine transition. The only change to `Sources/Core/SessionEngine*` is Task 9's one read-only accessor.
- Every value below is a named constant in `ActivityConstants` (Task 3): beat 30 s, flick fold 5 s, `engagedClickScrollPerBeat` 3, `watchGrace` 120 s, `minCreditedSeconds` 60 s, `minPhase` 180 s, `returnWindow` 900 s, `deepMinRun` 1 500 s, `deepInsideShare` 0.70, `deepOutsideShare` 0.15, `beatRetention` 90 days. Any change to a rule or a constant bumps `ActivityConstants.algorithmVersion` (starts at 1). Constants for phases B to D arrive with those phases.
- A signal claims nothing unless `SignalGate.passing` lists the running macOS major for it, and a line is added there only in the same commit as its passing probe report under `docs/debug/`.
- Checks use `TestClock`, `SelfTest.scratchDirectory()` and `MemoryDefaults`; trace times are offsets from `SelfTest.base`, never a fixed epoch; nothing reads `Date()` in logic under test.
- Source files stay at or under 300 lines. `SessionStore.swift` (498), `SessionStore+StoryDetails.swift` (299), `SessionMetadataArchive.swift` (305) and `Surfaces/Today/DayStory.swift` (1 072) take no net growth: new code goes in new files, and a task that adds a line to one moves at least as much out.
- Lengths in App, Design and Surfaces are tokens or `N.zoomed`; a fixed one carries `// zoom: fixed`.
- New stored members of `SessionStore` are added to its `keep_internals` list in `build.sh`.
- The repository is public: no personal data, app lists from the owner's Mac or real timings in fixtures or probe reports.
- Commit subjects are one plain present-tense sentence for any user of the app. Commits stay on the branch; no push, no pull request, no release until the owner asks.

## Review Focus

1. A beat cut by sleep, lock or a stalled ticker: the open beat closes at the last tick and no slice spans the gap, so a night never becomes one long slice (Task 4 check 6).
2. Synthetic input while nobody is there (an agent posting keys, a remote session): a slice whose interval saw no real input by the system idle clock carries zero counts, so it is not engaged (Task 4 check 4).
3. The engine backdates an idle or watching pause after beats were already written as quiet: credit follows the session's counted spans, never the beat's presence, so the backdated stretch earns nothing (Task 6 sweeps "Video opened, walked away" and "Untouched editor").
4. A session across midnight, a daylight-saving change or a zone change: its beats come from every local-day file it touches, none twice, none missed (Task 3 check 5).
5. Saving or clearing a note on a session that has a snapshot: the snapshot survives, and an entry holding only a snapshot is not dropped from the sidecar (Task 10 check 2).

## Who runs what

| Work | Runner | Why |
|---|---|---|
| Task 0, every build, check and probe run | `haiku-runner` (Haiku 5.5) | Mechanical; reports exit code and failing lines only |
| Task 2 (spike) | main session with the owner at the Mac | The owner plays the media; nothing here can be inferred |
| Tasks 3, 4, 8, 12 | `sonnet-worker` (Sonnet 5.5, effort xhigh on 4) | Bounded, stated interface |
| Tasks 5, 6 and 7 | one general-purpose agent on Opus 5.5, effort high | The credit rules, the sweep traces and the derivation must agree; one mind holds them |
| Tasks 9 and 10 | `sonnet-worker` (effort xhigh) | Wiring into the ticker and the sidecar; exact files named |
| Task 11 | general-purpose agent on Opus 5.5, then the design review | A new strip, VoiceOver, colour contrast |
| Tasks 13 and 14 | main session | The live cost run needs the owner's go-ahead |
| Review of Tasks 4, 7, 9, 10 | `fix-reviewer` agent | Repo rule: time arithmetic, persistence, session state |
| Review of the whole branch | `code-reviewer` panel plus Claude | Multi-file change finished |

Stages, each merged and fully checked before the next starts:

| Stage | Tasks | Together? | Why it is safe |
|---|---|---|---|
| 0 | 0, 2 | parallel | 0 touches only Verification; 2 writes a probe folder in `$TMPDIR` and a report in `docs/debug/` |
| 1 | 3 | alone | Every later task reads its types |
| 2 | 4, 5, 12 | parallel worktrees | 4 owns `BeatRecorder.swift`, 5 owns `ActivityCredit.swift`, 12 (landed; see Task 12 for what stays) owns `OwningApp.swift`, `ProcessLookup.swift` and (only if Task 2 says so) `WatchDetector.swift`; all read only Task 3 |
| 3 | 6, 7 | one agent, one commit | The sweep checks are written red, then 7 turns them green; the repo commits only on a passing suite |
| 4 | 8, 9 | parallel worktrees | 8 is Core only; 9 owns the App wiring files |
| 5 | 10 | alone | Reads 7, 8 and 9 |
| 6 | 11 | alone | Owns Surfaces |
| 7 | 13, 14 | in order | Measures and verifies the finished branch |

Verification sequence, one for every task: a worker in a parallel worktree runs the compile-only typecheck and a Core probe (`CLAUDE.md`, Runtime probes) wherever a step says "Run `./build.sh --check`", and commits in its worktree; after the stage's merge, `haiku-runner` runs the full `./build.sh --check` once, and a red result goes back to the task that owns the failing check. A task that runs alone (stages 1, 3, 5, 6, 7) runs `./build.sh --check` itself. Stage 0's probe report is written by the main session into the branch's own working tree, and Task 2 commits it there.

---

### Task 0: Empty suites, registered

**Files:**
- Create, in `Sources/Verification/`: `BeatArchiveChecks.swift`, `BeatRecorderChecks.swift`, `ActivityCreditChecks.swift`, `ActivitySweepChecks.swift`, `ActivityDerivationChecks.swift`, `ActivityEvidenceStoreChecks.swift`, `SessionPhaseStripChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (end of `registeredTests`)

- [ ] **Step 1:** Create each as `enum <Name>: CheckSuite { static let tests: [(String, () -> [String])] = [] }` with a one-line doc comment.
- [ ] **Step 2:** Append the seven `+ <Name>.tests` lines, in the order above, at the end of `registeredTests`.
- [ ] **Step 3:** Run `./build.sh --check`. Expected: the same pass count as before, exit 0.
- [ ] **Step 4:** Commit: "Daybook's checks have room for activity-aware sessions".

### Task 1: Removed

Removed by the owner's ruling of 17 November 2026: Daybook reads no audio.

### Task 2: Spike, screen-held probe

**Files:**
- Create: `docs/debug/2026-11-<dd>-screen-held-probe.md`

- [ ] **Step 1:** In its own `P="$(mktemp -d "$TMPDIR/fc-probe.XXXXXX")"`, write a probe that each 2 s calls `IOPMCopyAssertionsByProcess` and, for every assertion of type `NoDisplaySleepAssertion` or `PreventUserIdleDisplaySleep`, prints the pid, `AssertName`, `NSRunningApplication(processIdentifier:)`'s `bundleIdentifier` and `activationPolicy`, and the parent pid from `proc_pidinfo(pid, PROC_PIDTBSDINFO, …)` with the parent's bundle identifier and policy.
- [ ] **Step 2:** The owner plays a video, pauses it, plays music only, and moves the video to a background tab, in Safari, Chrome, Firefox and Arc; then in one call app during a call and one media player playing a film. Record each row.
- [ ] **Step 3:** Write the report: for each app and state, which process held the assertion and whether `WatchDetector.read()` as written calls it watched (a `.regular` holder) or kept awake (anything else). Verdict: "helper resolution needed" if any browser's playing video is held by a non-`.regular` process whose parent chain reaches the browser; otherwise "none needed".
- [ ] **Step 4:** Remove `$P`. Commit the report alone: "A probe report records which apps Daybook sees holding the screen". Its verdict decides whether Task 12 stays: `OwningApp`, `ProcessLookup` and the `WatchDetector` step are kept only if it says "helper resolution needed", and otherwise are removed in one commit.

### Task 3: Constants, signal gate, beats and their archive (Core)

**Files:**
- Create: `Sources/Core/ActivityConstants.swift`, `Sources/Core/SignalGate.swift`, `Sources/Core/Beat.swift`, `Sources/Core/BeatArchive.swift`
- Test: `Sources/Verification/BeatArchiveChecks.swift`

**Interfaces:**
- Consumes: `JournalFile` (`append`, `read`, `replay`), `SessionArchive.defaultDirectory`.
- Produces:

```swift
enum ActivityConstants {
    static let algorithmVersion = 1
    static let beatLength: TimeInterval = 30
    static let flickFold: TimeInterval = 5
    static let engagedClickScrollPerBeat = 3
    static let watchGrace: TimeInterval = 120
    static let minCreditedSeconds: TimeInterval = 60
    static let minPhase: TimeInterval = 180
    static let returnWindow: TimeInterval = 900
    static let deepMinRun: TimeInterval = 1_500
    static let deepInsideShare = 0.70
    static let deepOutsideShare = 0.15
    static let defaultBeatRetentionDays = 90
    /// Every rule-bearing value above, joined with "|"; a check pins it to `algorithmVersion`.
    static var signature: String { get }
}

/// Phase D's site kind is the only signal; Phase A reads none.
enum SignalKind: String, Codable, CaseIterable { case siteKind }
enum SignalGate {
    /// Signal to the macOS majors a committed probe report passed on. Empty until one does.
    static let passing: [SignalKind: Set<Int>] = [:]
    static func isOn(_ signal: SignalKind, macOSMajor: Int) -> Bool
}

/// What the existing sampler read for most of a beat's seconds. Recorded, never decided here.
enum BeatPresence: String, Codable { case input, quiet, watched, agent, watchPause, paused }

struct BeatSlice: Codable, Equatable {
    let app: String          // bundle identifier; "" when none was in front
    var seconds: Int
    var keys: Int
    var clicks: Int
    var scrolls: Int
    // CodingKeys: a, d, k, c, w
}

struct Beat: Codable, Equatable {
    static let schemaVersion = 1
    let version: Int                // "v"
    let start: Date                 // "t": whole seconds since the reference date, a multiple of 30
    var offset: Int                 // "f": seconds into the cell where recording began; omitted when 0
    var slices: [BeatSlice]         // "s": in the order they were in front, from start + offset
    var presence: BeatPresence      // "p"
    var watchedApps: [String]?      // "h": sorted; nil when the sampler did not read holders in this beat
    var end: Date { get }           // start + offset + the slices' seconds (a partial beat ends early)
    /// floor(timeIntervalSinceReferenceDate / 30) * 30; no calendar involved.
    static func gridStart(for date: Date) -> Date
}

final class BeatArchive {
    init(directory: URL = SessionArchive.defaultDirectory.appendingPathComponent("beats"),
         calendar: Calendar = .current)
    private(set) var revision: Int
    func append(_ beat: Beat) throws
    /// Sorted by start, each beat once. Reads the local-day files from two days before the
    /// interval's start to two days after its end (zone offsets differ by up to 26 hours) and filters by time, so a beat filed under
    /// another zone's day after the Mac changed zone is still found.
    func beats(in interval: DateInterval) -> [Beat]
    /// Removes day files whose day is more than `days` days before `now`'s; returns how many.
    @discardableResult func prune(olderThan days: Int, now: Date) -> Int
}
```

On disk: one file per local calendar day of the beat's start, `beats/YYYY-MM-DD.jsonl`, one beat per line through `JournalFile.append`. A day file is read once and cached; `append` updates the cache and bumps `revision`. A line from a newer schema is passed over by `replay`, as `JournalFile` already does. Beats are not added to `BackupScheduler`'s files: they expire, and the snapshot (Task 10) is what is kept.

- [ ] **Step 1: Write the failing checks** in `BeatArchiveChecks`:
  1. "Beats sit on a 30-second grid in every zone": `gridStart(for: base + 29) == gridStart(for: base)`, its `timeIntervalSinceReferenceDate` is a multiple of 30, and `base` built from calendars in `Europe/Berlin` and `Pacific/Kiritimati` gives grid starts that are also multiples of 30.
  2. "A beat reads back exactly as written": append three beats; a fresh `BeatArchive` on the same scratch directory returns them equal and in order; a beat with nil `watchedApps` writes no `"h"` key, and `watchedApps` nil and `[]` read back distinct.
  3. "A torn last line loses only that beat": two beats, then half a line appended by hand; reload gives two beats.
  4. "A beat line from a newer build is passed over": a line with `"v":2` and an unknown key between two good lines; both good beats return.
  5. "A session across midnight reads both days once": with a `Europe/Berlin` calendar, beats at 23:59:30 and 00:00:00 on the night of the October change; `beats(in:)` over 23:50 to 00:10 returns both, once each.
  6. "Old evidence is removed after the retention period": day files 91, 90 and 1 days before `now`; `prune(olderThan: 90, now:)` returns 1 and leaves the other two.
  7. "Signals are off until a probe passes": `SignalGate.isOn(s, macOSMajor: m)` is false for every `SignalKind` (only `.siteKind`) and every m in 14...30.
  8. "The algorithm version moves with its constants": `ActivityConstants.signature` equals the literal written beside `algorithmVersion == 1` in the check (a literal without `callMicShare`, which the ruling of 17 November 2026 removed); its message says to change a constant, the version and this literal together.
  9. "A beat filed under another zone's day is still found": a beat written with a `Pacific/Kiritimati` calendar at its 00:10 is read by an archive using a `America/Los_Angeles` calendar over an interval around it.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these nine fail.
- [ ] **Step 3:** Implement the four files to the interfaces above.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass, exit 0.
- [ ] **Step 5:** Commit: "Daybook can keep a compact record of what each half-minute held".

### Task 4: The beat recorder (Core)

**Files:**
- Create: `Sources/Core/BeatRecorder.swift`
- Test: `Sources/Verification/BeatRecorderChecks.swift`

**Interfaces:**
- Consumes: `Beat`, `BeatSlice`, `BeatPresence`, `ActivityConstants`.
- Produces:

```swift
struct CounterReading: Equatable { let keys: UInt32; let clicks: UInt32; let scrolls: UInt32 }

struct BeatRecorder {
    /// The front app changed. Closes the open slice at `at`.
    mutating func activate(app: String?, at: Date, counters: CounterReading, idleSeconds: TimeInterval)
    /// One ticker second. Returns the beat that closed, if a grid edge or a gap was crossed.
    /// `counters` and `idleSeconds` are called only when a beat closes.
    mutating func tick(at: Date, presence: BeatPresence, watchedApps: Set<String>?,
                       counters: () -> CounterReading, idleSeconds: () -> TimeInterval) -> Beat?
    /// Recording stops. Returns the partial beat, if any, with the presence and holders seen so far.
    mutating func stop(at: Date, counters: CounterReading, idleSeconds: TimeInterval) -> Beat?
}
```

Rules the checks pin:
- A slice's counts are wrapping deltas (`&-`) of the readings at its open and close. When `idleSeconds` at close is at least the slice's duration, no real input arrived in it and its counts are zero: the `InputDensity` guard, per slice.
- At close, a slice shorter than `flickFold` folds into the slice before it in the same beat (after it, if first; a beat's only slice is kept), adding its seconds and counts; then adjacent slices of the same app merge.
- The first tick with no open slice opens one at that second, reading `counters()` once as its baseline; the beat's `offset` is that second's distance from its grid start. Each closed beat's closing reading is the next slice's baseline.
- `presence` is the value with the most ticker seconds in the beat; ties go to the first of `paused, watchPause, agent, watched, quiet, input`. `watchedApps` is the last non-empty set seen in the beat; else `[]` if the holders were read at all in the beat; else nil (the sampler reads holders only after a minute of quiet).
- A tick more than 2 s after the previous one closes the open beat at the previous tick's time and opens a fresh one; no slice spans the gap.

- [ ] **Step 1: Write the failing checks** in `BeatRecorderChecks`, driving a `TestClock` that starts at `Beat.gridStart(for: SelfTest.base)` (so the first tick sits on a grid edge) unless a check says otherwise, with injected counter closures:
  1. "A beat closes on the grid edge with each app's seconds": 20 ticks in app A, an activation, 10 ticks in B; slices A 20 s and B 10 s.
  2. "Input lands in the slice that received it": keys advance 12 during A and 0 during B; A has 12 keys, B 0.
  3. "A flick under five seconds folds into its neighbour": A 12 s, B 3 s with 1 click, A 15 s gives one slice A 30 s with 1 click.
  4. "Counts with no real input behind them are discarded": keys advance 40 during a 30-second slice while `idleSeconds` is 31 at close; the slice has 0 keys.
  5. "Presence is the sampler's reading for most of the beat": 18 `.quiet` and 12 `.watched` ticks give `.quiet`; 15 and 15 give `.watched`.
  6. "Sleep never becomes one long slice": ticks stop at base+10 and resume at base+3 610; the closed beat's `end` is base+10, and the next beat has `start == gridStart(for: base + 3 610)` with the matching `offset`.
  7. "Counters are read only when a beat closes or the app changes": over 90 ticks in one app, starting on a grid edge, the counter closure is called exactly 4 times (one baseline, three closes).
  8. "Recording that starts mid-cell keeps its true times": the first tick at grid start + 17 gives a beat with `offset == 17` and slices totalling 13 s; `end == start + 30`.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement `BeatRecorder` to the interface and rules above.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass.
- [ ] **Step 5:** Run the `fix-reviewer` agent on the diff (time arithmetic). Address its findings.
- [ ] **Step 6:** Commit: "Each half-minute keeps the input every app in front received".

### Task 5: Credit states (Core)

**Files:**
- Create: `Sources/Core/ActivityCredit.swift`
- Test: `Sources/Verification/ActivityCreditChecks.swift`, `Sources/Verification/ActivityTraces.swift` (the `BeatTrace` builder, shared with Task 6)

**Interfaces:**
- Consumes: `Beat`, `ActivityConstants`, `SignalKind`, and from the existing `Sources/Core/AppPurpose.swift` (unchanged): `PurposeMap.purpose(for:activity:overrides:)`, `PurposeMap.rules`, `PurposeMap.isAmbiguous`, `AppPurpose` (whose `allCases` order, coding to utility, fixes label ties and the fingerprint).
- Produces:

```swift
enum CreditState: String, Codable { case engaged, held, quietKept, passive }

struct CreditedSlice: Equatable {
    let start: Date
    let end: Date
    let app: String
    let state: CreditState
    /// nil: counted but credited to nothing (passive on an app with no engaged slice yet, inside the grace).
    let purpose: AppPurpose?
}

struct CreditInput {
    let beats: [Beat]
    /// The session's counted time, from `CountedTime.spans` (below). Nothing outside it is credited.
    let counted: [DateInterval]
    /// Signals on for this derivation: those any beat in the bounds carries. No beat field carries one
    /// in Phase A, so it is empty until phase D's site kind; the counterfactual removes that signal.
    let signals: Set<SignalKind>
    let purposeOverrides: [String: String]
}

enum ActivityCredit {
    static func credit(_ input: CreditInput) -> [CreditedSlice]
    /// Any key, or clicks + scrolls ≥ engagedClickScrollPerBeat.
    static func isEngaged(_ slice: BeatSlice) -> Bool
}

/// What the engine counted. `DaySession.spans` are stretch bounds and include pauses,
/// so they are not this. Each record's start to end minus its `pausedSpans`. A record
/// with nil `pausedSpans` (older, or untrusted) is its bounds minus each run of `.paused`
/// or `.watchPause` beats, every run first extended back to the end of the last engaged
/// slice before it: the engine backdates a pause to where the quiet began, after beats
/// were already written as quiet.
enum CountedTime {
    static func spans(records: [(bounds: DateInterval, paused: [DateInterval]?)], beats: [Beat]) -> [DateInterval]
}

/// Verification only: builds beats from minute-level steps.
enum BeatTrace {
    struct Step { let app: String; let minutes: Double; let input: Input; var holder: String? = nil
                  var presence: BeatPresence? = nil }
    enum Input { case keys, clicks(Int), scrolls(Int), none, oneKeyEvery(minutes: Double) }
    static func beats(_ steps: [Step], from start: Date) -> [Beat]
}
```

A slice starts at its beat's start plus `offset` plus the seconds of the slices before it. A slice partly outside `counted` is clipped; the part outside yields nothing. Quiet age at a slice is its start minus the end of the last engaged slice in any app, or minus the first beat's start when there is none. Rules, first match wins:
1. **Engaged:** `PurposeMap.purpose(for: app, activity: .active, overrides:)`.
2. **Held** (spec ruling of 17 November: the whole quiet stretch, backdated). A *quiet stretch* is a maximal stretch of counted time containing no engaged slice, including the stretch before the first engaged slice and the one after the last. Inside it, a *held run* is a maximal run of beats whose `watchedApps` is not `[]` (non-empty, or nil because holders were not yet read), bounded by beats read as `[]`, that contains a non-empty beat at quiet age > `watchGrace`. The held run is credited `.held` from its first beat (clipped to the stretch's start) to the end of its last non-empty beat, so four minutes watched is four minutes held. Its holder is the app named in the most of the run's non-empty beats; on a tie, the front app if it is among the tied, else the first in sorted order. Its purpose is `PurposeMap.purpose(for: holder, activity: .passive, …)`, except that an ambiguous holder (a browser) is always `.media`; a call app (fixed communication, for example `us.zoom.xos`) stays communication through its own purpose. No microphone is read. A holder whose purpose is `.utility` makes no held run. Slices of the stretch outside held runs fall to 3a or 3b.
3a. **Quiet-kept:** the front app is not ambiguous (fixed, overridden, declared or unmapped), purpose from `.passive`; or the beat's presence is `.agent`, credited to the run's anchor (the first engaged app; the front app when there is none).
3b. **Passive:** the front app is ambiguous. Inside `watchGrace` of quiet, its rule's `active` purpose if this app had an engaged slice earlier in the input, else nil; after the grace, its rule's `passive` purpose.

Spec clarification adopted here: the spec gives quiet-kept to "a fixed purpose in the app-purpose map". An app the map does not list (a PDF viewer, say) is read as fixed, because `PurposeMap.purpose` gives it a purpose that does not depend on behaviour; only ambiguous apps are 3b.

- [ ] **Step 1: Write the failing checks** in `ActivityCreditChecks`:
  1. "Any key makes a slice engaged; three clicks or scrolls do; two do not".
  2. "Input beats a held screen": editor slices with keys while a browser holds the screen are `.engaged` `.coding`.
  3. "Once quiet passes the grace with a holder, the whole stretch is held, including a stretch with no engaged slice after it": editor in front, keys until base, then 4 minutes quiet with a browser holding (beats read from base+60): every slice from base to base+240 is `.held .media`. With the holder gone at base+90 (beats read `[]` after), nothing is held and the stretch is `.quietKept .coding`.
  3b. "A held run starts after the last beat read empty": editor quiet from base, holders read `[]` until base+300, then a browser holding to base+600: slices before base+300 are `.quietKept .coding`, after are `.held .media`.
  4. "A browser holding the screen is media; a call app holding it is communication": a browser holding for 10 minutes is `.media`; a call app holding for 10 minutes is `.communication`.
  5. "An untouched browser keeps its research for the grace, then is media": browser engaged until base, quiet to base+300, no holder: `.passive .research` before base+120, `.passive .media` after.
  6. "A browser never touched credits nothing during the grace": the same with no engaged slice: purpose nil before base+120.
  7. "Quiet is measured across apps": keys in the editor until base, a switch to a browser at base+100; the browser's slice starting at base+130 is past the grace.
  8. "Time outside the session's counted spans earns nothing": counted ends at base+60 of a 300-second trace; no slice ends after base+60.
  9. "An agent at work credits the anchor": an editor anchor, then `.agent` beats with a chat app in front: `.quietKept .coding`.
  10. "Counted time leaves out a record's pauses": a record 0 to 60 min with `pausedSpans` [20, 35] gives spans [0, 20] and [35, 60]. With nil `pausedSpans`, keys in every beat to the one ending at 20:30, `.quiet` beats to 30 and `.paused` beats from 30 to 35 (a backdated idle pause), the spans are [0, 20:30] and [35, 60]: slice resolution, the finest the beats hold.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement `ActivityCredit` and `CountedTime` (in `ActivityCredit.swift`) to the rules above.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass.
- [ ] **Step 5:** Commit: "Each counted second is credited to what the hands and screen were doing".

### Task 6: Sweep traces, written red

**Files:**
- Modify: `Sources/Verification/ActivitySweepChecks.swift`, `Sources/Verification/ActivityTraces.swift` (the traces beside `BeatTrace`)

**Interfaces:**
- Consumes: `BeatTrace` (Task 5), `ActivityDerivation.derive` and its types (Task 7's Interfaces block; the build stays red until Task 7 lands, and nothing is committed between).
- Produces:

```swift
struct SweepExpectation {
    let label: ActivityLabel
    var depth: SessionDepth? = nil              // nil: not asserted
    var phases: [PhaseActivity]? = nil          // in order; nil: not asserted
    var counted: [Bool]? = nil                  // per phase; nil: not asserted
    var splitCandidates: Int? = nil
    var creditedSeconds: TimeInterval? = nil    // total, within 30 s
    var purposeSeconds: [AppPurpose: TimeInterval]? = nil   // each within 30 s
}
enum ActivityTraces {
    static let all: [(name: String, input: DerivationInput, expect: SweepExpectation)]
}
```

One check per row, named "Sweep: <trace> is <expected label>". Minutes from `SelfTest.base`. E engaged (keys), Q quiet, H the named app in `watchedApps` (nil for the first minute of each quiet stretch, as the sampler reads holders only after a minute of quiet). Everything counted unless the row says otherwise. App roles, all from `PurposeMap.rules` as it stands: editor `com.microsoft.VSCode` (fixed coding), terminal `com.apple.Terminal` (fixed coding), browser `com.google.Chrome` (ambiguous: active research, passive media), design app `com.figma.Desktop` (fixed design), messaging app `com.tinyspeck.slackmacgap` (fixed communication), call app `us.zoom.xos` (fixed communication), media player `com.apple.TV` (fixed media), music `com.apple.Music`; viewer `com.apple.Preview`, which the map does not list (utility, with `declaredCategory` returning nil in checks). A step's app stays in front for all of that step, Q included. Every trace's `countsWhileWatching` is false.

| Trace | Evidence | Expected |
|---|---|---|
| a. Video, hands off | Browser E 0.5, then Q 9.5 with browser H | `.activity(.media)`, `.passive`, purposeSeconds media 570, research 30 |
| b. Coding with a tutorial playing | Editor E 30, browser H throughout | `.activity(.coding)`, `.deep`, phases [coding] |
| c. Editor untouched while video plays | Editor E 5, then Q 8 with browser H | `.activity(.media)`, `.passive`, phases [coding, media], purposeSeconds coding 300, media 480 |
| d. Code, browse, code | Editor E 40, browser E 10, editor E 30 | `.activity(.coding)`, `.deep`, phases [coding, research, coding], splitCandidates 0 |
| e. A film inside a session | Editor E 20, then 60 minutes of `.watchPause` beats with media player H, not counted | `.activity(.coding)`, phases [coding, media], counted [true, false], splitCandidates 1 |
| f. Left and not back | Editor E 30, messaging app E 25 | `.activity(.coding)`, `.light`, phases [coding, communication], splitCandidates 1, at minute 30 |
| Reading-heavy | Browser, 4 scrolls a beat, no keys, 30 | `.activity(.research)`, `.deep` |
| Click-heavy design | Design app, 5 clicks a beat, 30 | `.activity(.design)`, `.deep` |
| Code review | Editor, one key every 3 min, Q between, 30 | `.activity(.coding)`, `.deep` |
| Pause to watch a tutorial | Editor E 25, browser Q 6 with browser H, editor E 25 | `.activity(.coding)`, `.deep`, phases [coding, media, coding], splitCandidates 0, purposeSeconds coding 3 000, media 360 |
| Browser meeting | Browser Q 30 with browser H | `.activity(.media)`, purposeSeconds media 1 800 |
| Call app | Call app Q 30 with call app H | `.activity(.communication)`, `.passive`, purposeSeconds communication 1 800 |
| Lunch | Editor E 30, 60 minutes of `.paused` beats not counted, editor E 20 | `.activity(.coding)`, phases [coding, away, coding], splitCandidates 0 |
| Long pause, no departure | Editor E 20, Q 9, E 20 | `.activity(.coding)`, `.deep`, phases [coding] |
| Single-app run | Terminal E 30 | `.activity(.coding)`, `.deep` |
| Passive browser after coding | Editor E 30, browser Q 10, no holder | `.activity(.coding)`, phases [coding, media], splitCandidates 1 |
| Video opened, walked away | Browser E 2, then Q 20 with browser H, counted ending at minute 2 (backdated watching pause) | `.activity(.research)`, creditedSeconds 120 |
| Quiet on a non-member app | Editor E 20, viewer app 1 click then Q 8, editor E 20 | `.activity(.coding)`, `.light`, splitCandidates 0 |
| Untouched editor, no media | Editor E 0.5, then Q 30, counted ending at 0.5 (backdated idle pause) | `.unsorted` |
| A four-minute watch is a phase | Editor E 20, browser Q 4 with browser H, editor E 20 | `.activity(.coding)`, `.deep`, phases [coding, media, coding], splitCandidates 0, purposeSeconds media 240 |

- [ ] **Step 1:** Write `ActivityTraces.all` and one check per row.
- [ ] **Step 2:** Do not commit; Task 7's first run shows these red.

### Task 7: Working set, phases, depth and label (Core)

**Files:**
- Create: `Sources/Core/ActivityDerivation.swift`, `Sources/Core/SessionActivityShape.swift`, `Sources/Core/ActivityWorkingSet.swift`
- Test: `Sources/Verification/ActivityDerivationChecks.swift`, and Task 6's sweep

**Interfaces:**
- Consumes: `ActivityCredit.credit`, `CreditInput`, `CreditedSlice`, `Beat`, `ActivityConstants`.
- Produces:

```swift
enum PhaseActivity: Hashable, Codable { case purpose(AppPurpose), browsing, away }
enum SessionDepth: String, Codable { case deep, light, passive }
enum ActivityLabel: Hashable, Codable { case activity(AppPurpose), mixed, unsorted }
enum ShapeFidelity: String, Codable { case beats, appsOnly }

struct SessionPhase: Codable, Equatable {
    let start: Date
    let end: Date
    let activity: PhaseActivity
    let counted: Bool
    let credited: [String: TimeInterval]    // AppPurpose raw value to credited seconds in this phase
}

struct ActivityFingerprint: Codable, Hashable {
    let shares: [Int]        // per AppPurpose.allCases: share of credited seconds, rounded down to 20% steps, 0...5
    let topApps: [String]    // two apps with most credited seconds, ties by bundle id, padded with ""
    let siteKind: String     // "none" in this phase
}

/// One session's derived view: the snapshot stored at its end and the row's read model.
struct SessionActivityShape: Codable, Equatable {
    let algorithmVersion: Int
    let fidelity: ShapeFidelity
    let bounds: DateInterval                // the record's start to end when derived
    let countedSeconds: TimeInterval        // total of the counted spans it was derived from
    let signals: [SignalKind]               // on while its beats were recorded, sorted
    let phases: [SessionPhase]
    let depth: SessionDepth?                // nil for .appsOnly and for .unsorted
    let label: ActivityLabel
    let credited: [String: TimeInterval]    // AppPurpose raw value to credited seconds
    let fingerprint: ActivityFingerprint?   // nil for .appsOnly
    /// Departures whose return window closed with no return. Phase B reads these; nothing acts on them here.
    let splitCandidates: [Date]
}

struct DerivationInput {
    let credit: CreditInput
    let bounds: DateInterval
    let countsWhileWatching: Bool           // the session's WorkType.countsWhileWatching
    let isRunning: Bool
    let now: Date
}

enum ActivityDerivation {
    static func derive(_ input: DerivationInput) -> SessionActivityShape
}

enum ActivityWorkingSet {
    /// Members and departures of one run, from its credited slices and beats in time order.
    static func derive(_ slices: [CreditedSlice], beats: [Beat], countsWhileWatching: Bool) -> (members: Set<String>, departures: [Date])
}
```

Settled here, from "Left to the builder":
- **Working set.** The anchor is the app of the first engaged slice; with none, the front app of the first credited slice (so a call held from the start has a member). When work leaves the set (a departure at d, below), every non-member that receives an engaged slice after d is pending; when a later engaged slice on a member starts within `returnWindow` of d, every app pending since d joins. Membership is hindsight: a joined app's earlier slices count inside. `ThreadApps` was checked for reuse: it ranks apps by recorded seconds and knows no return rule, so it is not reused.
- **Departures.** The start of an engaged slice on an app not a member at that moment; the start of the first held or passive slice after one that was neither; the first `.watchPause` beat after a beat of any other presence. Quiet-kept time and `.paused` beats never depart, and with `countsWhileWatching` neither does held time (spec section 2). A departure returns when an engaged slice on a member (as of then) starts within `returnWindow`. One with no return is a split candidate once `bounds.end`, or `now` while running, is at least `returnWindow` after it, or the session has ended.
- **Phases (smoothing).** Cut `bounds` into 60-second cells. "Mostly" means more than 30 of the cell's 60 seconds. A cell's key: the purpose with most credited seconds in it (ties: `AppPurpose.allCases` order), counted; else, when it is mostly counted time credited to no purpose (3b inside the grace), no key: it takes its earlier neighbour's key (its later one's, if first); else, when its beats are mostly `.watchPause`, the holder's purpose, uncounted; else `.away`, uncounted. Run-length the keys, then repeatedly merge the shortest run under `minPhase` into its longer neighbour (ties: the earlier), until none is under `minPhase`, one run is left, or no legal merge remains. Counted and uncounted runs never merge into each other, so a short uncounted run between counted ones stays as it is. This cell-and-merge step is `internal static func phases(cells: [PhaseCell]) -> [SessionPhase]` from the start, so Task 8 reuses it unchanged.
- **Depth.** Over credited slices: `.passive` when held plus passive seconds exceed half of credited, leaving out all held seconds when `countsWhileWatching` (then held time is inside); else `.deep` when the run lasts at least `deepMinRun`, inside seconds (engaged or quiet-kept on a member, and every held second when `countsWhileWatching`, member or not, as spec section 2 says) are at least `deepInsideShare` of credited, and outside under `deepOutsideShare`; else `.light`. Nil when the label is `.unsorted`.
- **Label.** `.unsorted` under `minCreditedSeconds` credited. Else the purpose with most credited seconds (ties: `AppPurpose.allCases` order). With no weak signal in Phase A, `.mixed` cannot occur: the type stays. The counterfactual (derive again without the weak signals; a different top purpose gives `.mixed`) is described for phase D's site kind only, the one weak signal, and nothing in Phase A runs it.
- A run is the whole session in this phase; cutting runs at split candidates is phase B.

- [ ] **Step 1: Write the failing checks** in `ActivityDerivationChecks`:
  1. "An app joins the working set only when work returns to a member": editor, browser E, editor E within 15 min: browser is a member; with the return at 16 min it is not, and a split candidate sits at the browser's first engaged second.
  2. "An idle pause is never a departure": the lunch trace has no departures.
  3. "A running session's open window is not yet a split": trace f running with `now` 10 minutes after the departure has none; at 15 minutes it has one.
  4. "Watching counts inside for a category where watching is the work": the call-app trace with `countsWhileWatching` true is `.deep`, false `.passive`; and a meeting trace (editor E 10, then the call app Q 30 with call app H) has no departure and `splitCandidates == 0` when true, one departure when false.
  5. "The fingerprint buckets shares and names two apps": 70% coding and 30% research give coding 3, research 1, every other 0; a single-app session pads `topApps` with "".
  6. "Phases cover the session with no gap or overlap": for every sweep trace, phases are sorted, the first starts at `bounds.start`, each ends where the next starts, the last ends at `bounds.end`.
  7. Removed (no audio signals).
  8. "A short uncounted run between counted phases is kept": editor E 20, 2 minutes of `.paused` beats not counted, editor E 20 gives phases [coding, away, coding].
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these seven and every Task 6 sweep check fail.
- [ ] **Step 3:** Implement the three files.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass. If a sweep row fails because a constant, not the code, gives the wrong answer, stop and report the trace, the observed shape and the constant to the main session; a constant changes only with the owner's say, together with `algorithmVersion` and Task 3 check 8.
- [ ] **Step 5:** Run the `fix-reviewer` agent on Tasks 5 to 7 together. Address its findings.
- [ ] **Step 6:** Commit Tasks 6 and 7: "Each session can be read as phases of activity with a depth".

### Task 8: Phases for sessions recorded before beats (Core)

**Files:**
- Create: `Sources/Core/ActivityDerivation+AppsOnly.swift`
- Test: `Sources/Verification/ActivityDerivationChecks.swift` (append)

**Interfaces:**
- Consumes: `RecordedActivity` (`intervals`, `bounds`), `PurposeMap`, Task 7's phase smoothing.
- Produces: `extension ActivityDerivation { static func appsOnly(_ activity: RecordedActivity, bounds: DateInterval, purposeOverrides: [String: String]) -> SessionActivityShape }` with `fidelity .appsOnly`, `depth nil`, `fingerprint nil`, `signals []`, `splitCandidates []`. An ambiguous app's time is `.browsing` (no input is known for it); every other app is `.purpose(PurposeMap.purpose(for:activity: .active, …))`; a gap is `.away`, uncounted. Label: the top purpose by seconds, `.browsing` counting toward none; `.unsorted` under `minCreditedSeconds`.

- [ ] **Step 1: Write the failing checks:** "An older session shows phases from its apps alone, with no depth": editor 40, browser 10, editor 30 gives phases [coding, browsing, coding], `depth == nil`, `fidelity == .appsOnly`. "An older browser-only session is unsorted, not research".
- [ ] **Step 2:** Run `./build.sh --check`. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: pass.
- [ ] **Step 5:** Commit: "Sessions recorded earlier show their phases from app use alone".

### Task 9: Recording beats from the ticker (App)

**Files:**
- Create: `Sources/App/ActivityEvidence.swift`, `Sources/App/SessionStore+ActivityEvidence.swift`
- Modify: `Sources/App/SessionStore.swift` (one stored property and its init parameter; move out at least as many lines), `Sources/App/SessionStore+Presence.swift` (`observeIdle()`, `runTick()`, `handleApplicationActivation`), `Sources/Core/SessionEngine+Pauses.swift` (one read-only accessor), `build.sh` (`keep_internals store`: add `activityEvidence`)
- Test: `Sources/Verification/ActivityEvidenceStoreChecks.swift` (append)

**Interfaces:**
- Consumes: `BeatRecorder`, `BeatArchive`, `WatchDetector.Reading`, the `SessionEvent` `QuietSampler.read` returns, `InputCounters`, `IdleMonitor.idleSeconds()`.
- Produces:

```swift
/// SessionStore's activity-evidence state, held by one reference so the store gains one stored property.
final class ActivityEvidence {
    init(archive: BeatArchive = BeatArchive(), counters: InputCounters = InputCounters())
    var recorder = BeatRecorder()
    let archive: BeatArchive
    let counters: InputCounters
    var lastPresence: BeatPresence = .paused
    var lastWatched: Set<String>? = nil     // nil: holders not read this tick
    var lastPruneDay: Date?
}

extension SessionEngine {
    /// The running record's pauses so far, the open one included; nil when the engine
    /// does not trust its own spans. A public name for `trustedPausedSpans(until:)`,
    /// which `keep_internals` keeps private to the engine's files.
    func pausedSpansSoFar(until end: Date) -> [DateInterval]?
}

extension SessionStore {
    /// A session is not idle, or automatic sessions are on.
    var recordsBeats: Bool { get }
    /// Called by runTick right after observeIdle. Appends any beat that closed.
    func recordBeatTick(at now: Date)
    /// Called where handleApplicationActivation delivers an activation.
    func noteBeatActivation(bundleID: String?, at now: Date)
}
```

- `observeIdle()` names what was read, on every path, and decides nothing: engine `.paused(reason: .watching)` gives `.watchPause`; any other paused state, `.awaitingUserDecision` or `.idle` gives `.paused`; the quiet-under-60 branch gives `.input` when `quiet < 5`, else `.quiet`, and sets `lastWatched = nil` (holders were not read); past it, `.watchingObserved(byAgent: true)` gives `.agent`, `byAgent: false` gives `.watched`, `.idleObserved` gives `.quiet`, and `lastWatched = holders.watchedApps`, where `holders` is the `WatchDetector.Reading` `observeIdle()` already holds (fresh or from `watchingCache`).
- `runTick()` calls `recordBeatTick(at:)` right after `observeIdle()`. With `recordsBeats` false it calls `recorder.stop` once and appends what returns. An append error is logged once per launch with `os_log` and otherwise dropped; evidence never raises an alert.
- `recordsBeats` is `engine.state != .idle || engine.store.autoSessionsEnabled`.
- `noteBeatActivation` runs only in the delivering branch of `handleApplicationActivation`: not while awaiting confirmation, not on a break.
- On the first tick of each local day, `archive.prune(olderThan: ActivityConstants.defaultBeatRetentionDays, now:)`.
- A beat carries presence, holders and input counts only; `SessionStore` reads no audio.

- [ ] **Step 1: Write the failing checks** in `ActivityEvidenceStoreChecks`, on a store from `SelfTest+Fixtures` with a `TestClock`, a scratch `BeatArchive` and counter closures, inside `MainActor.assumeIsolated`:
  1. "A running session writes a beat every 30 seconds": with the clock at `Beat.gridStart(for: SelfTest.base)`, start a session, `runTick()` 90 times moving the clock 1 s each: 3 beats.
  2. "No beats are written with no session and automatic sessions off": 90 ticks, engine idle, `autoSessionsEnabled` false: 0 beats.
  3. "A watching pause is written as one": with the engine in `.paused(reason: .watching)`, the next beat's presence is `.watchPause`.
  4. "An app switch splits the beat's input by app": an activation mid-beat, keys advancing before and after: two slices with their own counts.
  5. Removed (no audio signals).
  6. "Recording never changes what the session counts": one 600-tick script, run with evidence recording and with `recordsBeats` forced false, gives equal `engine.snapshot()` and `elapsed`.
  7. "Holders not yet read are written as unread": during the first minute of quiet the beat's `watchedApps` is nil; after it, the sampler's set (or `[]`).
- [ ] **Step 2:** Run `./build.sh --check`. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: pass.
- [ ] **Step 5:** Run `python3 .claude/hooks/guard-live-data.py --check`. Expected: exit 0; `Application Support/Daybook/beats/` is inside the folder the guard already covers.
- [ ] **Step 6:** Run the `fix-reviewer` agent on the diff (session state, persistence). Address its findings.
- [ ] **Step 7:** Commit: "Daybook records which app had the hands and the screen while a session runs".

### Task 10: The snapshot and the read model (Core and App)

**Files:**
- Create: `Sources/App/SessionStore+SessionActivity.swift`, `Sources/Core/SessionMetadataArchive+ActivityShape.swift` (`saveActivityShape` only), `Sources/App/StorySessionDetail.swift` (the struct moved out of `SessionStore+StoryDetails.swift`, with the new field)
- Modify: `Sources/Core/SessionMetadata.swift` (`activityShape`, `isEmpty`), `Sources/Core/SessionMetadataArchive.swift` (`saveNote` becomes one `update` call; every "nothing left" test uses `isEmpty`), `Sources/App/SessionStore+StoryDetails.swift` (fill `phases`), `Sources/App/SessionStore+Presence.swift` (the minute heartbeat in `runTick` calls the sweep)
- Test: `Sources/Verification/ActivityEvidenceStoreChecks.swift` (append)

**Interfaces:**
- Consumes: `ActivityDerivation.derive`, `.appsOnly`, `BeatArchive.beats(in:)`, `CountedTime.spans`, `DaySession.recordIDs`, each record's `pausedSpans`, `SessionEngine.pausedSpansSoFar(until:)` for the running record, `WorkType.countsWhileWatching`, `SessionMetadataArchive`.
- Produces:

```swift
// SessionMetadata
var activityShape: SessionActivityShape?   // absent decodes as nil
var isEmpty: Bool { get }                  // note nil, power empty, activityShape nil

// `update` in SessionMetadataArchive.swift (it needs the private `commit`); `saveActivityShape` in the new file
extension SessionMetadataArchive {
    @discardableResult
    func update(_ recordID: UUID, _ change: (inout SessionMetadata) -> Void) -> SessionMetadataWriteResult
    @discardableResult
    func saveActivityShape(_ shape: SessionActivityShape, for recordID: UUID) -> SessionMetadataWriteResult
}

// StorySessionDetail gains
let phases: SessionActivityShape?

extension SessionStore {
    /// Beats while any lie in the session; else the stored snapshot; else app use alone. Memoised.
    func sessionActivity(for session: DaySession) -> SessionActivityShape?
    /// Writes a snapshot for each ended record whose stored one is missing or stale.
    func writeActivitySnapshots()
}
```

- `update` removes the entry when `isEmpty` after the change, else stores it, and commits through the archive's existing `commit`. `commit` is private to the class file, so `update` is written in `SessionMetadataArchive.swift` itself and `saveNote` shrinks to one `update` call, keeping the file from growing; `saveActivityShape` sits in the new file.
- Beats are used only when they can cover the whole session: its start falls on or after the oldest retained day file's day. A session that began before that reads its snapshot, so retention never replaces a complete snapshot with part of the evidence.
- The memo key is the session id, its `CountedTime.spans` (so a pause edit that keeps the beat count still invalidates), the number of beats in its bounds and `ActivityConstants.algorithmVersion`; a beat landing in another session does not invalidate it.
- A running session is derived from closed beats only; its strip trails by at most one beat.
- `writeActivitySnapshots()` runs on `runTick`'s existing 60-tick heartbeat and once on the refresh after the engine becomes idle. It considers records that ended within `defaultBeatRetentionDays` and have beats, and stores on each record id a shape derived over that record's own bounds and counted spans, with `signals` taken from the beats themselves: a signal is listed when any beat in the record's bounds carries it, never from the gate as it stands now. A Phase A beat carries none, so `signals` is empty. A stored shape is stale when its `bounds`, its `countedSeconds` (an Away answer or edit moved a pause) or its `algorithmVersion` differ from a fresh derivation's inputs. At most 20 records are written per call; the rest wait for the next heartbeat.
- The metadata file version stays 2: an older build ignores the unknown key; a downgrade that rewrites the file within 90 days loses snapshots that beats can rebuild.

- [ ] **Step 1: Write the failing checks:**
  1. "A session's phases reach its row": after Task 9's 30-minute engaged script, `storySessionDetail(session).phases?.label == .activity(<the fixture app's purpose>)`.
  2. "Clearing a note keeps the snapshot": save a snapshot, `saveNote("x")`, `saveNote(nil)`; the snapshot is unchanged and the entry still exists.
  3. "An ended session's snapshot is written once and rewritten when its bounds change": stop, sweep twice: one write (by `revision`); change the record's end, sweep: a second write with the new bounds.
  4. "After the evidence expires the snapshot is the record": prune every beat file and clear the memo; `sessionActivity(for:)` equals the stored snapshot.
  5. "A session with neither beats nor snapshot shows phases from its apps": `fidelity == .appsOnly`.
  6. "A pause the engine backdates earns no credit, end to end": with a real engine and the "pause when idle" threshold at 10 minutes, 5 minutes of keys, then quiet with no holder until the engine pauses as idle; after the pause, `sessionActivity(for:)` credits 5 minutes (within 30 s), and the snapshot written after the session ends says the same. Repeat with a browser holding the screen, ending in a watching pause: the same credit, and an uncounted media phase.
  7. "A corrected pause rewrites the snapshot": answer the Away question so the pause becomes work; the next sweep writes a snapshot with the larger `countedSeconds`.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: pass.
- [ ] **Step 5:** Run the `fix-reviewer` agent on the diff (persistence). Address its findings.
- [ ] **Step 6:** Commit: "A session keeps a summary of its phases after the detailed evidence expires".

### Task 11: The phase strip (Surfaces)

**Files:**
- Create: `Sources/Surfaces/Story/SessionPhaseStrip.swift`, `Sources/Surfaces/Story/SessionPhaseText.swift`, `Sources/Surfaces/Today/SessionEntryCard+Activity.swift` (`activityDetail` moved out of `DayStory.swift`, with the strip added)
- Modify: `Sources/Surfaces/Today/DayStory.swift` (pass `phases`; net growth at most 0), `Sources/Surfaces/Today/SessionCardSignature.swift` (`phases`), `Sources/Surfaces/Story/SessionReportView.swift` (strip above the app strip)
- Test: `Sources/Verification/SessionPhaseStripChecks.swift`

**Interfaces:**
- Consumes: `SessionActivityShape`, `SessionPhase`, `PhaseActivity`, `SessionDepth`, `AppPurpose.displayName`, `.symbolName`, `Tokens.Palette.workType`, `StoryShapeChart`'s band, divider and icon rules, `AppMarkLayout`.
- Produces:

```swift
struct SessionPhaseStrip: View {
    let shape: SessionActivityShape
    let tint: Color               // the session's Tokens.Palette.workType
    var height: CGFloat?          // nil: 28.zoomed, as StoryShapeChart
    var compact = false
}
enum SessionPhaseText {
    static func depthWord(_ depth: SessionDepth?) -> String?           // "Deep", "Light", "Passive"; nil
    static func phaseLine(_ phase: SessionPhase) -> String              // "Coding 40 min", "Away 1 h"
    static func summary(_ shape: SessionActivityShape) -> String        // VoiceOver value, phases in order
    static func fidelityNote(_ shape: SessionActivityShape) -> String?  // "From app use only" for .appsOnly
}
```

Visual treatment, for the design review to confirm or amend: drawn as `StoryShapeChart` is: one band clipped once, runs proportional to time, 1-point dividers in `StoryStyle.card`, no motion. A counted phase of a focused purpose fills with `tint`; another counted phase fills with `tint` at the strip's quiet strength; an uncounted phase (watching pause, away) is outlined, as the app strip draws gaps. A run wide enough carries its purpose's `symbolName`, shown by `AppMarkLayout.showsIcon`. The depth word sits on the row's title line beside the duration. The strip shows above the app strip in the open card and in the report, only when the session lasted at least 120 s, the app strip's own threshold. Accessibility label "Phases: what the session's time was spent on", value `summary`.

- [ ] **Step 1: Write the failing checks** for `SessionPhaseText`: "Each phase reads as its activity and length"; "An older session says its phases come from app use only"; "A session with no depth claim shows no depth word"; "VoiceOver hears every phase in order".
- [ ] **Step 2:** Run `./build.sh --check`. Expected: fail.
- [ ] **Step 3:** Implement the text, the view and the placements.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: pass, including the bare-length guard.
- [ ] **Step 5:** Render with `--snapshot` for traces b, d, e and lunch, light and dark, smallest and largest zoom. The main session runs the design review (`impeccable` critique; each fill at least 3:1 against the card) and records it in `docs/reviews/2026-11-<dd>-phase-strip.md`. Apply what it changes.
- [ ] **Step 6:** Commit: "Each session shows what its time was spent on, phase by phase".

### Task 12: Helper processes resolved to their app (stage 2)

Its purpose is now only helper resolution for the screen-held reading. Steps 1 to 4 already landed. `OwningApp` and `ProcessLookup` stay only if Task 2's probe says "helper resolution needed" (then step 5 runs); otherwise they are removed, with their checks, in one commit.

**Files:**
- Create: `Sources/Core/OwningApp.swift`, `Sources/App/ProcessLookup.swift`
- Modify (step 5 only): `Sources/App/WatchDetector.swift`
- Test: `Sources/Verification/ActivityEvidenceStoreChecks.swift` (append; the file is registered in Task 0)

**Interfaces:**
- Produces:

```swift
struct ProcessInfoLite: Equatable { let pid: Int32; let parent: Int32?; let bundleID: String?; let isRegularApp: Bool }
enum OwningApp {
    /// Itself if a regular app; else the nearest regular ancestor within 4 parents; else the
    /// running regular app whose bundle id is the longest dot-separated prefix of this one's
    /// (com.google.Chrome.helper → com.google.Chrome); else nil.
    static func resolve(_ process: ProcessInfoLite, lookup: (Int32) -> ProcessInfoLite?,
                        runningApps: Set<String>) -> String?
}
enum ProcessLookup {
    /// `proc_pidinfo(PROC_PIDTBSDINFO)` for the parent; `NSRunningApplication` for the bundle id and policy.
    static func info(_ pid: Int32) -> ProcessInfoLite?
    static func runningRegularApps() -> Set<String>
}
```

- [ ] **Step 1: Write the failing checks:** "A browser's helper reads as the browser" (helper `.prohibited`, parent the browser); "A helper whose parent is the launch daemon resolves by its bundle prefix, or to nothing"; "A dictation app's helper never resolves to a browser" (helper `com.example.dictation.audio`, browser running); "A keep-awake utility resolves to nothing"; "A parent loop ends".
- [ ] **Step 2:** Run `./build.sh --check`. Expected: fail.
- [ ] **Step 3:** Implement `OwningApp` (Core, pure) and `ProcessLookup` (App).
- [ ] **Step 4:** Run `./build.sh --check`. Expected: pass. Commit: "Daybook can tell which app a helper process works for".
- [ ] **Step 5 (only on Task 2's "helper resolution needed"):** `WatchDetector.read()` resolves each holder through `OwningApp.resolve`: one that resolves counts as watched under that app; one that does not stays `keptAwake`. Add the check "A browser's helper holding the screen reads as watching that browser", run `./build.sh --check`, and commit citing the Task 2 report: "Video a browser plays from a helper process is seen as watching".

### Task 13: The cost gate

The gate: beats, which carry no device signals in Phase A, add under 1% CPU and under 2 MB resident memory against today's idle figures.

**Files:**
- Create: `docs/debug/2026-11-<dd>-activity-evidence-cost.md`

- [ ] **Step 1 (headless):** In a tree copy (`CLAUDE.md`, Runtime probes), add a temporary check that runs `BeatRecorder.tick` 28 800 times (8 hours), appends each beat to a scratch `BeatArchive`, then derives one 8-hour session. Record time per tick, time per derivation and the day file's size. Pass: mean tick under 100 µs, the 8-hour derivation under 50 ms. Remove the copy.
- [ ] **Step 2 (live):** Ask the owner first: a worktree build writes beats into the live `Application Support/Daybook/beats/`. On yes, run it for 20 minutes of ordinary work and 20 minutes idle with a session running, sampling `ps -o %cpu=,rss= -p <pid>` every 10 s; repeat with the installed release as the baseline. Pass: mean CPU difference under 1 percentage point and median RSS difference under 2 MB.
- [ ] **Step 3:** Write the report with both steps' figures and the verdict. On a failure, stop and report to the owner with the hot path from `sample` (`FC_KEEP_SYMBOLS=1 ./build.sh`); nothing ships.
- [ ] **Step 4:** Commit the report: "A report records what recording activity evidence costs".

### Task 14: Final verification

- [ ] **Step 1:** Run `./build.sh --check`, `TZ=Europe/Berlin ./build.sh --check` and `TZ=Pacific/Kiritimati ./build.sh --check`. Expected: all pass; report `passed/total` for each.
- [ ] **Step 2:** Mutation pass in a tree copy, one at a time; each must turn the named check red: scroll-only input not engaged (sweep "Reading-heavy"); held before the grace (Task 5 check 3); credit outside counted spans (sweep "Video opened, walked away"); no synthetic guard (Task 4 check 4); an idle pause as a departure (sweep "Lunch"); held time starting only after the grace (sweep "A four-minute watch is a phase").
- [ ] **Step 3:** Run the `code-reviewer` panel and a Claude review on the branch diff; adopt or reject each finding in a table.
- [ ] **Step 4:** Report to the owner: stage commits, the two probe reports, the design review, the cost figures and the pass counts. No push and no pull request until asked.
