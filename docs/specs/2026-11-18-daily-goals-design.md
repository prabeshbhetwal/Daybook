# Daily goals: several goals a day, targets and limits

Status: approved by the owner, 18 November 2026. Panel review
(GPT 92 change, Gemini 92 approve, DeepSeek 75 change, Nemotron 85
approve); their changes are folded in: per-day goal records, pause rules,
kept labels, recording off, phased Add Goal, the ring-versus-goals note.
Related: `2026-11-17-activity-aware-sessions-design.md` (activity labels,
leisure blocks), the Yesterday recap redesign (scorecard), and the
glanceable rail work of 18 November (info marks on rail tiles).

## Problem

The rail's "Daily goal" card shows one figure against one day goal, plus a
quiet row for any category that has its own goal. People plan days in
several parts ("Coding 3h, Research 3h, Homework 2h, no more than 2h of
YouTube") and want each part tracked, with a sense of reward when it is
done. Two defects make the current card hard to trust:

- The category row counts every second filed under the category (Coding
  1h 51m) while the ring counts only focus with app use recorded (1h 26m).
  Two rules on one card.
- Leisure has nowhere to go. A "YouTube 2h" goal written as a target would
  reward watching more.

## What already exists

| Piece | Where | Keeps or changes |
|---|---|---|
| Day goal, evidence-backed | `PersistenceStore.dailyGoal`, `DailyGoal`, `GoalProgress` | Keeps: the ring stays the day's total |
| Category goal (optional, preset durations) | `WorkTypeDefinition.dailyGoal`, Settings › Categories, `goalOptions` | Becomes a target goal in the new list (migrated, not duplicated) |
| Category goal rows on the rail | `StoryRail.categoryGoalRows`, `storyCategorySeconds` | Replaced by goal rows; counting changes to evidence-backed |
| Per-category met rates in History | `SessionStore+InsightRange` (`metDays`) | Reads the new goal list |
| Goal-met haptic | `HapticMoment.goalReached` | Reused for each target met |
| Awards from `AwardFacts` | `Awards.all(from:)` ("Goal, N days" etc.) | Gains per-goal runs |
| Streak (25m minimum) | `SessionArchive.currentStreak` | Unchanged |
| Ask Daybook goal facts | `AskFacts+Goals` | Gains the goal list |

## Model

A goal is one line in an ordered list, kept in preferences:

```
DailyGoalItem { id, target, kind, seconds, isPaused }
target: .category(WorkType) | .app(bundleID) | .site(host) | .activity(label)
kind:   .target ("at least") | .limit ("at most")
```

- **Targets** are for focus: a category, or (once activity labels ship) an
  activity label the person has kept. They count what the ring counts:
  focus with app use recorded, filed under that category or label.
- **Limits** are for anything else: an app, a website (once site detection
  ships), or the Leisure label. They count all recorded foreground use of
  the target, in or out of sessions, leisure blocks included. Leisure is
  never focus, so a focus-only count would always read zero.
- A category or kept label can only be a target; an app, site or Leisure
  only a limit. The editor offers only the valid kind, so no one has to
  learn the rule.
- Unkept AI labels cannot be goal targets (activity-aware spec anti-goal).
- The day goal stays a single figure: the ring. Goals do not have to add up
  to it, and the ring does not sum the goals.
- At most 8 goals; the rail shows the first 4 in the person's order and
  "All goals" opens the rest.
- **Each day keeps its own goals.** The day's active goals and amounts are
  recorded with the day. An edit applies to today and later days; past days,
  their results and awards never change. Deleting a goal keeps its history.
- **Paused goals** are hidden from the tile, ignored by Perfect day, and do
  not break or extend a goal's run. A day with no active goals has no
  Perfect day.
- **Kept labels** are the activity-aware spec's: a label the person kept,
  renamed or merged into a category. An unkept AI label is never offered.
- **App recording off.** With nothing recorded, a target cannot count and a
  limit cannot be judged. The tile says "App recording is off, so goals
  can't count today" instead of showing empty bars, and that day is left
  out of Perfect day and awards rather than counted as missed.

Migration: on first launch of the version that ships this, each category
with a `dailyGoal` becomes a target item in category order; the category's
own field is then read only by the migration. Settings › Categories shows
the category's goal and edits the list item, so there is one truth.

## Display

Rail tile "Today's goals" (renamed from "Daily goal"), info mark beside the
trailing day:

- Ring row as today, with "1h 26m of 4h focus". The counting rule moves to
  the info mark.
- Target row: category icon, name, "45m of 3h", a bar in the category
  colour. Met: the figure becomes "3h ✓", the bar fills, `goalReached`
  plays once, and the row's tick draws in (no motion with Reduce Motion).
- Limit row: icon, name, a small "limit" tag, "45m of 2h limit", a neutral
  bar, "1h 15m left" beneath. Past the limit: "15m over" in amber, no sound,
  no alert. A limit is never shown as met during the day.
- Info mark: what counts for targets, what counts for limits, and "Goals
  are separate: the ring is your day's total focus, not the sum of your
  goals."
- History shows the same tile for a past day, with limits judged ("Kept ✓"
  or "15m over").

## Rewards, calm but felt

- **A target met**: the tick, the haptic, the bar filling. Once a day each.
- **Perfect day**: every target met and every limit kept. Shown the next
  morning in the Yesterday recap's scorecard, after the day is over, so a
  limit is never celebrated while it can still be broken.
- **Awards**: per goal, the longest run of days met or kept
  ("Coding goal, 5 days", "Kept to YouTube limit, 7 days"), and "Perfect
  week" for seven perfect days in a row. Awards stay in the Awards sheet.
- **Streak**: unchanged (a day with the minimum focus). Goals do not feed
  it, so a missed goal never breaks a streak.
- No confetti, badges in the menu bar, or notifications by default.

## Settings

A "Goals" group in Settings: the list in order (drag or arrows), Add Goal…
(pick a category, and once each phase ships a kept activity, an app or a
website; the kind follows; types not shipped yet are not offered), a
duration from the existing presets, and pause. The Categories editor shows
the category's goal and edits the same item.

## Phasing

| Phase | Ships | Depends on |
|---|---|---|
| G1 | Goal list, migration, category targets counted on evidence, Today's goals tile, Settings group, History day tile | Nothing new |
| G2 | App limits (any app), "limit" rows, judged limits in History | G1 |
| G3 | Perfect day in the recap, per-goal awards, Perfect week | G1, recap redesign merged |
| G4 | Activity-label targets and Leisure limits | Activity-aware Phase B/C (kept labels, leisure blocks) |
| G5 | Website limits (e.g. YouTube) | Site detection in the activity-aware work |

## Non-goals

Blocking or hiding apps; weekly or monthly goals; goals that sum to the day
goal; reminders as a limit nears (open question below).

## Open questions for the owner

1. YouTube is a website, so a "YouTube 2h" limit needs site detection (G5).
   Until then an app limit counts only an app, never the browser, and the
   Add Goal sheet says so. Is an app limit (or the Leisure label in G4)
   enough until G5?
2. Should a limit warn once when 10 minutes are left? Off by default if so.
3. Should goals apply every day, or allow weekdays only? (Proposed: every
   day in G1; weekdays as a later option.)
