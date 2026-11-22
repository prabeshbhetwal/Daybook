# Activity goals: count coding wherever it happens

Status: approved by the owner, 22 November 2026. Plan
review: GPT 94, change (accounting from slices not phases, exact midnight
cut, ring reconciliation, override timing, drop the switch hint), all
folded in. Gemini failed to run; no other reviewer answered.
Related: `2026-11-18-daily-goals-design.md` (goal list, targets and limits),
`2026-11-17-activity-aware-sessions-design.md` (phases, purposes, credit).

## Problem

On 22 November the rail read "9h 26m of 4h focus, goal met" and, under it,
"Coding 0m of 2h". Every session that day was started by hand as Deep work,
and a category goal counts only time filed under that category
(`SessionStore.categoryCredit`). Hours of coding inside Deep work counted
for nothing. The AI category assistant does not help: it only re-files
automatic sessions whose category is unclear, and a category the person
picked is never unclear.

The person's words: coding time inside a Deep work session should count
toward the Coding goal.

## What already exists

| Piece | Where | Use |
|---|---|---|
| Goal target `.activity(String)` | `DailyGoalList.swift` | Already decodes, stores and round-trips |
| Kind rule: a focused purpose is a target | `DailyGoalList.swift:52` | Already says `.activity(coding)` is `.target` |
| Activity limits (Media, Utility) | `DailyGoalList+Activity`, `GoalDayResults` | Counting pattern for the limit side |
| Per-phase credited seconds by purpose | `SessionPhase.credited` | The figure an activity target counts |
| Session shapes for the day | `SessionStore.sessionActivity(for:)` | Source of phases, cached |
| Purpose of each app | `PurposeMap`, `store.purposeOverrides` | Decides what is "coding" |
| Category goal rows, goal results | `StoryRail.categoryGoalRows`, `GoalDayResults.close` | Where the new rows and results land |

The model was built for this ("once activity labels ship"); only the
counting, the editor and the rail are missing.

## Decision

Let a focused purpose be a daily **target**, not just a limit: "Coding 2h"
as an activity goal counts coding in every focus session, whatever the
session is filed under. Category goals stay as they are.

Chosen over linking a category to a purpose (a Coding category that also
counts coding elsewhere): that needs a new field on every category, a rule
for the overlap of the two, and still leaves "what is Coding?" ambiguous.
An activity goal says exactly what it counts. Chosen over letting the AI
re-file hand-started sessions: that overrides a choice the person made.

## Rules

1. **Valid targets.** Each `AppPurpose` with `isFocused` (coding, writing
   and AI, design) can be an activity target. The others (communication,
   research, media, utility) stay limits only, as now.
2. **What counts.** The shape's own `credited[purpose]` total for each focus
   session row of the day, not phase figures. Phases are for display: a
   phase's `counted` flag means "mostly counted" per 60-second cell. A
   session row is already cut at midnight, and a shape derived from beats
   is derived within the row, so the split is exact. A day whose beats have
   expired reads the session's kept summary, which `clipped(to:)` splits at
   midnight by duration: an accepted approximation for those days only.
3. **Never above the ring.** The ring counts with `FocusedActiveTime`; the
   slices come from a separate derivation. The row shows
   `min(activity seconds, ring seconds)` for the day, and a check measures
   how often the cap bites on fixtures with pauses, missing app evidence,
   overlapping records and a running session. If it bites by more than a
   minute on any fixture, the two accountings are reconciled before ship.
4. **Sessions not counting toward focus** (a category set not to count, or
   leisure) add nothing, as for category goals.
5. **Running session.** Counted live from its current slices, refreshed on
   the existing coalesced refresh, never on its own timer.
6. **Old sessions without beats** (`fidelity == .appsOnly`) count from
   their apps-only credit and the row's info mark says so, as the phase
   strip already does.
7. **No double counting inside one goal.** A credited second is counted
   once, even where records overlap. Goals may overlap each other (Coding and a Deep work
   category goal can both count the same minute), as the goals spec already
   allows: goals do not sum to the ring.
8. **Past days.** Results are recorded at day close like other targets
   (`GoalDayResults.close` gains the `.activity` target case). Days already
   closed keep their results; a later change to an app's purpose affects
   today and later days only.
9. **Recording off.** Same as other targets: no bar, the tile's existing
   "App recording is off" line, day left out of Perfect day.

## What the person sees

- **Settings › Daily goals › Add goal** lists the focused activities under
  their own heading, "Activities (counted in any session)", with the
  purpose's symbol. A Coding category and the Coding activity can both
  exist; the editor shows which is which by the heading.
- **Today's goals** shows an activity row like a category row: symbol,
  name, "1h 31m of 2h", bar. Its info entry: "Counts coding in any focus
  session, by the apps in front: editors and terminals. AI apps such as
  Claude and ChatGPT count as Writing & AI."
- No prompt to switch an existing category goal: the person adds the
  activity goal and removes the category goal if they want. A switch hint
  can follow once the goal has been used for a while.

## Known gap the owner should decide

Much of the 22 November coding was in Claude and Dia, which `PurposeMap`
files as Writing & AI (Dia also as research or media depending on use).
The rail's activity list showed Coding 1h 31m for one block that day
(screenshot, not recomputed), far below the 9h of work. `store.purposeOverrides` already lets an app be given another
purpose, but no screen sets it. Options:

| Option | Cost | Effect |
|---|---|---|
| a. Leave as is | none | Coding counts editors and terminals only |
| b. Add "Counts as" to the app row in Top apps | one menu, existing storage | Person sets Claude to Coding once |
| c. Ask the on-device model per AI-app phase | new model call, privacy review | Automatic, less predictable |

Owner ruling, 22 November 2026: **a**. Coding counts the apps
`PurposeMap` already files as coding (editors, terminals); AI apps stay
Writing & AI. No "Counts as" control in this change.

## Out of scope

- Setting an app's purpose by hand ("Counts as"), per the ruling above.
- Re-filing or splitting hand-started sessions.
- Activity goals for leisure purposes (they stay limits).
- Changing category goal counting.
- Ask Daybook phrasing beyond adding the new goal to `AskFacts+Goals`.

## Checks (each fails on today's behaviour)

1. A Deep work session with 40 minutes of credited coding fills a Coding
   activity goal by 40 minutes; the Coding category goal stays at 0.
2. Uncounted time (watched, away) adds nothing, and credited coding inside
   a phase marked uncounted is still counted.
3. A session in a category set not to count adds nothing.
4. A session across midnight with coding 11:50 pm to 11:55 pm and research
   11:55 pm to 12:10 am gives the first day 5 minutes of coding and the
   second day none (duration-share clipping would split it wrongly).
5. On fixtures with pauses, missing app evidence, overlapping records and a
   running session, activity seconds before the cap stay within a minute
   of the ring; the shown row never exceeds it.
6. A non-focused purpose still cannot be a target.
7. Day close records an `.activity` target result; a closed day is not
   rewritten after an override changes.
8. All checks hold under `TZ=Europe/Berlin`.

## Tasks

1. Core: purpose seconds summed from session rows and capped at the ring,
   plus `.activity` target results at day close.
2. App: day credit by purpose on `StoryRailDay`, capped at the ring, live
   for the running session.
3. Settings: activity targets in Add goal.
4. Rail: activity rows and info entry.
