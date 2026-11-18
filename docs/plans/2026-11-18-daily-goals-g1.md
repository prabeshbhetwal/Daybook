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

Panel review (GPT 96 change, Gemini 92 change, DeepSeek change, Nemotron
approve with gaps) found tasks 1 to 3 cannot be a no-visible-change PR:
counting on evidence changes the category figures the old tile shows, and a
migration that lands before the Settings editor reads the list would make
edits in Categories silently ignored.

- **PR 1, no visible change:** task 1 (model) and the storage half of task 2
  (list, per-day record, migration). Nothing reads the list yet; the old
  category goal field stays the one truth.
- **PR 2, the visible release:** tasks 3, 4 and 5 together: counting, the
  tile, and Settings and Categories both editing the list. The category
  figure change and its explanation land in the same release.
- **PR 3:** tasks 6 and 7.

## Additions from review

- **Per-day record (task 2).** Store `goalResultsByDay: [Date: [GoalResult]]`
  beside the archive's day keys: goal id, target, amount, seconds counted,
  met. Written when a day closes and refreshed while it is open; past days
  are read from it and never recomputed, so an edit or a deleted goal cannot
  change history. History (task 6) and awards read only this record.
- **Migration guard (task 2).** A `goalsMigratedVersion` preference, set in
  the same write that saves the migrated list. A failed write leaves the
  flag unset so the next launch retries; the category field is left
  untouched until PR 2 ships. More than 8 categories with goals: the first
  8 in category order migrate and the rest stay on their category until the
  person adds them. Checks: failure retries, cap, relaunch is a no-op.
- **Backups (task 2).** The list and `goalResultsByDay` join the backup set
  and its restore; a restore from before the list existed re-runs the
  migration. Check: backup round trip.
- **Once-per-day haptic (task 4).** `goalReachedPlayed: Set<GoalID>` kept in
  the store per day key, cleared at midnight, not in the view.
- **Counting cost (task 3).** One credit pass per refresh, shared by every
  goal: build per-category credited seconds in a single pass, then read each
  goal from it. Republish only when a printed minute changes. Check: the pass
  count does not grow with the number of goals.
- **Wrong-kind goals (task 1).** A target on an app, or a limit on a
  category, is refused when saved and ignored when loaded from a file.

## Risks

- Counting cost: one `FocusedActiveTime` pass per goal per refresh. Bound it
  to the day and reuse the ring's pass where the inputs match.
- A migrated goal that the person had set long ago appearing as new: the
  tile's first appearance carries a one-time note "Your category goals are
  now here."
