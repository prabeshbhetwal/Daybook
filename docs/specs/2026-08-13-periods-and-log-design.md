# Day / Week / Month and the Session Log — Design Spec

**Date:** 2026-08-13
**Status:** Approved for planning

---

## 1. Goal

The dashboard can only answer "how was today". Every reference app leads with a period
switch and a chronological log. This slice adds both.

## 2. What the references establish

- **Screen Time**: a period bar chart with a dashed **average line**, a colour legend
  carrying per-category totals beneath it, then a ranked app list. The average line is what
  turns a bar chart into a judgement — without it, bars are just bars.
- **Timemator**: `Day / Week / Month / Year / Custom` tabs; stacked daily bars with the
  total written above each; then a **chronological log grouped by day**, time range on the
  left, name in the middle, duration right-aligned.
- **Tim / Timing**: a compact row of headline figures at different widths — active days,
  total, average per day. This works where my four equal cards did not, because the figures
  are one row of varying weight rather than a grid of identical boxes.

## 3. Period switch

`Day · Week · Month` replaces the date stepper as the primary control; the stepper stays
beneath it to move within the selected period. Persisted, so the app reopens where you left.

| Period | Chart | Bar = |
|---|---|---|
| Day | The existing elided timeline | unchanged |
| Week | 7 bars | one day |
| Month | 28–31 bars | one day |

Week and Month bars are **stacked by work type** using the existing palette, so a bar shows
both height and composition. A dashed average line crosses the chart, labelled `avg`.

## 4. The stat row

One row, varying widths, above the chart:

```
TRACKED          ACTIVE DAYS     AVERAGE / DAY     LONGEST SESSION
14h 32m          5 of 7          2h 55m            2h 13m in Xcode
```

Not four equal cards. Each figure is sized to its content, the label is small and secondary
above, and the row collapses to two lines when the window narrows. On Day the row reads
tracked, sessions, average session, longest.

## 5. The session log

Below the chart, replacing nothing — this is new. Sessions in reverse chronological order,
grouped by day with a day header carrying that day's total:

```
Wednesday, 13 August                                   4h 47m
  16:00 – 16:35   ▣ Xcode      Refactor the parser      35m
  14:00 – 15:36   ▣ Chrome     Research                1h 36m
  10:30 – 13:06   ▣ Xcode      Deep work · 3 visits    2h 36m

Tuesday, 12 August                                     3h 54m
  ...
```

Each row: the clock range, the app icon and name, the intent or work type, and the
duration. `· N visits` appears only when the grouped session had more than one stretch,
which is where the grouping work becomes visible to the user. Rows are hairline-separated,
never cards. Clicking a row selects that session on the chart above.

On Day the log shows today only; on Week and Month it shows every day in the period, which
is what makes the log worth scrolling.

## 6. Layout

The left column becomes: active session → stat row → period switch and chart → session
log. Top apps and focus quality move **below the log**, since the log is now the primary
evidence and the rankings are the summary. The right column is unchanged.

## 7. Architecture

```
Core/PeriodStats.swift    NEW. Period bounds, per-day rollups, averages, and the
                          flattened log. Pure, injected clock.
Core/DashboardStats.swift Unchanged; PeriodStats composes it per day
App/SessionStore.swift    Publishes `period`, `periodBars`, `periodLog`, `periodStats`
Surfaces/Dashboard/
  PeriodChart.swift       NEW. Stacked bars, average line, legend
  SessionLogList.swift    NEW. Grouped chronological rows
  StatRow.swift           NEW. The varying-width figure row
```

`PeriodStats` composes `DashboardStats` once per day in the period rather than
reimplementing the arithmetic — one definition of a day's numbers, used everywhere.

**Cost.** A month is 31 day-slices. Each is one pass over the usage array, so a month view
is 31 passes on selection, not per frame; results are held on the store until the period or
the archive changes. Measured against the 20 MB budget before and after.

## 8. Verification

- Period bounds: week starts on the calendar's first weekday; month covers every day.
- Rollups: a day's bar equals `DashboardStats.trackedTotal` for that day.
- Average: mean over **active** days, not calendar days — a week with two idle days
  averages over five, or the number is meaningless.
- Log ordering and grouping: reverse chronological, correct day headers, day totals equal
  the sum of their rows.
- `· N visits` appears only above one visit.
- Empty period renders the empty state, never a blank frame.

## 9. Out of scope

Year and Custom ranges, editing log rows, export, billing and hourly-rate features from the
references, and the Session-style circular timer.
