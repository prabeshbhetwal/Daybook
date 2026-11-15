# History front view: design

15 November 2026. Status: awaiting owner approval. Nothing is built.

## Intent

History's drill-down (months, then weeks, then days, with the rail following
and the day view at the bottom) is liked and stays exactly as it is. The first
view of History is the one level that does not look like the rest of the app:
a wide "Each day" bar chart card, then a stack of near-identical boxed cards
that each repeat daily bars. It reads as dashboard widgets, daily data is drawn
twice, and nothing leads.

This change redraws only that first view so it reads as the day view does: one
sentence, one picture of the days, then a quiet timeline of periods on a spine.

## Goals

- The first view answers, in order: how much, when, on what.
- It is drawn in the day view's language: headline, a gutter beside a spine,
  one card for the current period, quiet rows for the rest.
- Every day is drawn once.
- A non-technical reader gets sentences; a technical reader gets exact figures
  from the legend and the readout.
- It holds for a first week, a few months, and more than a year.

## Non-goals

- No change to the levels below the first view, the rail, the path bar, the
  search, the app and category filters, or Go to Date.
- No new stored data. Every figure is derived from `historyDays`.
- No comparison for the current, unfinished period.
- No new keyboard focus zone for the day grid (see Interaction).
- No export, no weekday averages, no second day calendar.

## Anti-goals

- A figure or sentence that is not computed from the record.
- A sentence that judges the reader.
- An entrance animation. `DESIGN.md`: "Do not choreograph everyday page loading."
- Meaning carried by colour alone.

## Constraints

- `DESIGN.md` is the authority for type roles, inks, radii and motion. Read text
  uses `StoryStyle.supportingInk`; fainter inks only on drawn marks, each with
  `// ink: quiet`.
- Every length is a token or `N.zoomed`; a deliberately fixed one says
  `// zoom: fixed`.
- Core stays UI-free. New calculations live in Core with checks; views read
  published models and add no timers.
- Must fit the 980 point minimum window: a 300 point rail and 30 point column
  insets leave about 620 points for the column.
- Checks hold in any time zone. Periods use `periodCalendar` (Monday-first).

## Approaches considered

| | What | Trade-off |
|---|---|---|
| A | A year-at-a-glance day grid, months as light rows | Shows rhythm and gaps; on its own it reads as a developer chart |
| B | The same months redrawn as the day view: one spine, no boxes, a sentence each | Closest to the app's voice; least new information |
| C | A wall of small month calendars | Familiar; weak for comparing months; repeats days if combined with A |

The owner chose a mix led by B: B's spine and sentences, A's day grid in place
of the "Each day" chart, and C surviving as the grid's month blocks. A panel of
five outside models reviewed the refinements; all approved with changes. Their
unanimous cuts (a second calendar on the current month, weekday averages) are
applied here.

## The design

```
 2026 · 13 AUG TO TODAY                                  (eyebrow, existing)
 You focused 212h across 41 days.                        (headline, existing)
 5h 10m per focused day                                  (facts, existing)

     Aug      Sep         Oct         Nov
 M   ▪ ▪ ▪    ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ □ □
     ▪ ▪ ▪    ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ □ □      one cell per day,
 W   ▪ ▪ ▪    ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ □ □      weeks as columns,
   ▪ ▪ ▪ ▪    ▪ ▪ ▪ ▪     ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ □ □      Monday at the top
 F ▪ ▪ ▪ ▪    ▪ ▪ ▪ ▪     ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ □ □
   ▪ ▪ ▪      ▪ ▪ ▪ ▪     ▪ ▪ ▪ ▪ ▪   ▪ ▪ ▪ □ □
   ▪ ▪ ▪      ▪ ▪ ▪ ▪     ▪ ▪ ▪ ▪   ▪ ▪ ▪[▪]□ □      [ ] today, □ still to come
 Focus in a day  ▫ none ▪ under 2h ▪ 2 to 5h ▪ 5 to 8h ▪ 8h or more  □ still to come
 Sun 15 Nov (today) · 1h 5m so far                       (readout, one line)

 Nov ●  ┌──────────────────────────────────────────────────────────── › ┐
     │  │ 61h 10m across 9 days so far.                                 │
     │  │ Thu 12 Nov was your longest day yet, at 9h 20m. 15 days left. │
     │  │ ▬▬▬▬▬▬▬▬▬▬ ▬▬▬▬▬▬▬   ● Coding 58%  ● Deep work 42%             │
     │  └────────────────────────────────────────────────────────────────┘
 Oct ●    74h 30m across 14 days.                                     ›
     │    Your biggest month so far, up 63% on September.
     │    ▬▬▬▬▬▬▬▬ ▬▬▬▬▬▬▬▬   ● Coding 50%  ● Deep work 50%
 Sep ●    45h 40m across 11 days.                                      ›
     │    ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ ▪   ● Deep work 98%  ● Other 2%
 Aug ●    30h 40m across 7 days.                                       ›
          You started on 13 Aug.
          ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬   ● Deep work 100%
```

Figures above are samples.

### 1. Headline

Unchanged. The existing `StoryHeadline` (eyebrow, sentence, facts) in
`HistoryTreeColumn` stays as the first thing in the column.

### 2. Day grid (replaces the "Each day" chart)

- Data: focus per day from `historyDays`, the same series the chart uses, with
  today's live figure as the tree already patches it.
- Shape: one block per calendar month. Inside a block, weeks are columns and
  weekdays are rows, Monday first, from `periodCalendar`. A month label sits
  above each block; the first block and each January also carry the year when
  the grid spans two years. Weekday letters (M, W, F) sit left of the first row
  of blocks.
- Range: from the month of the first recorded day to the current month, at most
  the trailing 12 months.
- Cells at 100% zoom: 12 points square, 3 point gap, radius 3, 14 points between
  blocks. At most six blocks in a row; more wrap to a second row of whole
  months. If a row of blocks does not fit the column, it wraps by whole months.
  Cells never shrink below 12 points.
- A day before the first recorded day is not drawn. A day after today, within
  the current month, is drawn as an outline. A recorded day with no focus is
  the "none" fill. Today carries a ring in the primary ink.
- Steps (fixed, half-open): none = 0; under 2h; 2h to under 5h; 5h to under 8h;
  8h or more.
- Colour: one hue, `Tokens.Colour.focus`, in four strengths over the "none"
  fill. Rules the tokens must meet on the canvas and the card, in both
  appearances: lightness strictly increases with focus; the lightest filled
  step is at least 2:1 against its surface; neighbouring steps differ by at
  least 1.3:1. Starting strengths that meet this (measured): light 46%, 64%,
  82%, 100%; dark 35%, 55%, 76%, 100%.
- Legend: always visible under the grid, in words and hours, as sketched.
- Readout: one line of fixed height under the legend. At rest it reads today
  ("Sun 15 Nov (today) · 1h 5m so far", or "no focus yet"). Pointing at a cell
  shows that day ("Thu 12 Nov · 9h 20m", "no focus", or "still to come").
  It never changes the layout. Cells have no tooltip; the readout is the
  tooltip.
- Click: a day opens that day (`navigation.openHistory(day:)`, as the chart
  does now). A month label opens that month's row.

### 3. The spine

Depth-0 rows of the tree, newest first, as today. What changes is how they are
drawn.

- Gutter: each depth-0 row has a short period label in a gutter left of the
  spine, right-aligned, in the body role and supporting ink: "Nov" for a month,
  "2026" for a year, the day's short weekday for a day, the range ("9 to 15")
  for a week. The gutter is as wide as the widest label at that level.
- The row whose period contains today is the one card (`StoryStyle.card`,
  radius 13, entry-card padding, hairline). Every other
  depth-0 row is a quiet row: no fill, no border, the existing hover tint.
  This replaces `isCard = depth == 0 && level != .day`.
- Line one, in the rowTitle role: "**61h 10m** across 9 days." The figure uses
  the focus ink the headline uses; the rest is primary. The current period ends
  "so far." A period with no focus reads "Nothing focused." and stays disabled
  as now. The period name is no longer repeated in the row; the gutter says it.
- Line two, body role, supporting ink, only when a rule below applies.
- Category bar: thin, segments in category colours with a gap, labels beside it
  with a dot each. History rows only: a share that rounds below 3% folds into
  "Other" (grey), so no "0%" label can appear. When two neighbouring segments
  share a hue (the owner can give two categories one colour), the second is
  drawn at reduced strength; the labels still tell them apart.
- A chevron at the trailing edge shows the row opens. Opening a row unfolds its
  children beneath it exactly as now, with the same motion.
- Daily bars and the "So far" chip leave these rows. The grid shows the days,
  and "so far" is in the sentence.

### 4. Line two: which fact

At most two clauses, chosen in this order. All computed in Core.

1. Record day: the period contains the longest focused day of the whole record,
   and the record has at least 14 focused days:
   "Thu 12 Nov was your longest day yet, at 9h 20m."
2. Biggest period: among at least three depth-0 rows, this one has the most
   focus: "Your biggest month so far".
3. Change: this period and the one before it are both complete (not the current
   period, and not cut short by the first recorded day) and differ by 10% or
   more: "up 63% on September" or "down 20% on September". Stated plainly,
   never with a judgement.
4. Start: the period contains the first recorded day: "You started on 13 Aug."

The current period also ends with the days left in it ("15 days left."),
omitted at zero. With no fact, there is no second line.

### 5. States

The existing top rule decides what the depth-0 rows are; the grid follows it.

| Record | Depth-0 rows (unchanged rule) | Grid |
|---|---|---|
| Nothing recorded | none | the existing "Nothing recorded yet" tile, no grid |
| All within this week | days | none: the day rows are the picture, and stay drawn exactly as they are today |
| All within this month | weeks | one month block |
| All within this year | months | one block per month from the first recorded month |
| Longer | years | trailing 12 months, two rows of six |
| Any search, app or category filter | unchanged | not shown, as the chart is not shown now |

The gutter, the one card and the new row lines apply to week, month and year
rows at depth 0. Day rows at depth 0 are untouched, so no day is drawn twice
in a first week. (An earlier sketch showed a seven-cell strip there; it is
dropped for that reason.)

Any active search or filter (`historyFilter.isActive`) already swaps the
headline, chart and tree for the results column. So the grid, the rows and the
line-two facts are only ever shown unfiltered, and "the whole record" means
all of `historyDays`. No second, unfiltered series is needed.

### 6. Interaction

- Pointing at any row of the tree, at any depth, or at a month block or its
  label, keeps the cells whose days fall inside that period at full strength
  and lowers the others; month labels stay fully legible. The link is by date
  overlap alone: a week row marks its seven cells, a year row marks whichever
  of its months are in the grid, and a row with no days in the grid changes
  nothing. The row that keyboard focus is on links the same way.
- Keyboard: unchanged. The tree's existing focus proxy (arrows, Return, Escape)
  already reaches every month, week and day, so every day in the grid can be
  opened without a pointer. The grid adds no second focus zone. Three of the
  five panel models asked for arrow keys inside the grid; that is left out to
  keep one keyboard path, and can follow later.
- Context menus on rows: unchanged.

### 7. Accessibility

- Each month block is one element: label "November 2026", value the same
  sentence as its row. Its children are one button per recorded day, labelled
  with the date and the spoken duration, opening that day, as the chart's
  children do now.
- Rows keep `HistoryRowText.spoken` with the new sentence, level, and expanded
  or collapsed.
- The legend and readout are text. Step, today and "still to come" are also
  distinguishable without colour: ring for today, outline for days to come.
- No text under 10 points. Increase Contrast adds a hairline to filled cells.
- Reduce Motion: the hover link changes without animation.

### 8. Motion

No entrance. The hover link uses the app's existing hover timing. Opening and
closing rows keep `Tokens.Motion.reveal`, `unfold` and `dismiss` as they are.

### 9. Words

| Where | Words |
|---|---|
| Legend | Focus in a day: none, under 2h, 2 to 5h, 5 to 8h, 8h or more, still to come |
| Readout | "Sun 15 Nov (today) · 1h 5m so far"; "Thu 12 Nov · 9h 20m"; "no focus"; "no focus yet"; "still to come" |
| Row | "61h 10m across 9 days so far."; "74h 30m across 14 days."; "across one day."; "Nothing focused." |
| Removed | "Each day", "Click a day to open it", "average day", "So far" chip, "N days · best …" |

## What it touches

- `Sources/Surfaces/History/HistoryTreeColumn.swift`: `overviewChart` becomes
  the grid.
- `Sources/Surfaces/History/HistoryTreeRow.swift`, `HistoryPeriodCard.swift`:
  gutter, the one card, quiet rows, the new lines.
- `Sources/Surfaces/History/HistoryDayChart.swift`: `HistoryResultChart` stays
  for search results; only the overview stops using it.
- New Core: the grid model (blocks, cells, steps), the line-two facts, the
  "Other" fold. New Design: ramp tokens.
- `SessionStore+HistoryTree.swift`: read models for the grid and facts, cached
  with the tree and patched for today as rows are.
- `DESIGN.md`: the History journal and colour paragraphs, in the same change.
- Checks: `HistoryOverviewChecks` and `HistoryTreeChecks` follow the new
  drawing; new checks for step boundaries, block layout across month and year
  edges and time zones, each line-two rule and its absence, the "Other" fold,
  and the ramp's contrast rules. Snapshots: the History scenarios in light and
  dark at 980 and 1,160 points, plus first-week, one-month and multi-year
  fixtures.

## For the owner to settle

1. Grid colour. This design uses `Tokens.Colour.focus`, which in code is the
   action blue (the "Each day" chart and the timer are blue today). The mockup
   showed indigo, and `DESIGN.md` still says "Focus identity is indigo, separate
   from blue action." The code and that paragraph disagree. Default here: follow
   the code, and correct the paragraph.
2. Fixed steps (2h, 5h, 8h). Simple and honest, but someone who focuses an hour
   a day sees one shade. The alternative is steps drawn from the person's own
   range, with the legend still in hours.
3. Decreases ("down 20% on September") are shown. The alternative is to show
   increases only.

## Left to the builder

File and type names, how the grid is laid out in SwiftUI, cache keys, exact
token names and strengths within the stated rules, the gutter width mechanism,
and the VoiceOver API used for the blocks.
