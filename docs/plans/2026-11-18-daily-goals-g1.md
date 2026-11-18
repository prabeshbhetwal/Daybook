# Daily goals, phase G1: plan

Spec: `docs/specs/2026-11-18-daily-goals-design.md`. G1 ships the goal list,
the migration from category goals, evidence-backed category targets, the
"Today's goals" tile, the Settings group and the History day tile. Limits
(G2), rewards (G3), labels (G4) and websites (G5) follow in their own plans.

Rules for every task: Core stays UI-free; views read published figures and
never compute time; lengths are tokens or `N.zoomed`; each task adds checks
at the end of `registeredTests` that fail on the old behaviour; checks use
`TestClock`, `SelfTest.scratchDirectory()` and `MemoryDefaults`; run
`./build.sh --check` (sandbox off) and `TZ=Europe/Berlin ./build.sh --check`
before each commit; run the `fix-reviewer` agent on tasks 1, 2 and 4
(persistence, settings, time arithmetic).

## Tasks

1. **Core model.** `Sources/Core/DailyGoals.swift`: `DailyGoalItem`
   (`id`, `target`, `kind`, `seconds`, `isPaused`), `DailyGoalTarget`
   (`.category`, `.app`, `.site`, `.activity`, Codable with an unknown-case
   fallback so a newer file never fails to load), `DailyGoalKind`, and the
   rule "categories and kept labels are targets; apps, sites and Leisure are
   limits". Cap of 8. Checks: round trip, unknown target kept, invalid kind
   refused, cap.

2. **Persistence and migration.** `PersistenceStore.dailyGoals` (JSON in
   preferences) and the per-day record `goalsByDay: [Date: [DailyGoalItem]]`
   kept with the archive's day keys. One-time migration from
   `WorkTypeDefinition.dailyGoal` in category order, guarded by a version
   flag so it runs once and never re-adds a deleted goal. Checks: migration
   once, order kept, idempotent across relaunch, a past day's goals
   unchanged after an edit today.

3. **Counting.** `GoalCount` in Core: for a target, evidence-backed focus
   filed under the category within the day (the `FocusedActiveTime` path the
   ring uses, filtered by work type, running session included). Published by
   `SessionStore` as `goalRows: [GoalRow]` on the existing refresh; the 1 Hz
   tick only republishes when a printed minute changes. Checks: a category
   row never exceeds the ring's figure for the same records; time with no
   app use is left out; the running session counts; DST day in Berlin.

4. **Today's goals tile.** `StoryRail.focusTile` becomes "Today's goals":
   ring row ("1h 26m of 4h focus"), up to 4 rows, "All goals" popover,
   info mark (spec wording), "App recording is off" state. Met row shows
   "3h ✓" and plays `goalReached` once per goal per day (state in the store,
   not the view). Gallery fixture with 0, 1, 4 and 6 goals; snapshot at
   zoom 1 and the largest zoom. Checks: rows follow the list order; a met
   goal plays once across refreshes; paused goals hidden.

5. **Settings › Goals.** List, Add Goal… (categories only in G1), duration
   presets from `WorkTypeDefinition.goalOptions`, reorder (drag and arrows),
   pause, delete. The Categories editor's goal field edits the same item.
   Help entries for the group's info mark. Checks: one truth between the two
   editors; keyboard reorder; VoiceOver labels.

6. **History day tile.** The same tile for a past day from `goalsByDay`,
   through `storyRailDay(on:)`. Checks: a past day shows the goals it had,
   not today's.

7. **Ask Daybook.** `AskFacts+Goals` lists the day's goals and progress.
   Checks: facts match the tile.

## Order and shipping

Tasks 1 to 3 land together as one PR (no visible change: the old tile reads
the new rows). Tasks 4 and 5 are one PR, the visible release. Tasks 6 and 7
are one PR. Each subject line is written for any user of the app.

## Risks

- Counting cost: one `FocusedActiveTime` pass per goal per refresh. Bound it
  to the day and reuse the ring's pass where the inputs match.
- A migrated goal that the person had set long ago appearing as new: the
  tile's first appearance carries a one-time note "Your category goals are
  now here."
