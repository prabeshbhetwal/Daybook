# History journal and a smaller type scale

Date: 2026-09-29
Status: approved in conversation, awaiting spec review

## Why

1. **The app reads too big.** Text, controls and the Day page's cards feel oversized. Nothing grew recently: the window still opens at 1160×780 and the type scale is unchanged since 2026-08-31. The scale itself runs a step above standard Mac apps (rows 15pt against macOS's 13pt, a 25pt story headline, 30pt figures). The owner's Interface density is already Compact, and Compact changes spacing only, never text.
2. **History is cluttered and hides the work.**
   - The rail mixes three time frames at once: the picked day, all-time totals and "this month so far".
   - The chrome has four navigation controls: back, range pills, ‹ ›, and the date menu.
   - The eyebrow can contradict the range ("12 months" selected, "1 MONTH · 1 – 30 SEP" shown).
   - Charts grow to fill space instead of carrying information: three full-width week bars, or one small calendar over an empty page.
   - The sessions themselves only appear after picking a day.

Goal: History answers "what did I do, when, for how long" at a glance, with every detail one click away and each fact shown once (the 2026-09-28 redundancy rules and `RedundancyChecks` still apply).

## Decisions

| Question | Decision |
|---|---|
| Size fix | One smaller scale for everyone. No new setting; Compact keeps changing spacing only. |
| History's job | A journal plus a summary |
| Moving through time | One scrolling journal back to the first recorded day. No range pills, no ‹ › paging, no custom span. |

This replaces the rolling 7 days / 30 days / 3 months / 12 months ranges chosen on 2026-09-28.

## 1. Type scale

`Tokens.Typography.Size` in `Sources/Design/DesignTokens.swift`:

| Step | Now | New | Used for |
|---|---|---|---|
| micro | 9 | 9 | axis ticks, calendar dots |
| smallLabel | 10 | 10 | chips, badges |
| ring | 11 | 11 | ring label |
| metadata | 12 | 12 | secondary text |
| control | 13 | 13 | AppKit controls, fields |
| row | 15 | 14 | card titles, list rows |
| section | 17 | 15 | section titles, period label |
| headline | 23 | 19 | strip timer, rail headings |
| page | 26 | 22 | page titles |
| metric | 30 | 24 | big figures in tiles |
| timer | 46 | 36 | live timer |

Also:
- `StoryStyle.headline` goes from 25 to 20 (`Sources/Design/StoryStyle.swift`).
- `StoryLayout.railWidth` goes from 336 to 300 (`Sources/Surfaces/Story/StoryView.swift`).

The scale stays strictly ascending, so `CompactControlsChecks`' scale check holds. Only the `GalleryView` debug surface and one `DashboardCharts` label use system text styles, and both are left alone.

## 2. History

### Chrome (History only)

`‹ Today` · **History** · `Jump to date` · Start focus · Settings

- **Jump to date** opens the existing `DayPickerCalendar` in single-date mode, limited to recorded days. Picking a day scrolls the journal to it and selects it.
- The range pills, the ‹ › paging, the span label and the custom-span picking all go.

### Column: the journal

The search bar (`HistoryFindBar`: field, app menu, category menu, Clear) stays pinned at the top of the column. ⌘F still focuses it from anywhere.

Below it, newest first, back to the first recorded day:

- **Month header**
  - Row: `September 2026` · `14h 20m focused · 7 days · 2h 2m per focused day`
  - Under it, one thin bar per calendar day of that month, height by focus. The bars have no labels; the day rows carry the dates.
  - Clicking the header selects the month.
- **Day header:** `Mon 28 Sep` on the left, the day's focus total on the right. Today reads `Today`.
  - Click selects the day; double-click opens its story (`navigation.openDay`).
- **Session row:** category colour dot · `8:30 – 11:35` · name · category chip · length.
  - The category chip only shows when the session is named; an unnamed session's title already is its category.
  - A second line (secondary text, one line) shows up to three apps from that session, then the first line of its note in quotes.
  - A running session shows `in progress` in place of its length.
  - Click selects the session; double-click opens its day's story.
- **Break row:** grey dot · time · name or "Break" · length.
- **Days with app use but no session:** one line, `Recorded app use only · 1h 5m`.
- **Runs of empty days:** collapse to one line, `22 – 25 Sep · nothing recorded`. A single empty day reads `Tue 23 Sep · nothing recorded`.
- **Footer** after the first recorded day: `On record since 22 Sep 2026 · 14h 20m focused · 7 days · 7 sessions · longest streak 7 days`.

Each total appears once: month totals in month headers, day totals in day headers, session lengths on rows.

**Search:** an active query or menu filter narrows the journal in place.
- Only matching sessions show, under their day and month headers.
- In that mode the headers carry the totals of the matches, and a line under the search bar reads `12 sessions match · 8h 20m of focus`.
- No matches shows the existing "No matching sessions" empty state.
- Clearing search restores the full journal at the same selection.

**Empty archive:** the existing "Nothing recorded yet" tile with its Start focus button.

### Rail: only what is selected

The rail heading names what it describes. It never mixes time frames. The default selection is the current month; selection changes only by click or Jump to date, never by scrolling.

- **Month selected**
  - Focus by category: `CategoryShareBar`. For the current month it also shows "where each lands in the day".
  - Best two hours, with how much focus fell there.
  - Category goals met: the existing goal-rate rows.
  - Top apps: `StoryAppRow`, up to the menu-bar app count.
  - Last 12 months: a small bar chart ending at the selected month, with the selected month highlighted. Clicking a bar scrolls to that month and selects it.
  - Current month only: "This month so far" with Pace, Focus quality and Continuity (`InsightSurface` for `.month`), or the existing insufficient-evidence line.
- **Day selected**
  - The date, its focus as a figure, recorded app use and longest stretch.
  - The day strip with its clock axis (`HistoryDayStrip`, `HistoryStripAxis`).
  - Apps.
  - Full notes. The journal only shows each note's first line.
  - `Open as a story ›`.
  - No session list here: the journal already shows it.
- **Session selected**
  - Name, category, time range, length.
  - Its stretches, when there are more than one.
  - Its apps (`StorySessionDetail.apps`).
  - Its full note.
  - `Open its day ›`.

A selection that disappears (removed session, filter hides it) falls back to the month it was in.

## 3. Code

### New

- `Sources/Surfaces/History/HistoryJournal.swift`: the column. The search bar is pinned above a `ScrollViewReader` + `LazyVStack` of month sections, with day groups, session and break rows, and the footer.
- `Sources/Surfaces/History/HistoryJournalRail.swift`: the month, day and session rail content.
- `Sources/App/SessionStore+Journal.swift`: the journal read model.
  - Months come from `historyDays` grouped by calendar month, down to `historyArchiveFacts().firstDay`.
  - Per-month totals, focused days and daily bars come from `historyArchiveFacts().focusByDay`, which is already cached per evidence revision.
  - The Last 12 months chart reads the same source.
  - Day rows come from `storyDayProjection(on:)`, which is cached per day and read only for days on screen. Session apps come from its `sessionDetails`.
  - Month rail facts come from the existing `insightReading(scope: .month, anchoredAt:, limit: 1)`.
  - A filtered journal is built from `historySearchHits` called with `limit: .max`, since the journal renders lazily.
- `HistorySelection` (`month(Date)`, `day(Date)`, `session(UUID, day: Date)`) on `MainWindowModel`, plus `jumpToHistoryDay(_:)`.

### Changed

- `MainWindowModel`: drop the `HistoryRange`/custom-span/paging state (`historyRange`, `historySpan`, `pageInsights`, `setCustomHistoryRange`, `insightAnchor`, `insightShownCount`, window labels) and add the selection above. `InsightRange` stays as the grouping type that `InsightSurface` and period projections use.
- `StoryChromeBar`: the History bar described above.
- `MainWindowView`: host `HistoryJournal` + `HistoryJournalRail` in place of `InsightsView`.
- `FirstRun` tour: the History step anchors on the search bar and the journal.
- `Snapshotter`: History scenarios for the journal with a month, a day and a session selected, plus search. Drop `selectHistoryRange`.
- README, `docs/usage.md`, `DESIGN.md` and the History screenshots.

### Retired

These move to `_trash/`, which `.gitignore` already covers; the repo history keeps them:
- `InsightsView` (with `InsightRangeReading`, `InsightPickedPeriodCard`, `InsightPeriodStory`)
- `InsightTrendChart`, `InsightMonthCalendars`, `InsightDayStrips`
- `HistoryFindResults`, `HistoryHitRow`, `HistoryHitMonth`
- `HistoryArchiveTiles`, whose facts move to the journal footer and the Month rail
- `HistoryDayRow`, `HistoryDayPreview`, whose content moves to the Day rail

A file is only retired once nothing references it. The self-test build fails otherwise.

`InsightHourGrid` is retired too; its static `hourLabel(_:)` helper moves into `HistoryJournalRail.swift`, where the best-hours tile and the day strip axis use it.

### Speed

- Only on-screen days build their projection.
- Past days come from the per-day cache.
- While a session ticks, only today's day group re-reads. Month headers read cached archive facts, not projections.
- The journal must not rebuild every second: pin this with an `EfficiencyChecks` compute counter, as `insightReadingComputeCount` does today.

## Verification

Self-tests (`./build.sh --test`, run unsandboxed because `sips` fails in the sandbox). The count stays at or above today's baseline once the retired checks are replaced. New or rewritten checks pin:

1. The journal lists months and days newest first, down to the first recorded day and not past it.
2. Each month total, day total and session length appears once. `RedundancyChecks` covers the journal.
3. The rail shows exactly one scope, and its heading names it.
4. Search narrows the journal to matching sessions and totals the matches. Clearing restores it.
5. Jump to date scrolls to and selects that day. ⌘F focuses the search bar.
6. A run of empty days renders as one line. An app-use-only day renders its line.
7. A running session shows `in progress` and only today's group re-reads per tick.
8. The type scale stays strictly ascending, with the new values.

Render evidence (snapshot matrix, light and dark, at 980 and 1160 wide):
- The Day page before and after the scale change.
- History with a month, a day and a session selected.
- History while searching.
- History empty.

## Out of scope

- Keyboard stepping through the journal (↑/↓): add when asked.
- A text-size setting.
- Changes to the Day page's structure. It only picks up the new scale.
