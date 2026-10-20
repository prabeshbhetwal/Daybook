# Breaks, phase 2: Rhythm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The person chooses their break rhythm: a preset (Steady, Pomodoro,
Deep work, Flow) or their own numbers, per weekday, with overrides for today,
this week, this month or a date range, and optionally only inside working
hours. Eyes and the long-stretch guard replace the micro and ultradian tiers.
Old tier switches carry over once, each on its own. Settings splits into
Breaks and Away. The break log records the rhythm actually in force each day,
including "off".

**Architecture:** Core gains the rhythm vocabulary and every rule that has a
number in it:
- `BreakRhythm.swift`: presets, Custom, Flow's suggestion
- `BreakSchedule.swift`: weekday plan, overrides, working hours, and which plan
  is in force on a date
- `BreakPlan.swift`: the plan the reminder runs on at one moment, and its log
  snapshot
- `BreakCycles.swift`: Flow's per-stretch rest and Pomodoro's cycle count

`BreakReminder.evaluate` takes a `BreakPlan` instead of a tier list. The three
`BreakTier` cases stay as the identities of the three clocks (`.micro` = Eyes,
`.cognitive` = the main rhythm, `.ultradian` = the guard), so `BreakClock`,
`lastBreakNotice` and `break-log.json` keep their stored formats and an older
build still reads them. `PersistenceStore` stores the new settings and reads
the old tier key until each new key is first written. `SessionStore` resolves
the plan on each refresh. Settings gets its own Breaks page.

**Tech Stack:** Swift 5 mode, AppKit and SwiftUI, macOS 14. Built by `build.sh`
(no Xcode project). Tested by the headless self-check suite.

**Spec:** `docs/specs/2026-10-19-breaks-design.md`: §1 (Rhythm), §2 (credited
rest), §5 ("Rhythm in force"), §9 (Settings) and the Phasing list. Read them
beside this plan.

## Global Constraints

- **Layering:** Core, then App, then Design and Surfaces, one way only.
  `build.sh` typechecks `Sources/Core` alone.
- **`keep_internals`** (`build.sh:90-97`): new `@Published` `SessionStore`
  properties go in the store's second list; new store helpers not meant for
  views go in its first list.
- **Timers:** none new. Everything runs off `SessionStore`'s ticker
  (`refreshBreak` every `breakCheckSeconds`, 5 s).
- **Lengths** in App, Design and Surfaces are tokens or `N.zoomed`.
- **Checks:** `TestClock` or `SelfTest.anchoredNow()`, `SelfTest.scratchDirectory()`,
  `MemoryDefaults.suite(named: "fc-selftest-…")`; never `UserDefaults(suiteName:)`.
  Fixture dates come from an explicit calendar handed to the code under test
  (`Calendar(identifier: .gregorian)` with a set `timeZone` and
  `firstWeekday = 2`), never from `Date(timeIntervalSince1970:)`. Day
  arithmetic goes through `Calendar`. New suites go at the **end** of
  `registeredTests` (`SelfTest+Registry.swift:145-152`), in task order.
- **Every new check must fail on the old code** (or not compile against it,
  for a new type) and hold under `TZ=Europe/Berlin` as well as the default zone.
- **Preset numbers and copy** (spec §1, verbatim):

  | Preset | Work | Break | Long break | Evidence note |
  |---|---|---|---|---|
  | Steady (default) | 50 min | 5 min | none | "Close to HSE and OSHA guidance: 5 to 10 minutes an hour." |
  | Pomodoro | 25 min | 5 min | 15 min after 4 | "A popular fixed cadence. Studies find it about as good as choosing your own breaks." |
  | Deep work | 90 min | 15 min | none | "Longer blocks for focused work, with a proper reset." |
  | Flow | self-paced | 1/5 of the stretch, 5 to 20 min | none | "You decide when to stop; Daybook suggests a break length." |
  | Custom | 10 to 180 min | 1 to 30 min | optional, every 2 to 8 | none |

- **Add-ons:** Eyes every 20 min of use, default on, never within 5 min of a
  main break or guard coming due. Guard default 90 min, settable 60 to 180,
  default on; its Later is 15 min (`BreakClock.stretchGuardLaterLength`).
- **What resets what** (spec §1, §2):
  - **Credited rest:** a recorded break of at least `minimumRecordedSession`,
    or an off-screen gap of at least the rhythm's break length, never under
    `AppUsageTracker.idleCutoff` (3 min). Under Flow the gap must reach that
    stretch's suggestion. With no rhythm ("No reminders"), 5 min
    (`BreakLength.standard`).
  - **Main clock:** credited rest or Skip.
  - **Guard:** credited rest only, never Skip or Later.
  - **Eyes:** a gap of at least the idle cutoff, or credited rest.
  - **Pomodoro cycle:** a credited rest after at least one work length; the
    count returns to zero after any rest of at least the long-break length.
- **Copy rules** (spec "Copy rules"): never "boosts productivity", "optimal
  ratio", "90-minute brain cycle", "prevents eye damage", "willpower"; no
  claim that a preset is best; no streaks or guilt; offer, never instruct.
  Existing reminder wording stays except numbers that now come from the rhythm
  (the spec's new Eyes wording waits for phase 5's copy pass).
- **Old data:** `fc.breakTiersDisabled` is never written or removed (a
  phase-1 build reads it after a downgrade). New `Codable` fields decode with
  `decodeIfPresent`; unknown future enum strings decode leniently.
- **Commits:** subject is one plain present-tense sentence stating what is now
  true for the user, no type prefix; body is wrapped prose; end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (a subagent names
  its own model, per the phase-1 ruling).
- **fix-reviewer:** the controller runs the repo's `fix-reviewer` agent beside
  the task reviewer for Tasks 2, 3, 4, 5, 7 and 8 (time, persistence,
  settings, session state) and on the whole branch; its findings join the
  same fix loop.
- **Build:** `build.sh` runs with the Claude sandbox **disabled**. The
  sandbox-safe typecheck in `CLAUDE.md` is fine between steps.
- **Public repository:** no personal data in fixtures.

## Rulings made while planning (cost if wrong in brackets)

1. **The guard resets on a credited rest (5 min under Steady), not on a
   15-minute gap.** Spec §1 says so, and that someone taking the suggested
   breaks never sees it. Phase 1 needed 15 minutes. This is the one change a
   person who never touched settings will notice. A pre-existing check that
   fails only because of it is updated to the new rule and named in the task
   report. [The guard appears less often than before for Steady users.]
2. **Eyes is quiet while the main break or the guard is due or comes due
   within 5 minutes** (spec: "never fires within 5 minutes of a main break
   being due"). Under the old tiers a due deeper break already silenced it.
   [An eyes glance some people got at 46 to 49 minutes no longer shows.]
3. **A guard set at or past the rhythm's work block comes due no sooner than
   15 minutes after that block** (`guard < work ? guard : max(guard, work +
   15 min)`). Otherwise Deep work (90) and the default guard (90) collide:
   the guard would replace the main prompt, and a Skip at 90 would bring the
   guard a minute later. A guard set shorter than the block still comes
   first, as chosen. Steady and Pomodoro keep exactly 90. [Under Deep work the
   default guard is at 105, not the 90 shown; the Settings detail says so.]
4. **"No reminders" on a day turns off the main rhythm only.** The migration
   table says "(main rhythm only)", and Eyes and the guard have their own
   switches. The weekday plan's footnote says so. [Someone expecting a silent
   Sunday also turns Eyes and the guard off.]
5. **The migration is read-through.** Each new key (`fc.breakEyes`,
   `fc.breakGuard`, `fc.breakSchedule`), until it is first written, reads its
   value from `fc.breakTiersDisabled`; the first write fixes it. Nothing
   writes the old key any more, so the result cannot change under the person,
   no marker key is needed, and a downgrade then upgrade follows their latest
   phase-1 choice. Each tier maps on its own. [A phase-1 build after a
   downgrade does not see phase-2 choices.]
6. **Overrides: one per kind (today, this week, this month, dates), each
   stored as calendar days.** The narrowest span covering the day wins; a tie
   goes today, week, month, dates. Settings shows four override rows rather
   than the spec's single picker, because "the most specific wins" only means
   something when several can exist. [Four rows instead of one.]
7. **Custom's long break has its own length** (5 to 60 min, never shorter
   than the break, default 15), shown only when "every N" is on. The spec
   gives Pomodoro's 15 but nothing for Custom. [One more field.]
8. **Start break starts at the rhythm's length:** Steady 5, Pomodoro 5 (15 when
   the long break is next), Deep work 15, Custom its break, Flow its
   suggestion, a "No reminders" day 5. The guard offers `max(15 min, the
   rhythm's break)`, or Flow's suggestion. The 5/10/15/30 menu is unchanged.
   Flow's suggestion shows as that default and in the guard's title.
9. **`fc.workInterval`** is already gone (phase 1 removed the property and
   keeps the key only in `removeAll()`), so the second clean-up is just the
   `breakLength` rename.
10. **The working-hours window silences all three reminders outside it**, and
    a window whose start is after its end runs overnight (22:00 to 06:00). The
    clocks keep counting work, so a stretch begun before the window opens is
    due at its start.

## Review Focus

1. **A day boundary mid-stretch.** At 00:00 the plan becomes the next day's
   (a "No reminders" Saturday, a "Today" override expiring) without a
   relaunch, and the log gains that day's snapshot. → Task 5 check
   `planFollowsMidnight`.
2. **Changing the rhythm while a break is due or put off.** Steady → Deep work
   with a Later pending: no crash, no permanent silence, the next prompt uses
   Deep work's numbers. → Task 2 check `rhythmChangeUnderLater`.
3. **Downgrade safety.** A `BreakClock` with `credits` decodes in a decoder that
   does not know them, and a phase-1-shaped clock decodes in this build; a
   snapshot with new fields decodes as the phase-1 struct did. → Task 3 check
   `clockFormatsInterchange`, Task 2 check `snapshotDecodesBothWays`.
4. **Custom extremes.** 10/1 (break under the idle cutoff: rest needs 3 min;
   Eyes never fires because the main break is always within 5 min) and
   180/30 with guard 60 (guard first, at 60). → Task 2 check `customExtremes`.
5. **A daylight-saving day.** Working hours on Berlin's 25-hour 25 Oct 2026
   (02:30 happens twice) and a week override across it. → Task 1 check
   `workingHoursOnDaylightSavingDay`.

Work on the current branch (`claude/bold-merkle-98e960`, from `main` at a3b8417).

---

### Task 1: Rhythms, the weekday plan, overrides and working hours exist in Core

**Files:**
- Create: `Sources/Core/BreakRhythm.swift`, `Sources/Core/BreakSchedule.swift`
- Test: `Sources/Verification/BreakRhythmChecks.swift` (new suite, registered at the end)

**Interfaces:**
- Produces (`BreakRhythm.swift`):
  - `enum BreakPreset: String, Codable, CaseIterable { case steady, pomodoro, deepWork, flow, custom }`
    with `var title: String` ("Steady", "Pomodoro", "Deep work", "Flow", "Custom")
    and `var evidenceNote: String?` (table above; nil for Custom).
  - `struct CustomRhythm: Codable, Equatable { var workMinutes = 50; var breakMinutes = 5; var longEvery: Int? = nil; var longMinutes = 15; func clamped() -> CustomRhythm }`
    (work 10…180, break 1…30, longEvery nil or 2…8, longMinutes breakMinutes…60).
  - `struct BreakRhythm: Equatable { let preset: BreakPreset; let work: TimeInterval?; let breakLength: TimeInterval?; let longEvery: Int?; let longLength: TimeInterval?; init(_ preset: BreakPreset, custom: CustomRhythm = CustomRhythm()) }`
    (`work` and `breakLength` nil only for Flow).
  - `static func BreakRhythm.flowSuggestion(after stretch: TimeInterval) -> TimeInterval`,
    with `flowShare = 0.2`, `flowShortest: TimeInterval = 300`, `flowLongest: TimeInterval = 1_200`.
- Produces (`BreakSchedule.swift`):
  - `struct CalendarDay: Codable, Hashable, Comparable { let year, month, day: Int; init(_ date: Date, calendar: Calendar); func start(in calendar: Calendar) -> Date? }`
  - `enum BreakDayPlan: Hashable, Codable { case usual, preset(BreakPreset), off }`, coded as one
    string ("usual", "off" or a preset's raw value); an unknown string decodes as `.usual`.
  - `enum BreakOverrideKind: String, Codable, CaseIterable { case today, week, month, range }` (declaration order is the tie order).
  - `struct BreakOverride: Codable, Equatable { let kind: BreakOverrideKind; let first: CalendarDay; let last: CalendarDay; let plan: BreakDayPlan }`
  - `struct WorkingHours: Codable, Equatable { var fromMinute: Int; var toMinute: Int; func contains(_ date: Date, calendar: Calendar) -> Bool }`
    (minutes after local midnight from `calendar.dateComponents([.hour, .minute])`; `from > to` runs overnight; `from == to` is the whole day).
  - `struct BreakSchedule: Codable, Equatable` with `var rhythm: BreakPreset = .steady`, `var custom = CustomRhythm()`,
    `var weekdays: [BreakDayPlan] = Array(repeating: .usual, count: 7)` (index = `calendar.component(.weekday) - 1`, Sunday first),
    `var overrides: [BreakOverride] = []`, `var workingHours: WorkingHours? = nil`;
    a hand-written `init(from:)` that reads every field with `decodeIfPresent` and its default, and decodes an unknown `rhythm` as `.steady` and a `weekdays` array of the wrong length as the default.
  - `func BreakSchedule.override(on date: Date, calendar: Calendar) -> BreakOverride?` (narrowest covering span, then kind order).
  - `func BreakSchedule.preset(on date: Date, calendar: Calendar) -> (preset: BreakPreset?, override: BreakOverrideKind?)`
    (`preset` nil means "No reminders"; `.usual` resolves to `rhythm`).
  - `mutating func BreakSchedule.setOverride(_ kind: BreakOverrideKind, plan: BreakDayPlan, covering date: Date, through end: Date? = nil, calendar: Calendar)`:
    replaces that kind's override; `.usual` removes it. Today: that day. Week: `calendar.dateInterval(of: .weekOfYear, for:)`.
    Month: `dateInterval(of: .month)`. Range: `date` to `end`, swapped if reversed.

- [ ] **Step 1: Write the failing checks** in `enum BreakRhythmChecks: CheckSuite`

```swift
("Each preset has the spec's numbers and evidence note", presetsHaveTheirNumbers),
("Custom numbers stay inside their ranges", customIsClamped),
("Flow suggests a fifth of the stretch, between 5 and 20 minutes", flowSuggestsAFifth),
("The weekday plan picks each day's rhythm", weekdayPlanPicksTheDay),
("The narrowest override covering a day wins", narrowestOverrideWins),
("Working hours hold overnight and in any zone", workingHoursHold),
("Working hours hold on a daylight-saving day", workingHoursOnDaylightSavingDay),
("A schedule from another build still reads", scheduleDecodesLeniently),

// presetsHaveTheirNumbers
expect(BreakRhythm(.steady).work == 3_000 && BreakRhythm(.steady).breakLength == 300 && BreakRhythm(.steady).longEvery == nil, …)
expect(BreakRhythm(.pomodoro).work == 1_500 && …breakLength == 300 && …longEvery == 4 && …longLength == 900, …)
expect(BreakRhythm(.deepWork).work == 5_400 && …breakLength == 900, …)
expect(BreakRhythm(.flow).work == nil && BreakRhythm(.flow).breakLength == nil, …)
expect(BreakPreset.steady.evidenceNote == "Close to HSE and OSHA guidance: 5 to 10 minutes an hour.", …) // and the other three verbatim; custom nil
// customIsClamped
let c = CustomRhythm(workMinutes: 5, breakMinutes: 45, longEvery: 12, longMinutes: 2).clamped()
expect(c == CustomRhythm(workMinutes: 10, breakMinutes: 30, longEvery: 8, longMinutes: 30), …)
expect(CustomRhythm(longEvery: 1).clamped().longEvery == 2 && CustomRhythm().clamped().longEvery == nil, …)
expect(BreakRhythm(.custom, custom: CustomRhythm(workMinutes: 40, breakMinutes: 8, longEvery: 3, longMinutes: 20)).longLength == 1_200, …)
// flowSuggestsAFifth
expect(BreakRhythm.flowSuggestion(after: 1_800) == 360 && …(after: 600) == 300 && …(after: 9_000) == 1_200 && …(after: 3_600) == 720, …)
// Fixtures: var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!; cal.firstWeekday = 2
// day(2026, 10, 21, hour) = cal.date(from: DateComponents(year:month:day:hour:)) — Wednesday 21 Oct 2026
// weekdayPlanPicksTheDay: weekdays[3] = .off (Wednesday), weekdays[4] = .preset(.pomodoro); rhythm = .deepWork
expect(s.preset(on: day(2026,10,21,10), calendar: cal).preset == nil, "Wednesday is No reminders", …)
expect(s.preset(on: day(2026,10,22,10), calendar: cal).preset == .pomodoro, …)
expect(s.preset(on: day(2026,10,23,10), calendar: cal).preset == .deepWork, "usual follows the rhythm", …)
expect(BreakSchedule().preset(on: day(2026,10,24,10), calendar: cal).preset == .steady, "every day is Steady by default", …)
// narrowestOverrideWins: setOverride(.month, .preset(.pomodoro), covering: 21 Oct); (.week, .preset(.deepWork), covering: 21 Oct);
// (.range, .preset(.flow), covering: 20 Oct, through: 22 Oct); (.today, .off, covering: 21 Oct)
expect(preset(21 Oct) == (nil, .today) && preset(22 Oct) == (.flow, .range) && preset(24 Oct) == (.deepWork, .week)
       && preset(28 Oct) == (.pomodoro, .month) && preset(2 Nov).override == nil, …)
// a range of exactly the week (19–25 Oct) on 23 Oct loses to the week override (tie → kind order)
// a 61-day range (1 Oct – 30 Nov) on 28 Oct loses to the month override
// setOverride(.week, plan: .usual, …) removes it; a reversed range (22 → 20 Oct) is stored 20 → 22
// workingHoursHold: WorkingHours(fromMinute: 480, toMinute: 1_080) contains 10:00, not 07:59, not 18:00;
// WorkingHours(fromMinute: 1_320, toMinute: 360) contains 23:30 and 05:59, not 06:00 or 12:00;
// repeat both with cal.timeZone = Pacific/Kiritimati and America/Los_Angeles built from the same components
// workingHoursOnDaylightSavingDay: Berlin 25 Oct 2026; 08:00–18:00 contains 10:00, and 02:30 (either occurrence:
// cal.date(from:) and that date + 3_600 s) is outside; a week override set on 21 Oct still covers 25 Oct and not 26 Oct
// scheduleDecodesLeniently: decode {"rhythm":"siesta","weekdays":["usual","nap","off","usual","usual","usual","usual"]}
expect(decoded.rhythm == .steady && decoded.weekdays[1] == .usual && decoded.weekdays[2] == .off && decoded.overrides.isEmpty, …)
expect(try? JSONDecoder().decode(BreakSchedule.self, from: Data("{}".utf8)) == BreakSchedule(), "an empty object reads as the defaults", …)
// round trip of a schedule with every field set is equal
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check` (sandbox disabled). Expected: compile error, the types do not exist.
- [ ] **Step 3: Implement** the two files to the interfaces above. `CalendarDay.start(in:)` is `calendar.date(from:)` of the three components (some zones skip midnight; the date is that day's first moment). Span length for "narrowest" is `calendar.dateComponents([.day], from: first.start, to: last.start).day + 1`.
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Commit** — "Daybook knows the break presets, a weekday plan, overrides and working hours".

---

### Task 2: Reminders follow a plan, with Eyes and the long-stretch guard

**Files:**
- Create: `Sources/Core/BreakPlan.swift`, `Sources/Core/BreakCycles.swift` (Flow's run only in this task), `Sources/Core/BreakPrompt.swift` (`BreakPrompt` and `BreakNotice` move here unchanged first, then gain the fields below)
- Modify: `Sources/Core/BreakReminder.swift` (`evaluate`, `prompt`, tier doc comments: `.micro` is Eyes, `.cognitive` the main rhythm, `.ultradian` the guard, and their numbers are Steady's defaults), `Sources/Core/BreakLog.swift` (`BreakRhythmSnapshot`, `noteEyesPrompt` fallback)
- Modify (callers, minimal): `Sources/App/SessionStore+Breaks.swift` (pass `plan: BreakPlan(tiers: engine.store.enabledBreakTiers)`; `logShown` uses `prompt.kind` and `prompt.threshold`), `Sources/App/SessionStore+BreakActions.swift:20-22` (a prompt's length is `prompt.breakLength`, eyes → `BreakLength.standard`)
- Modify (checks that pass `tiers:` or re-derive the rule): `Sources/Verification/BreakClockChecks.swift:122-130`, `Sources/Verification/EfficiencyChecks.swift:224-269`
- Test: `Sources/Verification/BreakPlanChecks.swift` (new suite)

**Interfaces:**
- Consumes: Task 1's `BreakRhythm`, `BreakSchedule`, `BreakOverrideKind`.
- Produces (`BreakPlan.swift`):
  - `struct BreakPlan: Equatable { var rhythm: BreakRhythm?; var eyes: Bool; var guardLength: TimeInterval?; var override: BreakOverrideKind? }`
  - `static let BreakPlan.standard` = Steady, eyes on, guard 5 400 s, no override.
  - `static let eyesInterval: TimeInterval = 1_200`, `eyesQuietBefore: TimeInterval = 300`, `guardRange = 60...180` (minutes), `defaultGuardMinutes = 90`, `guardBreak: TimeInterval = 900`, `guardAfterWork: TimeInterval = 900` (ruling 3).
  - `init(tiers: Set<BreakTier>)`: `.micro` → eyes, `.cognitive` → Steady, `.ultradian` → guard 90 (the migration table; tests and the phase-1 store path use it).
  - `static func resolve(schedule: BreakSchedule, eyes: Bool, guardMinutes: Int?, on moment: Date, calendar: Calendar) -> BreakPlan`
  - `var tiers: [BreakTier]` (enabled, shallowest first); `func workLength(_ tier: BreakTier) -> TimeInterval?`
    (micro 1 200; cognitive `rhythm?.work`; ultradian: with a fixed work block `w`, `guard < w ? guard : max(guard, w + guardAfterWork)`, else `guard`).
  - `var creditGap: TimeInterval?`: `max(rhythm?.breakLength ?? BreakLength.standard, AppUsageTracker.idleCutoff)`; nil under Flow.
  - `var snapshot: BreakRhythmSnapshot`.
- Produces (`BreakCycles.swift`): `static func BreakCycles.flowRun(_ ordered: [AppUsageSession], now: Date) -> (seconds: TimeInterval, start: Date?)`
  — `ordered` newest end first, already clipped; work since the last gap that reached `flowSuggestion` of the work before it.
- Produces (`BreakReminder.swift`):
  - `static func evaluate(_ stretches:, now:, last:, plan: BreakPlan = .standard, clock: BreakClock = BreakClock()) -> Evaluation` (replaces `tiers:`).
  - `Evaluation.breakLength: TimeInterval` — what Start break would begin with now (ruling 8; Task 3 adds the long break).
  - `BreakPrompt` gains `var isLong = false`, `var dueAfterWork: TimeInterval? = nil`, `var offeredBreak: TimeInterval? = nil`, and computed
    `kind: BreakPromptKind` (`.long` when `isLong`, else `.of(tier)`), `threshold` (`dueAfterWork ?? tier.workThreshold`),
    `breakLength` (`offeredBreak ?? tier.breakLength`). `title`: eyes `tier.title`; main and long "Take N minutes"
    ("Take 1 minute" for one); guard "Step away for N minutes". Minutes are whole and rounded.
- Produces (`BreakLog.swift`): `BreakRhythmSnapshot` gains, after `override` and in this order, `var preset: String?`, `var longEvery: Int?`, `var longMinutes: Int?`
  (preset is a `BreakPreset` raw value or `"off"`; nil means written by phase 1); `static let off` (preset "off", eyes false, everything else nil);
  `fromTiers` stays until Task 5 and returns `BreakPlan(tiers:).snapshot`. `noteEyesPrompt`'s fallback becomes `BreakRhythmSnapshot(eyes: true)`.

Inside `evaluate`, each enabled tier uses `workLength(tier)` and a rest rule: micro the idle cutoff; cognitive `creditGap`; ultradian `creditGap`, or
`BreakCycles.flowRun` under Flow (clipped at `floors[.ultradian]`). `latestRun`'s reach is the largest rest in play (Flow: `flowLongest`).
Repeat suppression compares with `workLength(tier)`, not `tier.workThreshold`. An eyes prompt is dropped when a main or guard tier is
due, or has `remaining <= eyesQuietBefore`. Prompts carry `dueAfterWork`, `offeredBreak` (main: the rhythm's break; guard: `max(guardBreak,
rhythm break)`, Flow: `flowSuggestion` of the guard run; eyes: tier default).

- [ ] **Step 1: Write the failing checks** in `enum BreakPlanChecks: CheckSuite` (stretches as in `testBreakTiers`: one run ending at `now`)

```swift
("Someone who never touched settings gets the same three reminders", standardPlanMatchesTiers),
("The guard resets on a credited rest, never on Skip", guardResetsOnCreditedRest),
("Eyes stays quiet within 5 minutes of a main break", eyesQuietNearMainBreak),
("Pomodoro, Deep work and Custom prompt at their own numbers", presetsPromptAtTheirNumbers),
("Flow has no main prompt, and its guard offers a fifth of the stretch", flowPromptsOnlyTheGuard),
("A Flow rest counts when it reaches the suggestion", flowRestReachesSuggestion),
("The guard follows a long main block rather than racing it", guardFollowsLongBlock),
("No reminders turns off the main rhythm only", noRemindersKeepsAddOns),
("A repeat waits for the plan's own work length", repeatWaitsForPlanLength),
("Changing the rhythm under a Later neither crashes nor silences", rhythmChangeUnderLater),
("Custom extremes behave", customExtremes),
("The plan's snapshot names the rhythm, and off is off", snapshotNamesRhythm),
("A rhythm snapshot reads in both directions", snapshotDecodesBothWays),

// standardPlanMatchesTiers — evaluate(plan: .standard)
expect(due(19) == nil && due(21) == .micro && due(51) == .cognitive && due(91) == .ultradian, …)
expect(prompt(21)?.title == "Look away for 30 seconds" && prompt(51)?.title == "Take 5 minutes" && prompt(91)?.title == "Step away for 15 minutes", …)
expect(prompt(51)?.breakLength == 300 && prompt(91)?.breakLength == 900 && prompt(51)?.kind == .main && prompt(91)?.kind == .stretchGuard, …)
// guardResetsOnCreditedRest: 60 min work, a 6-min gap, 40 min work to now (Steady)
expect(eval.due == .micro, "a 6-minute gap is a credited rest, so the guard is not due (old: .ultradian)", …)
// 95 min unbroken, clock.skip(.ultradian, at: now - 60): still .ultradian
// eyesQuietNearMainBreak: Pomodoro, 21 min unbroken → due .micro but prompt == nil (main due in 4 min);
// Steady, 41 min → eyes prompt shown; Steady, 46 min with last = (micro, now - 1_300) → prompt == nil
// presetsPromptAtTheirNumbers: Pomodoro 24 min → due != .cognitive; 26 → .cognitive, threshold 1_500, breakLength 300;
// Deep work 91 → .cognitive (not the guard), title "Take 15 minutes", breakLength 900;
// Custom 40/8 at 41 → .cognitive, breakLength 480, title "Take 8 minutes"
// flowPromptsOnlyTheGuard: Flow, 200 min unbroken → due == .ultradian, prompt.breakLength == 1_200, title "Step away for 20 minutes";
// Flow, 60 min → due is nil or .micro, never .cognitive; eval.breakLength == 720
// flowRestReachesSuggestion: Flow; 60 min work, gap, 40 min work to now; guard 90
// gap 10 min (suggestion 12) → guard due (100 ≥ 90); gap 12 min → not due
// guardFollowsLongBlock: Deep work, guard 90: due(91) == .cognitive, due(104) == .cognitive, due(106) == .ultradian;
// Steady, guard 90: due(91) == .ultradian (unchanged); Deep work, skip(.cognitive) at 90 → at 95 due != .ultradian
// noRemindersKeepsAddOns: plan(rhythm: nil, eyes: true, guard: 5_400): due(51) == .micro, due(91) == .ultradian, never .cognitive;
// creditGap == 300; eval.breakLength == 300
// repeatWaitsForPlanLength: Pomodoro, 30 min, last = (cognitive, now - 1_560) → prompt != nil (26 min ≥ 25);
// Steady, 55 min, the same last → nil (26 min < 50)
// rhythmChangeUnderLater: Steady 55 min, clock.later(.cognitive, at: now - 120); evaluate under Deep work (main not due) →
// prompt?.tier != .cognitive and result.clock.snooze == nil; then 92 min under Deep work → prompt is .cognitive with breakLength 900
// customExtremes: Custom 10/1 → creditGap == 180; 4 min, a 2-min gap, 7 min to now → due == .cognitive (the gap is no rest);
// 21 min unbroken → due == .cognitive (Eyes never prompts while the main block is shorter than 20 min);
// Custom 180/30 with guard 60 → due(61) == .ultradian (a shorter guard comes first), due(59) == .micro
// snapshotNamesRhythm
expect(BreakPlan.standard.snapshot == BreakRhythmSnapshot(workMinutes: 50, breakMinutes: 5, eyes: true, guardMinutes: 90, override: nil, preset: "steady"), …)
expect(BreakPlan(rhythm: BreakRhythm(.pomodoro), eyes: false, guardLength: nil, override: .week).snapshot.longEvery == 4 && …longMinutes == 15 && …override == "week", …)
expect(BreakPlan(rhythm: nil, eyes: true, guardLength: 5_400, override: nil).snapshot.preset == "off", …)
expect(BreakPlan(rhythm: BreakRhythm(.flow), …).snapshot.workMinutes == nil && .preset == "flow", …)
expect(BreakRhythmSnapshot.off == BreakRhythmSnapshot(eyes: false, preset: "off"), …)
// snapshotDecodesBothWays: phase-1 JSON {"workMinutes":50,"breakMinutes":5,"eyes":true,"guardMinutes":90} decodes with preset nil;
// a new snapshot encodes and decodes in a struct with only the phase-1 fields (declare it locally in the check)
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check`. Expected: compile errors (`plan:`, `BreakPlan`), and once compiling, `guardResetsOnCreditedRest`, `eyesQuietNearMainBreak`, `guardFollowsLongBlock` fail on the old rules.
- [ ] **Step 3: Implement** `BreakPlan.swift`, `BreakCycles.flowRun`, the `evaluate`/`prompt` changes and the snapshot fields. `flowRun`: take the run back to the first gap of at least `flowLongest`, then walk it oldest first, resetting the sum at each gap that reaches `flowSuggestion(after:)` of the sum before it, and finally test the gap from the last stretch to `now` the same way.
- [ ] **Step 4: Update** the three `tiers:` call sites in `BreakClockChecks` to `plan: BreakPlan(tiers: …)`, and `EfficiencyChecks`' reference walk to the plan's rest rule. Run the suite; any other failing pre-existing check that fails only because of rulings 1–3 is updated and named in the report; anything else is a regression to fix.
- [ ] **Step 5: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 6: Commit** — "Break reminders follow a rhythm, and the long-stretch guard resets on a real rest".

---

### Task 3: Pomodoro offers its long break after every fourth cycle

**Files:**
- Modify: `Sources/Core/BreakClock.swift` (`credits`, `credit`, `sanitized`, hand-written `init(from:)`), `Sources/Core/BreakCycles.swift` (`completedCycles`), `Sources/Core/BreakReminder.swift` (long prompt and `Evaluation.breakLength`)
- Test: `Sources/Verification/BreakCycleChecks.swift` (new suite)

**Interfaces:**
- Consumes: Task 2's `BreakPlan`, `BreakRhythm.longEvery/longLength`, `Evaluation.breakLength`, `BreakPrompt.isLong`.
- Produces:
  - `BreakClock.credits: [Date]` — every credited-rest moment, appended by `credit(at:)`, kept sorted, trimmed to `BreakReminder.runLookback` before the newest and to at most 32; `sanitized(now:)` drops future ones and clamps a snooze count into `0...maxLaters` (ledger line 88). Decoded with `decodeIfPresent` (default `[]`); `floors` and `snooze` decode exactly as now.
  - `static func BreakCycles.completedCycles(_ ordered: [AppUsageSession], now: Date, credits: [Date], work: TimeInterval, rest: TimeInterval, longRest: TimeInterval) -> Int`:
    over the run back to the first gap of at least `longRest`, oldest first: a gap is a credited rest when it reaches `rest` or a credit lies within it (inclusive); each credited rest after at least `work` of work since the previous one is a cycle; the gap from the last stretch to `now` counts the same way.
  - Under a rhythm with `longEvery`, when `completedCycles >= longEvery - 1`: the main prompt has `isLong = true` and `offeredBreak = longLength`, and `Evaluation.breakLength == longLength`.

- [ ] **Step 1: Write the failing checks** in `enum BreakCycleChecks: CheckSuite` (Pomodoro; four blocks are 26 min of work each, separated by gaps)

```swift
("The fourth Pomodoro break is the long one", fourthBreakIsLong),
("A long rest taken early starts the count again", longRestResetsCount),
("Skip is not a cycle, and a short block is not one", skipAndShortBlockAreNotCycles),
("A break ended early still counts as a cycle", endedBreakCounts),
("Break clocks read across builds", clockFormatsInterchange),

// fourthBreakIsLong: blocks 1–3 each followed by a 6-min gap, block 4 (26 min) running to now
expect(prompt?.isLong == true && prompt?.kind == .long && prompt?.breakLength == 900 && prompt?.title == "Take 15 minutes" && eval.breakLength == 900, …)
// after only two finished blocks: isLong == false, breakLength == 300
// longRestResetsCount: block 1, 6-min gap, block 2, 16-min gap, block 3, 6-min gap, block 4 to now → completedCycles == 1, not long
// skipAndShortBlockAreNotCycles: blocks 1–3 separated by clock.skip(.cognitive) moments (no gaps) → completedCycles == 0;
// a 10-min block between two 6-min gaps adds no cycle
// endedBreakCounts: block 1, then a 2-min gap containing a credit (clock.credit(at:) at its end), blocks 2–3 with 6-min gaps,
// block 4 to now → long; without the credit → not long
// clockFormatsInterchange: phase-1 JSON of a clock (encode a BreakClock with floors and a snooze, strip "credits") decodes with credits == [];
// a clock with credits decodes in a local struct holding only floors and snooze; credits older than a day are dropped on the next credit,
// a credit in the future is dropped by sanitized(now:), and a decoded snooze count of -3 reads as 0 after sanitized(now:)
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check`. Expected: compile errors, then `fourthBreakIsLong` and `endedBreakCounts` fail.
- [ ] **Step 3: Implement** `credits`, `completedCycles` and the long-break branch. `latestRun`'s reach includes `longLength` when the rhythm has one.
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Commit** — "Pomodoro offers a 15-minute break after every fourth cycle".

---

### Task 4: The rhythm settings are stored, the old tiers carry over, and the auto-session limit has its own name

**Files:**
- Modify: `Sources/Core/PersistenceStore.swift` (keys, accessors, `removeAll()`), `Sources/Core/SessionState.swift:679-684`, `Sources/Core/AutoSessionDetector.swift:25,58-59,192`, `Sources/App/AppCoordinator.swift:105,188`, `Sources/App/SettingsModel.swift:73,553-556`, `Sources/Surfaces/Settings/SettingsGroups.swift:445-449`
- Modify (checks): `Sources/Verification/StorySettingsChecks.swift:81,97`, `Sources/Verification/SelfTest/SelfTest+AppearanceAndSettings.swift:158-159`
- Test: `Sources/Verification/BreakSettingsChecks.swift` (new suite)

**Interfaces:**
- Consumes: Task 1's `BreakSchedule`; Task 2's `BreakPlan.guardRange`, `defaultGuardMinutes`.
- Produces (`PersistenceStore`):
  - Keys `fc.breakSchedule` (JSON via `decode`, so an unreadable value is set aside), `fc.breakEyes` (Bool), `fc.breakGuard` (Bool), `fc.breakGuardMinutes` (Int), all in `removeAll()`.
  - `var breakSchedule: BreakSchedule` — absent: `BreakSchedule()`, with every weekday `.off` when the old key turns `.cognitive` off.
  - `var breakEyes: Bool` — absent: `.micro` not in the old key's list.
  - `var breakGuardEnabled: Bool` — absent: `.ultradian` not in the old key's list.
  - `var breakGuardMinutes: Int` — absent: 90; clamped to `BreakPlan.guardRange` on read and write.
  - `var legacyDisabledBreakTiers: Set<BreakTier>` (read-only, from `fc.breakTiersDisabled`). `enabledBreakTiers` stays until Task 6.
  - Rename `breakLength` → `autoSessionPauseLimit` (key stays `fc.breakLength`), `FocusConstants.defaultBreakLength` → `defaultAutoSessionPauseLimit`, `breakLengthOptions` → `autoSessionPauseLimitOptions`, `AutoSessionDetector.breakLength` → `autoSessionPauseLimit`, `SettingsModel.breakLength` → `autoSessionPauseLimit`.

- [ ] **Step 1: Write the failing checks** in `enum BreakSettingsChecks: CheckSuite` (each on its own `MemoryDefaults` suite, removed at the end)

```swift
("Each old tier switch carries over on its own", eachTierMapsAlone),
("A carried-over setting stays once it is changed", writtenSettingWins),
("A Mac that never changed a tier gets the default rhythm", freshDefaults),
("An unreadable schedule is kept aside and reads as the default", unreadableScheduleKept),
("The guard stays between 60 and 180 minutes", guardMinutesClamped),
("End a paused automatic session after keeps its stored value", pauseLimitKeepsItsKey),

// eachTierMapsAlone: for every subset of [.micro, .cognitive, .ultradian] written raw to "fc.breakTiersDisabled" as [Int]
expect(store.breakEyes == !off.contains(.micro), …)
expect(store.breakGuardEnabled == !off.contains(.ultradian), …)
expect(store.breakSchedule.weekdays == Array(repeating: off.contains(.cognitive) ? .off : .usual, count: 7), …)
expect(store.breakSchedule.rhythm == .steady && store.breakGuardMinutes == 90, …)
// writtenSettingWins: old key [0] (micro off) → breakEyes false; set breakEyes = true; rewrite old key [0, 1, 2] → breakEyes still true,
// breakGuardEnabled now false (not yet written), and the old key's value is unchanged after the writes
// freshDefaults: no keys → breakSchedule == BreakSchedule(), breakEyes, breakGuardEnabled, breakGuardMinutes == 90
// unreadableScheduleKept: raw Data("not json".utf8) under fc.breakSchedule → reads BreakSchedule(); a key with prefix "fc.breakSchedule.unreadable." holds the bytes
// guardMinutesClamped: write 30 → reads 60; write 500 → reads 180; raw 45 stored by hand → reads 60
// pauseLimitKeepsItsKey: raw 1_200.0 under "fc.breakLength" → store.autoSessionPauseLimit == 1_200; writing 1_800 lands under "fc.breakLength"
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check`. Expected: compile errors for the new accessors and the renamed property.
- [ ] **Step 3: Implement** the accessors next to `breakClock` in `PersistenceStore.swift` (the `Key` enum and `decode` are private there), then the rename across the files listed. Update the two checks to the new name.
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass, and `grep -rnE 'store\.breakLength|model\.breakLength|detector\.breakLength|defaultBreakLength|breakLengthOptions' Sources` prints nothing.
- [ ] **Step 5: Commit** — "Your break rhythm settings are saved, and earlier reminder choices carry over".

---

### Task 5: SessionStore reminds on the rhythm in force and logs it every day

**Files:**
- Modify: `Sources/App/SessionStore+Breaks.swift` (`refreshBreak`, `breakLabel`, new `currentBreakPlan(at:)`), `Sources/App/SessionStore+BreakActions.swift` (`startBreak` default length), `Sources/App/SessionStore.swift:262-265` (published state), `Sources/Core/BreakLog.swift` (remove `fromTiers`), `Sources/Surfaces/Focus/FocusBreakViews.swift:30` and `Sources/App/BreakCountdown.swift:46-48` (default minutes and comments), `build.sh:96-97` (keep_internals lists)
- Test: `Sources/Verification/BreakRhythmStoreChecks.swift` (new suite)

**Interfaces:**
- Consumes: `BreakPlan.resolve`, `Evaluation.breakLength`, `BreakPlan.snapshot`, `BreakRhythmSnapshot.off`, Task 4's accessors, `periodCalendar`.
- Produces:
  - `func currentBreakPlan(at moment: Date) -> BreakPlan` (from `engine.store.breakSchedule`, `breakEyes`, `breakGuardEnabled ? breakGuardMinutes : nil`, `periodCalendar`).
  - `@Published var suggestedBreakLength: TimeInterval = BreakLength.standard` — the evaluation's `breakLength` when it ran, else the plan's fixed length (`rhythm?.breakLength ?? BreakLength.standard`).
  - `@Published var isOutsideWorkingHours = false`; `breakLabel` reads "Outside working hours" when it is set (after "Reminders off" and the category pause).
  - `startBreak(length:label:from:)`: `length ?? prompt.map { $0.kind == .eyes ? suggestedBreakLength : $0.breakLength } ?? suggestedBreakLength`.

`refreshBreak` order: resolve the plan; write `breakLog.noteRhythm(remindersEnabled ? plan.snapshot : .off, on: moment)` **before** the guard (phase-1 ledger: the day's rhythm was only written past it, and "off" had no form); set `suggestedBreakLength`; then the existing guard, which now also stops outside working hours (setting `isOutsideWorkingHours`); then `evaluate(plan:)`.

- [ ] **Step 1: Write the failing checks** in `enum BreakRhythmStoreChecks: CheckSuite` (store built as in `BreakStoreLogChecks`, a `TestClock`, `periodCalendarBase` set to the Berlin fixture calendar, usage fed through the existing fixture helpers)

```swift
("The day's rhythm is logged even with reminders off or on a break", rhythmLoggedWhateverTheState),
("A settings change rewrites today's rhythm", settingsChangeRewritesToday),
("The plan follows midnight without a relaunch", planFollowsMidnight),
("A No reminders weekday has no main prompt, and Eyes and the guard still run", noRemindersWeekday),
("Today's override prompts at its own rhythm", todayOverridePrompts),
("Outside working hours nothing prompts, and the label says why", outsideWorkingHoursIsQuiet),
("Start break begins at the rhythm's length", startBreakUsesRhythmLength),
("A long Pomodoro prompt is logged as the long kind", longPromptLogged),

// rhythmLoggedWhateverTheState: remindersEnabled = false → breakLog.days.last?.rhythm == .off;
// on a break (startBreak) with reminders on → today's day exists with preset "steady"
// settingsChangeRewritesToday: Steady logged; breakSchedule.rhythm = .pomodoro; refreshBreak → same day, preset "pomodoro", one day entry
// planFollowsMidnight: Wednesday .off, Thursday usual (Steady); clock at Wed 23:50 with 55 min of unbroken work →
// onBreakDue never sees .cognitive (old code prompts here); advance to Thu 00:00:05 with work continuing → a .cognitive prompt;
// breakLog.days holds both dates, Wednesday's preset "off" and Thursday's "steady"
// noRemindersWeekday: today .off, eyes and guard on; 51 min → no .cognitive prompt; 95 min → .ultradian prompt
// todayOverridePrompts: setOverride(.today, .preset(.pomodoro), covering: now) → 26 min of work prompts .cognitive with breakLength 300
// outsideWorkingHoursIsQuiet: WorkingHours 08:00–18:00, clock 19:00, 60 min work → no prompt, isOutsideWorkingHours, breakLabel == "Outside working hours";
// clock 08:00 next day after work since 07:00 → prompt
// startBreakUsesRhythmLength: Deep work → startBreak() → activeBreak planned length 900; Flow with 40 min of work → 480;
// startBreak(length: 600) → 600
// longPromptLogged: Pomodoro, three finished blocks, fourth due → breakLog.prompts.last?.kind == .long
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check`. Expected: `rhythmLoggedWhateverTheState` and `planFollowsMidnight` fail on the phase-1 guard; the rest fail to compile.
- [ ] **Step 3: Implement** the store changes; delete `BreakRhythmSnapshot.fromTiers` and its last caller; add `suggestedBreakLength` and `isOutsideWorkingHours` to the store's published list in `build.sh`; `FocusTakeBreakMenu.minutes` reads `store.suggestedBreakLength`.
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Commit** — "Reminders follow the rhythm planned for the day, and every day's rhythm is recorded".

---

### Task 6: Settings has a Breaks page and an Away page

**Files:**
- Create: `Sources/App/SettingsModel+Breaks.swift`, `Sources/Surfaces/Settings/SettingsGroups+Breaks.swift`
- Modify: `Sources/App/SettingsModel.swift` (`write` becomes internal; `now`/`calendar` init parameters; control keys), `Sources/Surfaces/Settings/SettingsSidebar.swift` (pages, sections, labels, keys), `Sources/Surfaces/Settings/SettingsGroups.swift:29,356-399` (dispatch; Breaks panel leaves `away`), `Sources/Core/PersistenceStore.swift` (remove the `enabledBreakTiers` setter and property)
- Test: `Sources/Verification/BreakSettingsPageChecks.swift` (new suite)

**Interfaces:**
- Consumes: Tasks 1, 2 and 4.
- Produces:
  - `SettingsPage`: `.awayAndBreaks` becomes `.breaks` ("Breaks", `cup.and.saucer`) and `.away` ("Away", `moon.zzz`); `SettingsSection` gains `.breaks`. Breaks keys: `.reminders, .breakRhythm, .breakWeekdays, .breakOverrides, .workingHours, .breakEyes, .breakGuard, .breakOverSound, .menuBarShowsBreakCountdown`. Away keeps the five away rows and the agent rows. `.breakTiers` is removed.
  - `SettingsModel` init gains `now: @escaping () -> Date = Date.init` and `calendar: @escaping () -> Calendar = { Calendar.current.forPeriods }` (read on each use, so a time-zone change is followed).
  - `SettingsModel+Breaks`: `breakSchedule: BreakSchedule`, `customRhythm: CustomRhythm` (writes `clamped()`), `breakEyes: Bool`, `breakGuardEnabled: Bool`, `breakGuardMinutes: Int`,
    `func breakOverridePlan(_ kind: BreakOverrideKind) -> BreakDayPlan` (`.usual` when none covers today; a range shows until its last day),
    `func setBreakOverride(_ kind: BreakOverrideKind, plan: BreakDayPlan, from: Date? = nil, to: Date? = nil)`,
    `var breakRangeFrom: Date`, `var breakRangeTo: Date`, `var workingHoursEnabled: Bool` (on → 08:00–18:00),
    `var workingHoursFrom: Date`, `var workingHoursTo: Date` (minutes ↔ today's date in `calendar`), `var weekdayOrder: [Int]` (indices from `calendar.firstWeekday`).
  - Page rows, top to bottom (spec §9, this phase): Remind me to take breaks; Rhythm (picker "Steady · 50/5", "Pomodoro · 25/5", "Deep work · 90/15", "Flow", "Custom", with the evidence note below; Custom shows Work 10–180 step 5, Break 1–30, Long break every Off/2–8, Long break length when on); Weekday plan (seven pickers: "Usual rhythm", each preset, "No reminders"; footnote "No reminders turns off the rhythm that day. Eyes and the long-stretch guard follow their own switches."); Overrides (Today, This week, This month, Dates: "Weekday plan", each preset, "No reminders"; Dates shows From and To); Working hours (toggle, From, To); Eyes ("Every 20 minutes of use, a short reminder to look at something far away. It has no buttons."); Long-stretch guard (toggle and 60–180 picker in 15-minute steps; detail "One clearer prompt after an unbroken stretch, whatever the rhythm. With a longer work block it comes 15 minutes after that block."); Play a sound when a break is over; Show break countdown in the menu bar. Every row disabled while the master switch is off. All lengths tokens or `N.zoomed`.

- [ ] **Step 1: Write the failing checks** in `enum BreakSettingsPageChecks: CheckSuite`

```swift
("Breaks and Away are separate pages", pagesAreSplit),
("Every Breaks row is backed by a setting and found by search", breakRowsResolve),
("An override set in Settings covers today, this week or this month", overridesAnchorToToday),
("Working hours round-trip through the time pickers", workingHoursRoundTrip),
("Custom numbers are clamped when written", customWritesClamped),

// pagesAreSplit
expect(SettingsPage.breaks.sections == [.breaks] && SettingsPage.away.sections == [.away], …)
expect(Set(SettingsSection.breaks.mutableControlKeys).isDisjoint(with: SettingsSection.away.mutableControlKeys), …)
expect(SettingsSection.away.controlLabels.contains("Pause after no input for") && !SettingsSection.away.controlLabels.contains("Remind me to take breaks"), …)
// breakRowsResolve: every SettingsControlKey appears in exactly one section; SettingsSection.matching("Pomodoro") == [.breaks];
// matching("Working hours") contains .breaks; matching("End session after") == [.away]
// overridesAnchorToToday: model with now = Wed 21 Oct 2026 10:00 Berlin and the fixture calendar;
// setBreakOverride(.today, plan: .off) → stored first == last == 21 Oct; setBreakOverride(.week, .preset(.flow)) → 19…25 Oct;
// with now moved to 22 Oct, breakOverridePlan(.today) == .usual and (.week) == .preset(.flow);
// setBreakOverride(.range, .preset(.deepWork), from: 24 Oct, to: 22 Oct) → stored 22…24 Oct; setBreakOverride(.month, .usual) leaves none
// workingHoursRoundTrip: workingHoursEnabled = true → 480…1_080; workingHoursFrom = date at 07:30 → fromMinute 450; repeat with a Kiritimati calendar
// customWritesClamped: customRhythm = CustomRhythm(workMinutes: 500, breakMinutes: 0) → stored 180 and 1
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check`. Expected: compile errors (`.breaks`, model helpers).
- [ ] **Step 3: Implement** the model extension, the page view, the sidebar split and the search labels; remove the tier rows and `enabledBreakTiers`.
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass, including the existing Settings accessibility checks.
- [ ] **Step 5: Look at it.** In a `mktemp -d` copy (`CLAUDE.md`, Runtime probes), use the existing `--snapshot` or `--gallery` mode if it renders Settings, else build and open Settings in the copy without turning on Open at login; capture the Breaks page at the narrowest window and at the largest zoom, and fix any clipped row. Attach the captures to the report.
- [ ] **Step 6: Commit** — "Settings has a Breaks page with your rhythm, weekday plan and overrides, and an Away page".

---

### Phase-1 carry-overs

The phase-1 ledger (`_trash/sdd-2026-10-19-breaks-phase1-take-a-break/progress.md`)
sends these to phase 2. Each was re-read at a3b8417 and is still real.

| Ledger | Item | Where it goes |
|---|---|---|
| 107 | Day rhythm only written past `refreshBreak`'s guard; no "off" | Task 5 |
| 95 | `noteEyesPrompt` fallback says eyes off for the eyes prompt it logs | Task 2 |
| 81 | `BreakReminder.swift` is 416 lines | Task 2 (prompt types move out) |
| 88 | A damaged negative Later count is not clamped | Task 3 |
| 147 | BreakLog calendar fixed at launch | Task 7 |
| 147 | A prompt back after a Later starts a second log row | Task 7 |
| 154 | `breakReachesScreen` ignores the wake gate | Task 7 |
| 147 | Watching: the HUD's Start and the hero disagree | Task 7 |
| 154 | `BreakCountdown.cardText(.nan)` reads "Over over" | Task 7 |
| 147 | Take a break on a pause past the cap starts a new session | Task 8 |
| 147 | A break under 30 s comes back live after a kill | Task 8 |
| 154 | `applyExactCorrectionState` skips restore's break filters | Task 8 |
| 147, 153 | A sustained end resumes tracking at now, not at the backdated start | Task 8 |
| 147 | Double refresh at break end | Not built: no observable behaviour and no check can pin it; phase 4's performance pass |
| 154 | Check 1203 finds controls by a private class name | Not built: an OS rename fails it loudly, never falsely |
| 152 | Sustained input drains during the save-retry wait | Phase 3, by the phase-1 ruling |

Every other LATER line of the phase-1 final review (untested engine rules, a
91-second window edge, `continueApp` ordering, file lengths in `AppCoordinator`
and `FocusHero`, label joins, keyboard access to Later and Skip, duplicate days
after a time-zone change, and the rest) is not phase 2's and stays in that
ledger for phases 3 to 5.

### Task 7: Reminders and the break log mend phase-1 edges

**Files:**
- Modify: `Sources/Core/BreakLog.swift:93` (calendar), `:103-127` (`recordShown`, unknown-id diagnostics); `Sources/App/AppCoordinator.swift:680-688,856` (`breakReachesScreen`); `Sources/App/SessionStore+BreakActions.swift:13,19-23` (`canTakeBreak`, `startBreak`); `Sources/Surfaces/Focus/FocusHero.swift:97`; `Sources/App/AppCoordinator.swift:703-719` (HUD Start only when `canTakeBreak`); `Sources/App/BreakCountdown.swift:27`
- Test: `Sources/Verification/BreakCarryOverChecks.swift` (new suite)

**Interfaces:**
- Produces: `BreakLog.init(directory:calendar: Calendar = .autoupdatingCurrent, writeOverride:)`;
  `AppCoordinator.breakReminderReachesScreen(screenLocked:displayAsleep:machineSleeping:away:awaitingPresence:)`;
  `SessionStore.canTakeBreak` is false while watching, and `startBreak` refuses when it is false (ruling: one rule for every surface; the phase-1 ruling took Take a break away from the hero and menu while watching).

- [ ] **Step 1: Write the failing checks** in `enum BreakCarryOverChecks: CheckSuite`

```swift
("The break log follows a time-zone change", logFollowsTimeZone),
("A reminder back after a Later stays one log row", laterKeepsOneRow),
("A reminder after a wake waits for the person", reminderWaitsAfterWake),
("Watching offers no break anywhere", watchingOffersNoBreak),
("A countdown that is not a number reads Break over", countdownNaN),

// logFollowsTimeZone: inside a block that sets NSTimeZone.default to Europe/Berlin and restores it in a defer,
// a default-calendar BreakLog notes a rhythm; switch NSTimeZone.default to Pacific/Kiritimati; note again
// → the second day key == Kiritimati's start of that day (first probe that the swap moves Calendar.autoupdatingCurrent;
// if it does not, give BreakLog a `calendar: () -> Calendar` instead and swap that)
// laterKeepsOneRow: recordShown(A), noteLater(A), recordShown(B, same kind) → prompts.count == 1, id == B.id, laterCount == 1,
// outcome == nil; setOutcome(.started, for: B.id) → that row is .started; setOutcome on an unknown id returns nil and leaves rows alone
// reminderWaitsAfterWake
expect(!AppCoordinator.breakReminderReachesScreen(screenLocked: false, displayAsleep: false, machineSleeping: false, away: false, awaitingPresence: true), …)
// watchingOffersNoBreak: a store in the watching pause → canTakeBreak == false; startBreak(from: a main prompt) → isOnBreak == false
// countdownNaN
expect(BreakCountdown.cardText(remaining: .nan) == "Break over", …)
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check`. Expected: `logFollowsTimeZone`, `laterKeepsOneRow`, `watchingOffersNoBreak`, `countdownNaN` fail; `reminderWaitsAfterWake` does not compile.
- [ ] **Step 3: Implement.** `recordShown`: when the newest row has the same kind and outcome `.later`, it takes the new id and its outcome clears (`laterCount` and `shown` stay). `setOutcome`/`noteLater` on an unknown id write `Diagnostics.log`. The coordinator passes `store.presenceGate.isAwaitingConfirmation` (add a read-only store accessor if `presenceGate` is in `keep_internals`). `cardText` begins with `let remaining = bounded(remaining)`.
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Commit** — "A reminder after a wake waits for you, and one put off stays a single entry in the break log".

---

### Task 8: Breaks survive a kill, a stale pause and a correction intact

**Files:**
- Modify: `Sources/Core/SessionEngine+Break.swift:31-40` (past-cap start), `Sources/Core/SessionEngine+Restore.swift:71-78,97-108` (filters as one helper; the stretch-saved branch), `Sources/Core/SessionEngine+Corrections.swift:124`, `Sources/App/SessionStore+BreakActions.swift:176` (`confirmPresence(at: ended.end)`); `build.sh:91` if a new engine helper is added
- Test: `Sources/Verification/BreakCarryOverChecks.swift` (append; a second suite `BreakRestoreCarryOverChecks` if the file passes 250 lines)

**Interfaces:**
- Produces: `private func SessionEngine.restorableBreak(_ brk: ActiveBreak?) -> ActiveBreak?` (credible and not yet recorded), used by restore and `applyExactCorrectionState`; added to the engine's first `keep_internals` list.

- [ ] **Step 1: Write the failing checks**

```swift
("Take a break on a pause past the cap ends that session first", pastCapPauseEndsFirst),
("A break under 30 seconds stays ended after a kill", shortBreakStaysEnded),
("A correction does not bring back a break restore would drop", correctionFiltersBreak),
("Recording resumes where the input that ended a break began", trackingResumesAtBackdatedStart),

// pastCapPauseEndsFirst: manual pause, clock past longAwayCap, startBreak(length: 300), endBreak →
expect(engine.state == .idle && records.count == 1 && records[0].end == pauseStart, …)
// shortBreakStaysEnded: start a break, take the engine snapshot just before endBreak's state save (the pre-end snapshot),
// end it at 20 s, restore a new engine from that snapshot plus the saved archive → activeBreak == nil, state == .idle
// correctionFiltersBreak: a newer checkpoint carrying activeBreak with plannedEnd = start + 1e9 → after prepareCorrection, activeBreak == nil
// trackingResumesAtBackdatedStart: real AppUsageTracker on a scratch archive with a TestClock; a sustained-input end backdated 75 s →
// the first usage segment after the break starts at ended.end, not at now
```

- [ ] **Step 2: Run to verify they fail** — `./build.sh --check`. Expected: all four fail.
- [ ] **Step 3: Implement** the four fixes (the triage's smallest forms: `completeLongAway(intent: .endOnly)` before a past-cap break; `activeBreak = nil` in the stretch-saved restore branch while still inside its cap; one shared break filter; presence confirmed at `ended.end`).
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Commit** — "A break taken on a stale pause, cut short by a crash or replayed by a correction is recorded once and ends as it should".

---

### Task 9: Whole-branch verification, then ship on Sir's word

- [ ] **Step 1:** `./build.sh --check`, `TZ=Europe/Berlin ./build.sh --check` and `TZ=Pacific/Kiritimati ./build.sh --check`. Record `passed/total` for each.
- [ ] **Step 2: Mutations** in a `mktemp -d` copy, each run with `./build.sh --check`, each must fail at least one new check:
  A. guard rest back to 15 minutes (`creditGap` → 900 for `.ultradian`);
  B. Eyes quiet window removed;
  C. migration reads `.micro` for the guard;
  D. `noteRhythm` moved back after the guard;
  E. override tie goes to the longest span.
- [ ] **Step 3:** Run `fix-reviewer` and a final code review on `main..HEAD`; fix what they confirm.
- [ ] **Step 4:** Report to Sir with the counts, the rulings above and the two default-visible changes (rulings 1 and 2). Ship with the `ship` skill only after Sir approves.
