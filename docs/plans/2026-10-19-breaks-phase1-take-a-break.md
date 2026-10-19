# Breaks, phase 1: Take a break — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone can start a timed break from the popover, Today, the Session
menu or a reminder, and get a gentle break-over moment. The break is recorded
with its real length and its origin. Reminders gain Start break, Later and Skip.
Break notifications are retired, and every reminder and its outcome is logged.

**Architecture:** Core owns everything that has a rule in it:
- `ActiveBreak`, a new `.onBreak` pause, and the engine's start, extend, end and
  expire methods
- the sustained-activity detector
- the reminder clock (per-tier floors and Later), via `BreakReminder.evaluate`
- the `BreakLog` file

App (`SessionStore`, `AppCoordinator`) drives these from the 1 Hz ticker and
wires callbacks. Surfaces add a buttoned `BreakHUD`, a break mode in
`FocusHero`, a menu bar countdown, a Session-menu item and two Settings rows.

**Tech Stack:** Swift 5 mode, AppKit and SwiftUI, macOS 14. Built by
`build.sh` (no Xcode project). Tested by the headless self-check suite.

**Spec:** `docs/specs/2026-10-19-breaks-design.md`. Sections 3, 4 (buttons
only), 5 and 6 are this phase. Read them alongside this plan.

## Global Constraints

- **Layering:** Core, then App, then Design and Surfaces, one way only.
  `build.sh` typechecks `Sources/Core` alone, so Core may not use App types.
- **`keep_internals`** (`build.sh:83-97`):
  - A new engine helper not meant for the store goes in the engine's first list.
  - New engine stored properties the store must not set go in the engine's
    second (setter) list.
  - New `@Published` store properties go in the store's second list.
- **Timers:** no new timers. Everything runs off `SessionStore`'s 1 Hz ticker.
- **Lengths** in App, Design and Surfaces are tokens or `N.zoomed`. The menu bar
  keeps `// zoom: fixed`.
- **Checks:** each check uses `TestClock`, `SelfTest.base` or
  `SelfTest.anchoredNow()`, `SelfTest.scratchDirectory()` and
  `MemoryDefaults.suite(named: "fc-selftest-…")`. Never use
  `UserDefaults(suiteName:)`. New suites go at the **end** of `registeredTests`
  (`SelfTest+Registry.swift:140-144`). Never insert or remove a registered
  check, because positions are check numbers.
- **Recording rules** (spec §3):
  - A started break is recorded at its **actual** length if it lasts at least
    `minimumRecordedSession` (30 s).
  - Its name is "Break", or the label the person typed.
  - Its `workType` is `.breakTime`, its `breakOrigin` is `.started`, and its
    `plannedLength` is set.
- **Ending a break:**
  - **Planned length:** 5 min by default. Choices are 5, 10, 15 and 30 min.
    "+5 min" adds 300 s.
  - **Sustained activity:** input on at least 60 of 90 seconds after the planned
    end closes the break, backdated to when that activity began.
  - **Cap:** a break with nobody back ends at `plannedEnd + longAwayCap`.
- **Later and Skip** (spec §4):
  - Later lasts 10 min, or 15 min for the long-stretch prompt (`.ultradian`).
  - At most 2 Laters per due break.
  - Skip restarts only that tier's clock and records no rest.
  - A credited rest (an ended break) restarts every tier's clock.
- **Eyes:** the micro tier keeps today's buttonless HUD in this phase.
- **Commits:** the subject is one plain present-tense sentence stating what is
  now true for the user, with no type prefix. The body is wrapped prose. End with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Before committing** Tasks 2, 4, 6 and 9 (session state, settings,
  persistence, time), run the `fix-reviewer` agent on the diff.
- **Build:** `build.sh` must run with the Claude sandbox **disabled**.
- **Public repository:** no personal data in fixtures.

## Review Focus

1. **Relaunch or crash mid-break.**
   - The break comes back with the same start and planned end.
   - The countdown continues.
   - It is recorded exactly once.
   - Pinned by Task 2, `breakSurvivesRelaunch`.
2. **Lid closed overnight during a 5-minute break.**
   - The record ends at `plannedEnd + longAwayCap`, not 16 hours later.
   - A running session ends as a long absence does.
   - Pinned by Task 2, `forgottenBreakEndsAtCap` and `restorePastCapExpires`.
3. **Glancing at a work app, or automation firing, during the planned time.**
   - The break does not end.
   - No session resumes or starts.
   - Pinned by Task 2, `workAppDoesNotEndBreak` and `idleBreakBlocksLegacyStart`;
     Task 6, `automationWaitsForBreak`.
4. **Stop, Start or Continue pressed during a break.**
   - The break is recorded once.
   - No stretch shorter than the minimum is written.
   - Pinned by Task 6, `stopDuringBreakRecordsOnce`.
5. **Later pressed twice, then the long-stretch prompt.**
   - The third prompt offers no Later.
   - Skip never silences `.ultradian`.
   - Pinned by Task 4, `laterCapsAtTwo` and `skipLeavesOtherTiers`.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `Sources/Core/SessionState.swift` | modify | `PauseReason.onBreak`, `SessionRecord.breakOrigin` and `plannedLength`, `PersistedState.activeBreak` |
| `Sources/Core/BreakTaking.swift` | create | `BreakOrigin`, `ActiveBreak`, `BreakLength`, `SustainedActivity` |
| `Sources/Core/SessionEngine.swift` | modify | stored `activeBreak` |
| `Sources/Core/SessionEngine+Break.swift` | create | start, extend, end, expire and over-noticed for breaks |
| `Sources/Core/SessionEngine+PausedTransitions.swift`, `+Transitions.swift`, `+Absence.swift`, `+Restore.swift`, `+Corrections.swift`, `+Pauses.swift`, `+AwayDecision.swift` | modify | `.onBreak` ignores events; tag existing rests; persist and restore |
| `Sources/Core/BreakReminder.swift` | modify | `BreakTier: Codable`, `BreakClock`, `BreakSnooze`, `BreakPrompt.id` and `canLater`, floors and snooze in `evaluate` |
| `Sources/Core/BreakLog.swift` | create | reminder log file (prompts, outcomes, rhythm per day, eyes counts) |
| `Sources/Core/PersistenceStore.swift` | modify | keys `fc.breakClock`, `fc.menuBarShowsBreakCountdown`, `fc.breakOverSound`; remove `fc.workInterval` |
| `Sources/Core/Notifier.swift` | move to `_trash/` | break notifications retired |
| `Sources/App/SessionStore.swift`, `SessionStore+Breaks.swift`, `+Refresh.swift`, `+Presence.swift`, `+Actions.swift`, `+History.swift`, `+Away.swift`, `+Automation.swift` | modify | break actions, ticker, gates, log writes |
| `Sources/App/AppCoordinator.swift` | modify | `BreakHUD` wiring, sound, tracker suspend, automation gates, notifier removal |
| `Sources/App/MenuBarLabelModel.swift`, `Sources/Design/Components/Components.swift` | modify | cup glyph and countdown |
| `Sources/Surfaces/BreakHUD.swift` | create | non-activating HUD with up to three buttons, on the pointer's screen |
| `Sources/Surfaces/Focus/FocusHero.swift`, `Sources/Surfaces/SessionCommands.swift` | modify | break mode, Take a break, ⌥⌘B |
| `Sources/Surfaces/Settings/SettingsGroups.swift`, `SettingsModel.swift` | modify | two rows; the permission row goes |
| `Sources/Verification/BreakTakingChecks.swift`, `BreakClockChecks.swift`, `BreakLogChecks.swift`, `BreakStoreChecks.swift`, `BreakSurfaceChecks.swift` | create | the suites below |
| `.claude/hooks/guard-live-data.py`, `CLAUDE.md` | modify | name `break-log.json` as live data |

Work on a branch: `git switch -c claude/breaks-phase1`.

---

### Task 1: Break records carry their origin

**Files:**
- Create: `Sources/Core/BreakTaking.swift` (only `BreakOrigin` in this task)
- Modify: `Sources/Core/SessionState.swift:269-328` (`SessionRecord`)
- Modify: `Sources/Core/SessionEngine+Pauses.swift:105` ("Away") and `:146`
  ("Watching"); `Sources/Core/SessionEngine+AwayDecision.swift:57` (tookBreak)
- Test: `Sources/Verification/BreakTakingChecks.swift` (new suite; register at
  the end of `registeredTests`)

**Interfaces:**
- Produces:
  - `enum BreakOrigin: String, Codable, Equatable { case started, prompted, answered, away, watching }`
  - `SessionRecord.breakOrigin: BreakOrigin?` and `SessionRecord.plannedLength: TimeInterval?`
  - Both are memberwise-init parameters with default `nil`, and both are read
    with `decodeIfPresent`.

- [ ] **Step 1: Write the failing checks** in `enum BreakTakingChecks: CheckSuite`

```swift
("A break record written before origins existed still reads", oldRecordDecodes),
("Away, Watching and answered breaks say where they came from", restsAreTagged),

// oldRecordDecodes: encode a SessionRecord, strip breakOrigin/plannedLength from the JSON, decode.
expect(decoded.breakOrigin == nil && decoded.plannedLength == nil, "absent fields read as nil", &problems)
// round trip keeps them
expect(roundTripped.breakOrigin == .started && roundTripped.plannedLength == 300, "fields round-trip", &problems)

// restsAreTagged: engine = SelfTest.makeEngine(clock); engine.start(workType: .deepWork, intent: "Parser")
// declared away past breakThreshold → markedAway, advance, then a work app → the "Away" record
expect(rest(named: "Away")?.breakOrigin == .away, "declared away is .away", &problems)
// answer .tookBreak after an idle absence
expect(answered?.breakOrigin == .answered, "answered break is .answered", &problems)
// watching pause longer than breakThreshold
expect(rest(named: "Watching")?.breakOrigin == .watching, "watching is .watching", &problems)
```

- [ ] **Step 2: Verify they fail.** Run `./build.sh --check 2>&1 | grep -E '\[FAIL\]|passed$|error:'`.
  Expected: a compile error, because `breakOrigin` is undefined.
- [ ] **Step 3: Implement.**
  - Add `BreakOrigin`.
  - Add the two `SessionRecord` fields (init defaults and `decodeIfPresent`).
  - Pass `breakOrigin:` at the three construction sites.
- [ ] **Step 4: Verify.** Run the same command. Expected: `N/N passed`, with the
  two new checks `[PASS]`.
- [ ] **Step 5: Commit.** Subject: "Breaks remember whether they were answered,
  declared or watched".

---

### Task 2: The engine can hold a timed break

**Files:**
- Modify: `Sources/Core/BreakTaking.swift` (add `ActiveBreak`, `BreakLength`)
- Modify: `Sources/Core/SessionState.swift`. `PauseReason.onBreak`:
  - `displayName` "On a break"
  - persisted string `"onBreak"` in `PersistedState.init` (`:537`) and
    `restoredPauseReason` (`:577`)
  - `PersistedState.activeBreak: ActiveBreak? = nil`
- Modify: `Sources/Core/SessionEngine.swift` (stored `var activeBreak: ActiveBreak?`)
- Create: `Sources/Core/SessionEngine+Break.swift`
- Modify: `SessionEngine+Absence.swift:19`:
  - `pauseMeansNobodyHere(.onBreak) == false`, because a break has its own cap
- Modify: `SessionEngine+PausedTransitions.swift`:
  - `.paused(.onBreak)` responds only to `.manualResume`, which calls `endBreak()`
  - every other event (appActivated, overrideApplied, idleObserved, markedAway,
    awayBegan, awayEnded, watchingObserved, dwellExpired, manualPause) leaves it
    unchanged
- Modify: `SessionEngine+Transitions.swift:48-49`:
  - legacy `(.idle, .appActivated)` start requires `activeBreak == nil`
- Modify: `SessionEngine+Corrections.swift:129` (`snapshot()` writes `activeBreak`)
- Modify: `SessionEngine+Restore.swift`:
  - read `activeBreak`
  - `.paused(.onBreak)` with no `activeBreak` restores as `.manual`
  - after restore, call `expireBreakIfOutgrown()`
- Modify: `build.sh:90-92`:
  - `recordStartedBreak` goes in the engine's first list
  - `activeBreak` goes in the engine's setter list
- Test: `Sources/Verification/BreakTakingChecks.swift`

**Interfaces:**
- Consumes: `BreakOrigin` (Task 1).
- Produces:

```swift
struct ActiveBreak: Codable, Equatable {
    let id: UUID
    let start: Date
    var plannedEnd: Date
    var label: String?
    let threadID: UUID?        // the session thread it paused; nil when none ran
    var overNoticed: Bool      // the break-over HUD has been shown
    var plannedLength: TimeInterval { plannedEnd.timeIntervalSince(start) }
    func remaining(at moment: Date) -> TimeInterval   // negative = overtime
    func capEnd(longAwayCap: TimeInterval) -> Date      // plannedEnd + cap
}
enum BreakLength {
    static let standard: TimeInterval = 300
    static let choices: [TimeInterval] = [300, 600, 900, 1_800]
    static let extra: TimeInterval = 300
}
// SessionEngine+Break.swift
@discardableResult func startBreak(length: TimeInterval, label: String? = nil) -> Bool
func extendBreak(by seconds: TimeInterval)
@discardableResult func endBreak(at end: Date? = nil) -> Date?      // the end used; nil when none / not ended
@discardableResult func expireBreakIfOutgrown() -> Date?            // the capped end; nil when not due
func markBreakOverNoticed()
```

**Rules for `startBreak`:**
- **Refused** (returns false) when a break is already active, when the state is
  `.awaitingUserDecision`, or when the state is `.paused` for `.away`, `.idle` or
  `.systemSleep`.
- **`.idle`:** a break with `threadID: nil`.
- **`.running`:** `enterPause(reason: .onBreak)`, and `threadID = activeThreadID`.
- **Other pauses** (`.manual`, `.distractionApp`, `.watching`): leave the pause
  through the same path `.manualResume` uses for that reason, then pause
  `.onBreak`.
- Always `persist()`.

**Rules for `endBreak(at:)`:**
- **End time:** clamp to `start...now()`.
- **When the state is `.paused(.onBreak)`:**
  - Keep `thread = activeThreadID`.
  - `guard archiveCurrentSession(endingAt: brk.start)`. If it is refused, keep
    the break and return nil.
  - Then `recordStartedBreak(start:end:)`, `beginFreshSession()`,
    `activeThreadID = thread`, and `sessionStartDate = end`.
- **When no session ran:** only `recordStartedBreak`.
- **Always:** `activeBreak = nil` and `persist()`.
- **`func recordStartedBreak(_ brk: ActiveBreak, endingAt end: Date)`** (engine
  internal) writes through `saveRests(adding:)` only if
  `end - start >= store.minimumRecordedSession`. The record has name
  `label ?? "Break"`, `breakOrigin: .started`, `plannedLength`, and a new
  `threadID: UUID()`.

**Rules for `expireBreakIfOutgrown()`:**
- **Due** when `now() >= brk.capEnd(longAwayCap: store.longAwayCap)`.
- **Record** the break `[start, capEnd]`.
- **If paused `.onBreak`:** archive the stretch ending at `brk.start` and go idle
  the way `endAbsentSession()` does. Do not archive twice.
- Clear the break and return `capEnd`.

- [ ] **Step 1: Write the failing checks** (append to `BreakTakingChecks.tests`)

```swift
("Starting a break pauses the session and times it", startPausesRunning),
("Ending a break records its real length and resumes the thread", endRecordsAndResumes),
("A break with no session records itself and starts nothing", idleBreakRecordsOnly),
("A work app in front does not end a break", workAppDoesNotEndBreak),
("No session starts by itself while a break runs", idleBreakBlocksLegacyStart),
("A break survives a relaunch", breakSurvivesRelaunch),
("A forgotten break ends at the long-away cap", forgottenBreakEndsAtCap),
("A relaunch past the cap ends the break there", restorePastCapExpires),
("A break across midnight is one record", breakAcrossMidnight),
("A break is refused while an away question waits", refusedWhileDeciding),

// startPausesRunning
engine.start(workType: .deepWork, intent: "Parser"); clock.advance(1_200)
expect(engine.startBreak(length: 300), "starts", &problems)
expect(engine.state == .paused(reason: .onBreak), "paused onBreak", &problems)
expect(engine.activeBreak?.plannedLength == 300, "five minutes planned", &problems)
expect(!engine.startBreak(length: 300), "second start refused", &problems)
// endRecordsAndResumes: start, advance 1_200, startBreak(300), advance 420, extendBreak(by: 300), endBreak()
expect(rest?.workSeconds == 420 && rest?.plannedLength == 600 && rest?.breakOrigin == .started, "actual 7 min, planned 10", &problems)
expect(engine.state == .running && engine.activeThreadID == thread, "same thread resumes", &problems)
expect(engine.archive.records.filter { $0.workType != .breakTime }.last?.end == breakStart, "stretch closed at the break's start", &problems)
// idleBreakRecordsOnly: no session; startBreak(300); advance 20 → endBreak() → nothing recorded (< 30 s); again with 400 s → one record, state == .idle
// workAppDoesNotEndBreak: during break transition(on: .appActivated(bundleID: <a .work app>, name: "Xcode")), .overrideApplied, .idleObserved(seconds: 600), .markedAway
expect(engine.state == .paused(reason: .onBreak) && engine.activeBreak != nil, "still on a break", &problems)
// idleBreakBlocksLegacyStart: store.automationMode = .legacyHeuristic; idle; startBreak; appActivated(work) → state == .idle
// breakSurvivesRelaunch: snapshot → new engine (same defaults + archive dir) → restore
expect(restored.activeBreak == original.activeBreak && restored.state == .paused(reason: .onBreak), "same break back", &problems)
// then endBreak() on restored → exactly one .started record in archive
// forgottenBreakEndsAtCap: start session, startBreak(300), advance 300 + longAwayCap + 3_600, expireBreakIfOutgrown()
expect(rest?.end == brk.plannedEnd.addingTimeInterval(store.longAwayCap), "ends at cap, not now", &problems)
expect(engine.state == .idle, "session ended as a long absence", &problems)
// restorePastCapExpires: snapshot mid-break, advance past cap, restore into a fresh engine → state .idle, one record ending at cap
// breakAcrossMidnight: clock at local 23:57 built from Calendar.current on SelfTest.base's day; startBreak(600); advance 600; endBreak()
expect(breaks.count == 1 && breaks[0].workSeconds == 600, "one ten-minute record across midnight", &problems)
// refusedWhileDeciding: drive to .awaitingUserDecision (idle absence past breakThreshold, then a work app) → startBreak returns false
```

- [ ] **Step 2: Verify they fail.** Run `./build.sh --check 2>&1 | grep -E '\[FAIL\]|passed$|error:'`.
  Expected: a compile error, because `startBreak` is undefined.
- [ ] **Step 3: Implement** the interfaces and rules above. Fix every switch
  over `PauseReason` the compiler reports. `FocusHero.swift:24-35` is fixed in
  Task 8. For now, map `.onBreak` there to the same mode as `.paused`.
- [ ] **Step 4: Verify.** Run the same command. Expected: all pass, including
  the earlier engine suites (no regression in away and absence checks).
- [ ] **Step 5: Run `fix-reviewer`** on the diff and address its findings.
- [ ] **Step 6: Commit.** Subject: "A break can be started, timed and recorded
  at its real length".

---

### Task 3: Sustained activity is told apart from a glance

**Files:**
- Modify: `Sources/Core/BreakTaking.swift` (add `SustainedActivity`)
- Test: `Sources/Verification/BreakTakingChecks.swift`

**Interfaces:**
- Produces:

```swift
struct SustainedActivity: Equatable {
    static let window: TimeInterval = 90
    static let required = 60
    /// Call once per tick when input happened in the last second. Returns the
    /// first active second of a window holding `required` active seconds.
    mutating func record(activeAt moment: Date) -> Date?
    mutating func reset()
}
```

Seconds older than `window` are dropped. Repeat calls within the same whole
second count once.

- [ ] **Step 1: Write the failing checks**

```swift
("A minute of work after a break is noticed, a glance is not", sustainedActivity),
// 59 active seconds spread over 90 → nil; the 60th → returns the first of them
// 60 active seconds spread over 120 (every other second) → nil
// reset() clears
expect(first == start, "backdated to the first active second", &problems)
```

- [ ] **Step 2: Verify it fails** (compile error).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify** that it passes.
- [ ] **Step 5: Commit.** Subject: "A break ends on returning work, not on a
  glance".

---

### Task 4: Reminders can be put off or skipped

**Files:**
- Modify: `Sources/Core/BreakReminder.swift`:
  - `BreakTier` gains `Codable`
  - add `BreakClock` and `BreakSnooze`
  - `BreakPrompt` gains `let id: UUID = UUID()` and `var canLater = true`
  - `evaluate` gains `clock:`
- Modify: `Sources/Core/PersistenceStore.swift`:
  - `var breakClock: BreakClock`, stored as JSON under `fc.breakClock`
  - add the key to `removeAll()`
  - remove `fc.workInterval` and its property
- Test: `Sources/Verification/BreakClockChecks.swift` (new suite, registered last)

**Interfaces:**
- Produces:

```swift
struct BreakSnooze: Codable, Equatable { let tier: BreakTier; var until: Date; var count: Int }
struct BreakClock: Codable, Equatable {
    var floors: [BreakTier: Date] = [:]
    var snooze: BreakSnooze?
    static let maxLaters = 2
    static let laterLength: TimeInterval = 600
    static let stretchGuardLaterLength: TimeInterval = 900     // .ultradian
    mutating func credit(at moment: Date)                       // every floor = moment; snooze = nil
    mutating func skip(_ tier: BreakTier, at moment: Date)      // floors[tier] = moment; clears a snooze of that tier
    mutating func later(_ tier: BreakTier, at moment: Date)     // until = moment + length for tier; count += 1 if same tier else 1
    mutating func clearSnoozeIfNotDue(_ due: BreakTier?)        // nil or lower than snooze.tier clears it
}
static func evaluate(_ stretches: [AppUsageSession], now: Date, last: BreakNotice?,
                     tiers: [BreakTier] = BreakTier.allCases,
                     clock: BreakClock = BreakClock()) -> Evaluation
```

**`evaluate` rules:**
- **Floors.** A tier's work counts only usage after `clock.floors[tier]`.
  Stretches are clipped at the floor before `worked` walks back.
- **Snooze running.** While `now < snooze.until`, tiers at or below
  `snooze.tier` produce no prompt. `due` and `next` still report them, so the
  popover still says "Break due".
- **Snooze ended.** When `now >= snooze.until` and `snooze.tier` is still due,
  prompt for it and ignore the `last` repeat suppression. Set
  `canLater = snooze.count < BreakClock.maxLaters`.
- **Default arguments.** Today's behaviour is unchanged. The existing break
  checks must keep passing.

- [ ] **Step 1: Write the failing checks** in `enum BreakClockChecks: CheckSuite`

```swift
("Later brings the reminder back in ten minutes", laterReturnsInTen),
("Later is offered twice, not a third time", laterCapsAtTwo),
("Skip restarts that reminder only", skipLeavesOtherTiers),
("A taken break restarts every reminder", creditResetsAll),
("The reminder clock survives a relaunch", clockPersists),

// laterReturnsInTen: 55 min continuous → prompt(.cognitive); clock.later(.cognitive, at: now)
expect(evaluate(at: now + 300).prompt == nil, "quiet at +5", &problems)
expect(evaluate(at: now + 600).prompt?.tier == .cognitive, "back at +10 despite lastBreakNotice", &problems)
// laterCapsAtTwo: later twice → third prompt.canLater == false
// skipLeavesOtherTiers: 95 min continuous; clock.skip(.cognitive, at: now)
expect(eval.due != .cognitive, "cognitive restarted", &problems)
expect(BreakReminder.worked(clipped for .ultradian) >= 95 * 60, "ultradian still counts the whole run", &problems)
// creditResetsAll: credit(at: now) → due == nil and next.seconds == 20 min for .micro
// clockPersists: PersistenceStore(defaults: MemoryDefaults.suite(named: "fc-selftest-breakclock")!) write → new store reads equal
```

- [ ] **Step 2: Verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** All pass, including the existing checks
  `testBreakReminder` and `testBreakTiers`.
- [ ] **Step 5: Run `fix-reviewer`** (settings and time) and address its
  findings.
- [ ] **Step 6: Commit.** Subject: "A break reminder can be put off twice or
  skipped".

---

### Task 5: Every reminder and its outcome is logged

**Files:**
- Create: `Sources/Core/BreakLog.swift`, modelled on
  `Sources/Core/AmbientPowerLog.swift`:
  - versioned `Document` (version 1)
  - `loadFailure` blocks overwrite
  - atomic write
  - `writeOverride` for tests
- Modify: `.claude/hooks/guard-live-data.py`:
  - add a `blocked` case and a docstring line for `break-log.json` inside the
    live folder
  - then run `python3 .claude/hooks/guard-live-data.py --check`
- Modify: `CLAUDE.md`, "Live data" paragraph: add `break-log.json`
- Test: `Sources/Verification/BreakLogChecks.swift` (new suite, registered last)

**Interfaces:**
- Produces:

```swift
enum BreakPromptKind: String, Codable { case eyes, main, long, stretchGuard
    static func of(_ tier: BreakTier) -> BreakPromptKind }   // micro→eyes, cognitive→main, ultradian→stretchGuard
enum BreakPromptOutcome: String, Codable { case started, left, later, skipped, unanswered, held, credited }
struct BreakPromptEntry: Codable, Equatable, Identifiable {
    let id: UUID; let kind: BreakPromptKind; let due: Date; let shown: Date
    var laterCount = 0; var outcome: BreakPromptOutcome?; var outcomeAt: Date?
    var heldSeconds: TimeInterval?; var holdReasons: [String]?        // phase 3
}
struct BreakRhythmSnapshot: Codable, Equatable {
    var workMinutes: Int?; var breakMinutes: Int?; var eyes: Bool; var guardMinutes: Int?; var override: String?
    static func fromTiers(_ enabled: Set<BreakTier>) -> BreakRhythmSnapshot
    // cognitive on → 50/5; micro → eyes; ultradian on → guardMinutes 90 (spec §1 migration)
}
struct BreakDay: Codable, Equatable { let day: Date; var rhythm: BreakRhythmSnapshot; var eyesPrompts: Int }
final class BreakLog {
    static let fileName = "break-log.json"
    static let retentionDays = 400
    init(directory: URL = SessionArchive.defaultDirectory, calendar: Calendar = .current,
         writeOverride: ((Data) -> String?)? = nil)
    private(set) var prompts: [BreakPromptEntry]
    private(set) var days: [BreakDay]
    @discardableResult func recordShown(_ entry: BreakPromptEntry) -> String?
    @discardableResult func setOutcome(_ outcome: BreakPromptOutcome, for id: UUID, at moment: Date) -> String?
    @discardableResult func noteLater(for id: UUID, at moment: Date) -> String?   // laterCount += 1, outcome = .later
    @discardableResult func noteRhythm(_ rhythm: BreakRhythmSnapshot, on moment: Date) -> String?  // upsert by start of day; no write when equal
    @discardableResult func noteEyesPrompt(at moment: Date) -> String?
}
```

Retention prunes prompts and days older than 400 days on each write. Each
returned `String?` is the write error, as in `AmbientPowerLog`.

- [ ] **Step 1: Write the failing checks** in `enum BreakLogChecks: CheckSuite`

```swift
("The reminder log keeps prompts and their outcomes across a reload", logRoundTrip),
("A day's rhythm is written once and replaced when it changes", rhythmUpsert),
("The reminder log forgets entries older than 400 days", logRetention),
("An unreadable reminder log is never overwritten", logLoadFailureBlocks),

// logRoundTrip: recordShown, noteLater, setOutcome(.skipped) → new BreakLog(directory: same) has laterCount 1, outcome .skipped
// rhythmUpsert: noteRhythm(A, on: SelfTest.base) twice → one day, file written once (count via writeOverride);
//   noteRhythm(B, on: base + 3_600) → still one day, rhythm == B
expect(BreakRhythmSnapshot.fromTiers([.cognitive, .ultradian]) ==
       BreakRhythmSnapshot(workMinutes: 50, breakMinutes: 5, eyes: false, guardMinutes: 90, override: nil), "tiers map as the spec's migration table", &problems)
// logRetention: entry shown 401 days before base (built with Calendar.current.date(byAdding: .day, value: -401, to: base)) drops on next write
// logLoadFailureBlocks: garbage bytes in break-log.json → recordShown returns an error and the file is unchanged
```

- [ ] **Step 2: Verify they fail.**
- [ ] **Step 3: Implement.** Then update the guard and `CLAUDE.md`, and run
  `python3 .claude/hooks/guard-live-data.py --check`. Expected: it passes.
- [ ] **Step 4: Verify.** All checks pass.
- [ ] **Step 5: Commit.** Subject: "Daybook keeps a log of break reminders and
  what happened to them".

---

### Task 6: SessionStore runs breaks from the ticker

**Files:**
- Modify: `Sources/App/SessionStore.swift`:
  - `let breakLog: BreakLog`, wired like `AmbientPowerLog(directory: engine.archive.dataDirectoryURL)`
  - stored `var sustained = SustainedActivity()`
  - `@Published private(set) var breakRemaining: TimeInterval = 0`
  - callbacks
  - `onBreakDue`'s type becomes `((BreakPrompt) -> Bool)?`, which returns
    whether the reminder was shown
- Modify: `Sources/App/SessionStore+Breaks.swift`:
  - `refreshBreak()` uses `now()` instead of `Date()`
  - quiet while on a break
  - passes `engine.store.breakClock`
  - clears an outgrown snooze
  - logs the day's rhythm, eyes counts and shown prompts
  - new break actions
- Modify: `Sources/App/SessionStore+Refresh.swift:80-83`:
  - `ticks` is also true while `isOnBreak`
- Modify: `Sources/App/SessionStore+Presence.swift`:
  - each tick: `tickBreak()`
  - `:134,147` treat `isOnBreak` like `.away` for presence
- Modify: `Sources/App/SessionStore+Actions.swift` (`start()`, `startQuick`,
  `stop()`, `togglePause()`) and `SessionStore+History.swift:414,432,903`
  (Continue):
  - each calls `endBreakIfNeeded()` first
  - `togglePause()` while on a break ends it
- Modify: `Sources/App/SessionStore+Automation.swift:32,97`:
  - add `var automationWaits: Bool { hasUnresolvedAwayDecision || isOnBreak }`
  - `applyAutomaticActivity` and `startAutomatically` gate on it
  - leave `hasUnresolvedAwayDecision` itself unchanged, because the UI and the
    manual actions read it
- Modify: `build.sh:95-97`:
  - `breakRemaining` goes in the store's setter list
  - `tickBreak`, `afterBreakEnded` and `sustained` go in its first list
- Test: `Sources/Verification/BreakStoreChecks.swift` (new suite, registered last)

**Interfaces:**
- Consumes: Tasks 2–5.
- Produces (used by Tasks 7–8):

```swift
var isOnBreak: Bool { engine.activeBreak != nil }
var activeBreak: ActiveBreak? { engine.activeBreak }
var onBreakOver: ((ActiveBreak) -> Bool)?    // true when the HUD reached the screen
var onBreakBegan: (() -> Void)?
var onBreakEnded: (() -> Void)?
func startBreak(length: TimeInterval? = nil, label: String? = nil, from prompt: BreakPrompt? = nil)
func endBreak()                               // End break / Resume / Done
func extendBreak()                            // +5 min
func laterBreak(_ prompt: BreakPrompt)
func skipBreak(_ prompt: BreakPrompt)
func breakPromptUnanswered(_ prompt: BreakPrompt)
func endBreakIfNeeded()
```

**Rules:**
- **`startBreak` length.** The default is
  `prompt.map { max($0.tier.breakLength, BreakLength.standard) } ?? BreakLength.standard`.
- **`startBreak` side effects.** On success: `onBreakBegan?()`, and when
  `prompt` is given, `breakLog.setOutcome(.started, …)`. Also, if the most recent
  logged prompt was shown in the last 10 min with outcome nil or `.unanswered`,
  mark it `.started`.
- **`tickBreak()`** runs once per tick, in this order:
  1. If `expireBreakIfOutgrown()` returns an end, call `afterBreakEnded(end)`.
  2. Update `breakRemaining`.
  3. When `remaining <= 0` and `!overNoticed`: if `onBreakOver?(brk) == true`,
     call `engine.markBreakOverNoticed()`.
  4. When `remaining <= 0`: if idle seconds ≤ 1, feed
     `sustained.record(activeAt: now())`. A returned start leads to
     `engine.endBreak(at: start)` and then `afterBreakEnded`.
- **`afterBreakEnded(end)`:**
  - `engine.store.breakClock.credit(at: end)`
  - `sustained.reset()`
  - `onBreakEnded?()`
  - `refresh()`
- **`laterBreak`:**
  - `breakClock.later(prompt.tier, at: now())`
  - `breakLog.noteLater(for: prompt.id, …)`
- **`skipBreak`:**
  - `breakClock.skip(prompt.tier, at: now())`
  - `breakLog.setOutcome(.skipped, …)`
- **`refreshBreak`:** log a prompt only when `onBreakDue` returns true. For
  `.micro`, call `noteEyesPrompt` instead of `recordShown`. Keep writing
  `lastBreakNotice` either way, as today.

- [ ] **Step 1: Write the failing checks** in `enum BreakStoreChecks: CheckSuite`
  (`SessionStore(engine:, now: { clock.value })` built as in
  `CardClaimChecks.swift:23-30`)

```swift
("Pressing Stop during a break records the break once", stopDuringBreakRecordsOnce),
("Automatic sessions wait for a break to end", automationWaitsForBreak),
("Work after the planned end closes the break where it began", sustainedEndsBreak),
("A taken break restarts the reminders", breakCreditsClock),
("Later and Skip are logged against the reminder", actionsAreLogged),
("No reminder is due during a break", quietDuringBreak),

// stopDuringBreakRecordsOnce: start, advance 1_200, startBreak(), advance 400, stop()
expect(breaks.count == 1 && breaks[0].workSeconds == 400, "one break", &problems)
expect(!records.contains { $0.workType != .breakTime && $0.workSeconds < 30 }, "no empty stretch", &problems)
// automationWaitsForBreak: automationWaits == true while on a break, hasUnresolvedAwayDecision == false; startAutomatically(...) leaves state .paused(.onBreak)
// sustainedEndsBreak: startBreak(300); advance 300; tick with idle 0 for 60 s → break end == planned end, state .running
// breakCreditsClock: after endBreak(), engine.store.breakClock.floors.count == BreakTier.allCases.count
// actionsAreLogged: onBreakDue = { _ in true }; drive a cognitive prompt; laterBreak → laterCount 1; skipBreak → outcome .skipped
// quietDuringBreak: on a break, refreshBreak() → isBreakDue == false and onBreakDue not called
```

- [ ] **Step 2: Verify they fail.**
- [ ] **Step 3: Implement.** If the idle-seconds source is not injectable,
  expose it through the store's existing idle seam. Check how `observeIdle()`
  reads `IdleMonitor` in tests, and reuse that seam.
- [ ] **Step 4: Verify.** All checks pass.
- [ ] **Step 5: Run `fix-reviewer`** (session state and time) and address its
  findings.
- [ ] **Step 6: Commit.** Subject: "Breaks run on the app's clock and keep
  automatic sessions waiting".

---

### Task 7: Reminders and the break-over moment have buttons, and notifications go

**Files:**
- Create: `Sources/Surfaces/BreakHUD.swift`:
  - reuse `NonActivatingHUDPanel` and `FirstMouseHostingView` from
    `RewardHUD.swift`; make them internal if they are private
  - do not grow `RewardHUD.swift`, which is near 300 lines
- Modify: `Sources/App/AppCoordinator.swift`:
  - `store.onBreakDue` (`:648-671`):
    - `.micro` → `RewardHUD` as today
    - `.cognitive` / `.ultradian` → `BreakHUD`
    - return `breakReminderReachesScreen(...)`
    - not reachable → show nothing and return false
  - `store.onBreakOver` → `BreakHUD` plus sound
  - `onBreakBegan` / `onBreakEnded` → `tracker.suspend()` / `resumeTracking()`,
    as for away (`:642-643`)
  - `evaluateAutomation()` (`:205`) skips while `store.isOnBreak`, then calls
    `detector.reset()`
  - `activityRuleInput` (`:245-266`): presence is away while on a break
  - `:249,651` presence matches include the break
  - remove `notifier` (`:13`, `:77`, `:533`, `:658`)
- Move: `Sources/Core/Notifier.swift` → `_trash/Notifier.swift`
  (`mkdir -p _trash && mv …`; git records the deletion)
- Modify: `Sources/Surfaces/Settings/SettingsGroups.swift:359-367` (remove the
  permission row) and `SettingsModel.swift`:
  - remove `import UserNotifications`, `notificationsDenied` and
    `openNotificationSettings()`
  - keep `refreshSystemStatus()` for the login item
- Modify: `Sources/Verification/SelfTest/SelfTest+WakeActivation.swift:218`
  (`testBreakReminderUsesOneChannel`) and its title at `SelfTest+Registry.swift:300`:
  - same position, re-purposed: "A due break shows only at the screen; away, it
    waits"
  - assert `breakReminderReachesScreen` is false for each of the four absences
    and true otherwise
- Test: `Sources/Verification/BreakSurfaceChecks.swift` (new suite, registered last)

**Interfaces:**
- Consumes: Task 6 (store API), Task 4 (`BreakPrompt.canLater`, `.id`).
- Produces:

```swift
struct BreakHUDButton { let title: String; let isPrimary: Bool; let action: () -> Void }
struct BreakHUDContent {
    let title: String; let detail: String; let symbolName: String
    let buttons: [BreakHUDButton]; let duration: TimeInterval
    let onTimeout: (() -> Void)?
}
@MainActor final class BreakHUD { func show(_ content: BreakHUDContent); func dismiss() }
enum BreakHUDCopy {   // pure, in Surfaces, checked headless
    static func reminder(_ prompt: BreakPrompt) -> (title: String, detail: String, buttons: [String])
    static func breakOver(threadName: String?) -> (title: String, detail: String, buttons: [String])
}
```

**Copy:**
- **`.cognitive` reminder:**
  - Title and detail: the existing `prompt.title` and `prompt.body`.
  - Buttons: "Start break" (primary), "Later" (only when `canLater`), "Skip".
- **`.ultradian` reminder:**
  - Buttons: "Start break" (primary), "Remind me in 15 min" (only when
    `canLater`).
- **Break over:**
  - Title: "Break's over".
  - Detail: "Back to \(name)?", or "" when there is no thread.
  - Buttons: "Resume" (or "Done" when there is no thread) (primary), "+5 min".

**HUD behaviour:**
- Shows on the `NSScreen` containing `NSEvent.mouseLocation`, falling back to
  `NSScreen.main`.
- Announces through `Announcement.post`.
- Lasts `FocusConstants.breakHUDSeconds`.
- A timeout calls `onTimeout`. For reminders, `store.breakPromptUnanswered`.
- Any button dismisses it.

**Sound:** when `store.engine.store.breakOverSound` is true, play
`NSSound(named: "Tink")` once with the break-over HUD.

- [ ] **Step 1: Write the failing checks** in `enum BreakSurfaceChecks: CheckSuite`

```swift
("A reminder offers Later only while it may", reminderButtons),
("Break's over names the thread, or offers Done without one", breakOverCopy),
// reminderButtons
expect(BreakHUDCopy.reminder(cognitive(canLater: true)).buttons == ["Start break", "Later", "Skip"], "full set", &problems)
expect(BreakHUDCopy.reminder(cognitive(canLater: false)).buttons == ["Start break", "Skip"], "no third Later", &problems)
expect(BreakHUDCopy.reminder(ultradian(canLater: true)).buttons == ["Start break", "Remind me in 15 min"], "guard has no Skip", &problems)
// breakOverCopy
expect(BreakHUDCopy.breakOver(threadName: "Parser") == ("Break's over", "Back to Parser?", ["Resume", "+5 min"]), "with thread", &problems)
expect(BreakHUDCopy.breakOver(threadName: nil).buttons == ["Done", "+5 min"], "without thread", &problems)
```

- [ ] **Step 2: Verify they fail.**
- [ ] **Step 3: Implement** `BreakHUD`, the copy, the coordinator wiring, the
  notifier removal and the re-purposed check.
- [ ] **Step 4: Verify.** All checks pass. Then
  `grep -rn "UserNotifications\|Notifier" Sources` returns nothing.
- [ ] **Step 5: Commit.** Subject: "Break reminders offer Start, Later and Skip,
  and no longer arrive as stale notifications".

---

### Task 8: The break shows in the menu bar, the popover, Today and the Session menu

**Files:**
- Modify: `Sources/App/MenuBarLabelModel.swift` (`MenuBarDisplay`: add
  `isOnBreak: Bool`, `breakText: String?`; accessibility label)
- Modify: `Sources/Design/Components/Components.swift:333-352` (`MenuBarLabel`):
  - on a break, `Image(systemName: "cup.and.saucer.fill")` replaces the goal
    glyph
  - then `breakText` when present, else the existing `time`
- Modify: `Sources/Core/PersistenceStore.swift`:
  - `menuBarShowsBreakCountdown: Bool`, default true, key
    `fc.menuBarShowsBreakCountdown`
  - `breakOverSound: Bool`, default true, key `fc.breakOverSound`
  - add both to `removeAll()`
- Modify: `Sources/Surfaces/Settings/SettingsModel.swift` and
  `SettingsGroups.swift` "Breaks" panel: two `toggleRow`s, "Show break countdown
  in the menu bar" and "Play a sound when a break is over"
- Modify: `Sources/Surfaces/Focus/FocusHero.swift`:
  - `FocusSurfaceMode.onBreak`, chosen whenever `store.isOnBreak`, session or
    not, before any other mode
  - the body shows "On a break", the remaining time (`Tokens.preciseDuration`,
    or "+Nm over"), "End break" (primary) and "+5 min"
  - idle, running and manual-paused modes gain a secondary "Take a break" button
    calling `store.startBreak()`
  - `:409-414` underline copy reads "On a break"
  - The popover shows `HeroCard` (`PopoverView.swift:76`) above
    `FocusBreakLine` (`:90`). If `HeroCard` does not render `FocusHero`, give
    `HeroCard` the same break mode and Take a break button, so the popover and
    Today match. `FocusBreakLine` shows nothing while on a break.
- Modify: `Sources/Surfaces/SessionCommands.swift:7-26,78-80`:
  - `SessionShortcut.takeBreak` (⌥⌘B)
  - an item titled `store.isOnBreak ? "End Break" : "Take a Break"`
  - the item is disabled while an away decision waits
- Test: `Sources/Verification/BreakSurfaceChecks.swift`

**Interfaces:**
- Consumes: Task 6 (`isOnBreak`, `activeBreak`, `breakRemaining`, `startBreak`,
  `endBreak`, `extendBreak`).
- Produces:
  `static func breakText(remaining: TimeInterval) -> String` on `MenuBarDisplay`.
  The rules, which pin the once-a-minute redraw:
  - more than 60 s left → `"\(Int(ceil(remaining / 60)))m"`
  - 0 < remaining ≤ 60 → `"\(Int(ceil(remaining)))s"`
  - −60 < remaining ≤ 0 → `"Over"`
  - otherwise → `"+\(Int(-remaining / 60))m"`

  Accessibility label: "On a break, N minutes left" or "Break over by N
  minutes".

- [ ] **Step 1: Write the failing checks** (append to `BreakSurfaceChecks.tests`)

```swift
("The menu bar counts a break down by the minute, then the second", menuBarBreakText),
("The menu bar shows a break even with no session", menuBarIdleBreak),
// menuBarBreakText
expect(MenuBarDisplay.breakText(remaining: 299) == "5m", "rounds up minutes", &problems)
expect(MenuBarDisplay.breakText(remaining: 61) == "2m" && MenuBarDisplay.breakText(remaining: 60) == "60s", "seconds in the last minute", &problems)
expect(MenuBarDisplay.breakText(remaining: -30) == "Over" && MenuBarDisplay.breakText(remaining: -200) == "+3m", "overtime", &problems)
// menuBarIdleBreak: idle store, startBreak() → MenuBarDisplay(store).isOnBreak && breakText == "5m";
//   menuBarShowsBreakCountdown = false → breakText == nil, isOnBreak still true
```

- [ ] **Step 2: Verify they fail.**
- [ ] **Step 3: Implement.** Check that every new length is a token or
  `N.zoomed`; `build.sh` fails on bare lengths.
- [ ] **Step 4: Verify.** All checks pass. Run `./build.sh --run` with the
  sandbox disabled, **in a copy of the tree** per `CLAUDE.md` "Runtime probes",
  not on live data. Then confirm by eye:
  - the popover's Take a break → cup and "5m" in the menu bar
  - "+5 min" → "10m"
  - End break → the session resumes on the same thread
  - Today's row shows the break mode
  - ⌥⌘B toggles
  - VoiceOver (⌘F5) reads the HUD
- [ ] **Step 5: Commit.** Subject: "A running break shows its time left in the
  menu bar, the popover and Today".

---

### Task 9: Whole-branch verification and ship

- [ ] **Step 1:** Run `./build.sh --check 2>&1 | tail -3`. Expected: `N/N passed`
  and `Check succeeded`.
- [ ] **Step 2:** Run `TZ=Europe/Berlin ./build.sh --check 2>&1 | tail -3` and
  `TZ=Pacific/Kiritimati ./build.sh --check 2>&1 | tail -3`. Expected: the same
  counts.
- [ ] **Step 3: Mutation test**, in a `mktemp -d` copy of the tree:
  1. Make `startBreak` resume on any `.work` app (delete the `.onBreak`
     early-out). Confirm `workAppDoesNotEndBreak` fails.
  2. Make `expireBreakIfOutgrown` record `now()`. Confirm
     `forgottenBreakEndsAtCap` fails.
  3. Remove the folder when done.
- [ ] **Step 4:** Run `fix-reviewer` on the whole branch diff. Address its
  findings with checks.
- [ ] **Step 5:** Ship with the `ship` skill: check, merge into `main`, push,
  update the main checkout. Sir runs `./build.sh --install` himself.

## Not in this phase (spec phases 2–5)

- Rhythm presets, the weekday plan, overrides, working hours, Eyes and guard as
  settings, and the tier migration.
- Grace windows, breakpoints, holds, pause reminders, gentle dim, repeated-skip
  adaptation, and auto-recording a break taken after a prompt (`.prompted`).
- The menu bar due cue, "last break 38m ago", the Today break line, lunch, and
  the History, week, month and Ask figures.
- Suggestion lines and the copy pass.
- A running break shown as a row in Today's day story before it ends.
