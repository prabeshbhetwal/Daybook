# Complete Story interactions — verification

Date: 2 September 2026

Baseline: `dbb4bde` (plan approved). Task 7 closed at `31ff359`; this document
accompanies the Task 8 commit. No push authorised or performed.

Status: implementation and local verification complete within the limits
below. The Mac remained locked for the whole run, so every pointer, VoiceOver,
live-hardware and live-discovery check is listed as deferred rather than passed.

## Scope

The approved [interaction model](../specs/2026-08-31-story-interaction-model-design.md)
and [session-controls and activity-rules proposal](../specs/2026-08-31-session-controls-and-activity-rules-proposal.md),
executed through the [plan](../plans/2026-08-31-complete-story-interactions.md)
as eight tasks with an independent review and bounded fix rounds per task.
`DESIGN.md` records the design decisions; `README.md` the behaviour.

| Task | What landed | Review outcome |
| --- | --- | --- |
| 1 Continuation | Only the latest stretch of a thread continues; stale cards and menu actions are rejected; a continued thread keeps every stretch. | Clean after one fix round. |
| 2 Activity display | Logged focus, recorded app use and elapsed time are distinct; short sessions use seconds; recording gaps stay unknown; App activity strip with keyboard-reachable interval detail. | Clean after one fix round. |
| 3 Durable Undo | Per-entry recoverable action journal; older receipts stay undoable after later decisions and relaunch; failed saves refuse visibly and retry. | Clean after five bounded rounds. |
| 4 Reading workspaces | Week and Month children open in place; History and Insights keep their own dates; explicit-day projections never mutate the global Day. | Clean after one fix round. |
| 5 Compact controls | In-window session strip with pinning; 320–360 pt menu panel; stable Settings pages; bounded Month cells; Arrange cards with keyboard Move actions. | Clean after one fix round. |
| 6 Notes and power | Per-stretch notes in a sidecar; factual power context from observations only; durable, record-scoped recovery. | Clean after five bounded rounds. |
| 7 Activity rules | Opt-in rules replace the legacy heuristic; one primary activity; quiet choice for shared apps; identity-bound Undo with cooldown; bounded local app discovery. | One Critical (double credit after Stop interrupts a mid-dwell run) fixed at the detector and the engine with RED coverage; clean after two rounds. |
| 8 Integration | Seven cross-feature checks; snapshot appearance axis light/dark/system; documentation. | This document. |

## Executed commands and counts

- `./build.sh --check`: 396/396 passed, staged bundle 11 MB signed with a
  strict `codesign --verify --deep --strict`, local bundle not promoted.
  Warnings-as-errors clean.
- `git diff --check`: clean.
- `./build.sh` then `FocusContinuity --snapshot`: 252/252 product snapshots
  at 980 pt and 1160 pt in light, dark and system appearance (84 each), plus
  the compact popover and quick/full prompt captures.
- `scripts/build-fixture-app.sh activityRuleAmbiguity`: fixture-only app
  built and ad-hoc signed; **not launched**.

## Cross-feature regression coverage (Task 8, Step 1)

`Sources/Verification/StoryIntegrationChecks.swift`, all through consumer
state, none through source strings:

1. Continuing after a saved note resumes the same thread on a new stretch and
   the note stays on the stretch it was written on.
2. Undoing an older receipt with the inline Month child open leaves the scope,
   the selected day and the open child in place.
3. Editing activity rules while the strip is pinned neither hides nor
   collapses it, starts nothing, and presents no choice without evidence.
4. Switching Insights scope leaves the Story scope and selected day untouched.
5. A powered fixture records observations; a no-power fixture invents none;
   both stretches reach the story.
6. Reduce Motion drops every product animation to instant.
7. An automatic start reaches the session controls once the main queue turns.

RED found in Step 2 was in the fixtures, not the product: a store with no
attached usage archive clears review data and never fills day entries; and the
store mirrors engine state through `DispatchQueue.main.async`, so a synchronous
fixture must let the queue turn before rendering. Both were fixed in the
fixtures; no acceptance test was weakened.

## Visual acceptance (Task 8, Step 3)

Screenshots were rendered and then inspected, not merely generated. Inspected
captures and what each shows:

- `activityRuleAmbiguity-comfortable-light` (1160 pt): the quiet choice in the
  in-window strip — question, factual exclusion line, two bordered answers —
  beneath the chrome with Pin/close intact; Arrange cards in the rail.
- `activityRuleAmbiguity-popover-dark`: the same choice card in the compact
  menu panel between the hero and continuations.
- `activityRuleAutomatic-minimum-system` (980 pt, system): a rule-started
  session shown consistently everywhere — chrome pill clock, "Focus in
  progress" strip with Pause/Away/Stop, "Started automatically", the adopt or
  reclassify row, "Undo automatic session", and the running entry with Add
  note, Pause and End session.
- `settingsActivityRules-comfortable-light`: Sessions page with **Use my
  activity rules** and its opt-in explanation. **Limitation:** the rule
  editor's rows sit below the sheet's fold; sheets keep their production
  height in captures, so the editor rows were not visually inspected. They
  are exercised by the `editorConsumer` check and reachable in the fixture app.

Reduce Motion is not a still-image property and the system flag cannot be
forced through the SwiftUI environment; the snapshot axis is therefore
light/dark/system, and the Reduce Motion contract is verified on
`Tokens.Motion.animation(_:reduceMotion:)`.

## Native fixture checks (Task 8, Step 4)

Deferred, with the exact limitation: the Mac was locked throughout, so timer
strip opening/pinning, scope keyboard, Escape/X, note saving, rule selection
and rail ordering were not driven by pointer or keyboard in the native
fixture app. Their logic is covered headlessly (CompactControlsChecks,
SessionMetadataChecks, ActivityRuleChecks, StoryIntegrationChecks) and the
Task 5 hosted-window keyboard probes. No production launch and no real-data
migration occurred.

## Known limitations carried forward

- Pointer, VoiceOver traversal, native picker appearance and focus-ring
  visuals: deferred (locked Mac).
- Live IOKit power sampling and live Spotlight discovery: not exercised. The
  Spotlight query runs on a worker without a run loop and may yield nothing in
  production; it fails safe (less discovery, never more) and is recorded as
  unverified.
- An in-process accessibility walk cannot see SwiftUI-only elements
  (`NSHostingView` reports zero accessibility children), so render proofs use
  the production evidence seam; assistive-technology exposure of SwiftUI
  containers remains a manual check.
