# Daybook Interface Redesign — Design

**Date:** 2026-08-29
**Status:** Approved design direction; ready for main-thread review before implementation.

## 1. Decision

Daybook will receive a complete interface redesign built around a calm desktop
information architecture: a centred horizontal tab rail, an intentionally quiet
top-level hierarchy, restrained tonal surfaces, and one dominant piece of information per
screen.

The interaction grammar uses a calm tab rail, contextual secondary controls, dense but
readable rows, and data that earns its visual weight. Daybook remains a private
focus-and-time-continuity product with its own purpose, content and cooler focus accent.

The global tabs are:

```text
Focus  ·  Today  ·  Review  ·  Insights  ·  Settings
```

Selecting a tab changes the working surface below it. The app must no longer present every
metric, chart and list inside one vertically exhaustive dashboard.

## 2. Goals

1. Make the first question on every surface obvious: *what should I do here?*
2. Make the second question honest: *what did the data actually establish?*
3. Give the desktop app a stable tab hierarchy instead of a collection of cards
   competing for attention.
4. Give Settings a first-class global tab where every real configurable behaviour is easy
   to find and explain.
5. Preserve Daybook's hard-won accounting rules, terminology and privacy boundary.
6. Work in light and dark appearance, macOS 13+, direct `swiftc`, SwiftUI, no packages,
   no extra TCC permission, and no new repeating timer.

## 3. Non-goals

- No historical rewriting, smoothing, or reclassification of usage/session records.
- No invented insight, prediction, score, comparison or recommendation.
- No third-party font, asset catalogue, web service, telemetry or account.
- No redesign of the Core → App → Design/Surfaces ownership boundary.
- No control that appears configurable but does nothing.
- No attempt to turn the menu-bar popover into a miniature five-tab desktop app.

## 4. Product principles

### 4.1 A tab is a promise

Each global tab owns one kind of question:

| Tab | The user's question | It must not become |
|---|---|---|
| Focus | What should I do right now? | A historical dashboard |
| Today | What actually happened today? | A goal-setting form |
| Review | How is time changing across days? | A live control surface |
| Insights | What patterns are supported by enough evidence? | A feed of generic encouragement |
| Settings | How does the app behave? | A dumping ground for history and reports |

### 4.2 Truth before decoration

`Focused` means declared focus-session time that satisfies the existing hands-on rules.
`Tracked` or `At the Mac` means observed app-use time; it is not silently presented as
deliberate work. Breaks, Watching, unattended time, legacy-accuracy boundaries and past-day
data retain their existing semantics.

The interface may simplify presentation; it must never simplify meaning.

### 4.3 One dominant visual per screen

- Focus: live time and the next action.
- Today: the day timeline.
- Review: exact tracked time by day.
- Insights: a small number of evidence-backed pattern statements.
- Settings: the selected setting group.

Supporting figures must serve the dominant visual rather than appear as decorative KPI cards.

### 4.4 Calm density

Daybook uses compact rows, low-contrast structure and direct labels; it avoids
decorative darkness, excessive glass and a cleaner-utility visual metaphor.

## 5. Global navigation and shell

### 5.1 Desktop window

The main window is the full application surface. It has a minimum content size of 980 × 680
and a comfortable working size around 1,160 × 780. It may scroll vertically within a tab,
but global navigation and tab identity remain visible at the top.

The shell has three horizontal bands:

1. **Title/status band** — app mark and contextual title on the left; quiet live status on
   the right, such as `Focus active · 42m` or `Today · 2h 10m focused`.
2. **Global tab rail** — a centred five-mode capsule.
   It uses icon + short label at generous desktop widths and label-only compact pills when
   the window narrows. The selected tab is filled; unselected tabs are text-only.
3. **Tab canvas** — the selected tab's single purpose-built surface.

The tab rail is keyboard navigable with left/right arrows after focus enters the control.
`⌘1` through `⌘5` select Focus, Today, Review, Insights and Settings respectively. `⌘,`
opens the main window on Settings rather than a separate form-only settings scene.

### 5.2 Secondary controls

Secondary controls appear only inside a relevant tab, directly below the tab rail or in the
tab header. They use a smaller text-pill grammar.

| Global tab | Secondary control |
|---|---|
| Focus | No secondary navigation |
| Today | Date stepper and calendar; `Today` reset when browsing history |
| Review | `Week` · `Month` · `History` |
| Insights | `This week` · `This month` when both have sufficient data |
| Settings | A vertical settings-group list inside the canvas |

Secondary controls must not be duplicated as a second global navigation system.

### 5.3 Menu-bar item and popover

The menu bar remains the ambient, low-friction entry point. It continues to show the existing
goal-state glyph and, while running, elapsed time. Clicking it opens a compact **Focus
popover**:

- live/idle/paused/awaiting-decision hero;
- one primary action appropriate to that state;
- current daily goal progress and a concise break status;
- at most three resumable threads or quick starts;
- footer actions: `Open Daybook`, `Settings`, and `Quit`.

The popover does not duplicate Today, Review or Insights. `Open Daybook` opens the
main window on Focus by default; a deep link from a specific notification may open the
relevant tab only when that tab directly answers the notification.

## 6. Visual foundations

### 6.1 Colour

The visual mood is **warm precision**: softly warm, near-black depth combined with a cool
blue focus signal. Use dynamic light/dark token pairs rather than hard-coding colours
in views.

| Token | Light | Dark | Use |
|---|---:|---:|---|
| `ground` | `#F7F6F3` | `#1C1919` | full window canvas |
| `surface` | `#FFFFFF` | `#272222` | tab canvas panels and grouped regions |
| `elevated` | `#F0EEEA` | `#332C2D` | selected fields, quiet wells, tab rail backing |
| `line` | black 8% | white 10% | section boundaries and row separators |
| `hover` | black 4% | white 7% | row and secondary-pill hover |
| `focus` | `#3478F6` | `#82AEFF` | selected tab, primary action, live focus state |
| `progress` | `#238D7A` | `#52C3AC` | verified positive progress and goal completion |
| `attention` | `#B9721F` | `#E3A34F` | integrity qualification or awaiting attention |
| `danger` | system red | system red | destructive or irreversible actions only |

The seven-app data palette remains muted and luminance-balanced. Work-type colours remain
fixed across all tabs. The selected tab and primary action use `focus`; data never inherits
that colour merely because it is on screen.

### 6.2 Typography

Use the installed system family only:

| Role | Style |
|---|---|
| Live timer | SF Rounded, 46 pt semibold, tabular digits |
| Page title | SF Pro, 26 pt semibold |
| Section title | SF Pro, 17 pt semibold |
| Metric value | SF Rounded, 28 pt semibold, tabular digits |
| Tab label | SF Pro, 13 pt medium |
| Row title | SF Pro, 14 pt medium |
| Metadata | SF Pro, 12–13 pt regular, secondary colour |
| Technical time ranges | SF Pro with `.monospacedDigit()`; never SF Mono by default |

Uppercase micro-labels are reserved for charts and compact metric context. Long explanations
use normal sentence case and a readable measure rather than all caps or tiny type.

### 6.3 Spacing, radius and depth

Use an 8-point rhythm: 4, 8, 12, 16, 24, 32 and 48. Window-edge padding is 32 on desktop
and 20 at narrower widths. Standard row height is 52; dense historical rows may be 44 only
when all information remains readable.

The main canvas uses open space and aligned groups, not a blanket of cards. A group may use
one surface panel with internal hairlines. Use 16 pt rounded corners for primary panels,
12 pt for nested wells, and a fully rounded capsule only for tabs, filters, tags and primary
compact controls.

### 6.4 Icons and motion

Use SF Symbols with hierarchical rendering. App icons remain real app icons. Use a 5–6 pt
colour dot as a stable app/work-type key where colour carries meaning.

Motion communicates a data/state transition only:

- numeric text transitions for live time;
- a restrained goal-ring fill transition;
- a 160–200 ms selected-tab transition;
- subtle hover backgrounds for rows and pills.

Respect Reduce Motion. No decorative entrance animation, bouncing reward, parallax or
perpetual motion is permitted.

## 7. Focus tab

The Focus tab is the operational surface. It should feel like opening a calm instrument
panel rather than a report.

### 7.1 Idle state

The upper panel contains:

- `Ready to focus` title;
- optional intent field with placeholder `What are you working on?`;
- work-type selector rendered as a compact pill;
- one filled `Start focus` button;
- daily goal ring and honest pace sentence as supporting context, not competing content.

Below it, show only the most useful continuation path:

- up to three `Continue` rows for today's threads when they exist; otherwise
- up to three quick-start rows derived from existing history; otherwise
- a succinct first-run explanation.

Break status appears as a muted line, never a full card when no break is due.

### 7.2 Running state

The upper panel is visually simplified around a single large timer:

```text
42:18
Refactor the parser · Deep work
[Pause]  [Away]  [Stop]
Today: 1h 52m focused of 4h
```

The current stretch is the hero. Total daily focus and goal pace are secondary. Do not show
Tracked, Focused, Sessions, Quality and app-share metric tiles beside the live timer.

Below the hero, show the current thread, relevant app context and next break only when
available. The existing non-blocking absence/away decision remains an explicit state in the
same panel; it does not open a new dashboard layer.

### 7.3 Paused, Watching and awaiting-decision states

- **Paused:** retain the timer and intent, visually quiet it, offer `Resume` and `Stop`.
- **Watching:** explain that the clock is paused quietly and name the observation only when
  the evidence supports it.
- **Awaiting decision:** replace controls with the existing honest decision choices, their
  time range and the explanation that the gap is not counted. Do not hide the decision in a
  modal or present it as an error.

## 8. Today tab

Today is the evidence-led narrative of one calendar day. It owns past-day inspection through
the date stepper and calendar, while the menu-bar popover continues to stay anchored to the
real current day.

### 8.1 Header

The header reads `Today`, `Yesterday`, or the selected date. The subtitle gives only the
most useful verified context, for example `Friday 28 August · 2h 25m focused · 1 session`.
The date stepper and calendar live on the right. Browsing a past day exposes a `Today`
action.

### 8.2 Primary canvas: time ribbon

The day timeline is the dominant visual. It spans the content width, shows app stretches,
gaps, focus brackets and the selected-session highlight. It keeps existing hover, click and
Esc-to-clear behaviour. A selected app/session opens a lightweight inspector below the
ribbon; it does not reflow the entire page.

Gaps, breaks and Watching are visually distinguishable but do not resemble productive time.
Named breaks remain named rest. Timeline labels are direct: app name, time range and
duration.

### 8.3 Supporting groups

Below the ribbon, use two aligned groups rather than a KPI grid:

1. **Sessions** — grouped threads/stretches, time range, work type, duration, app context
   and active indicator when relevant.
2. **At the Mac** — ranked app rows with app icon, stable colour dot, duration, share and
   last-used range.

Then show a compact **Day recap** that may contain:

- focused time and daily goal state;
- tracked time labelled `At the Mac`;
- number of focus sessions;
- longest stretch;
- data-qualified narrative/insights.

The recap must not make Focused exceed Tracked without context. If this can occur because
of known historical/legacy data boundaries, present the existing accuracy qualification
clearly and offer `Reveal data folder` from the relevant Settings area.

## 9. Review tab

Review is period comparison. Its local control selects `Week`, `Month` or `History`.

### 9.1 Week and Month

The header has period navigation, the local control and a short period summary. The dominant
chart is titled **Tracked by day**. Each bar equals the exact canonical tracked total for
that day. The average line is calculated from the same series.

Work-type composition remains a separate donut/list. It must not be stacked into the tracked
bars, because composition is not the same measure as tracked time.

The lower content is:

- a concise period summary: tracked total, active days, average per active day, longest
  focus stretch;
- exact period session log, grouped by date;
- top apps and work type, scoped and labelled correctly;
- a period-wide legacy-accuracy warning when any displayed day needs one.

Clicking a day bar opens that day in Today rather than forcing an expandable chart detail.

### 9.2 History

History is a searchable, chronological record rather than a third chart. It provides:

- calendar/date-range selection;
- grouped day rows with tracked, focused and session count;
- an optional filter by work type or app;
- direct entry into Today for a chosen day.

No export, editing or historical repair is introduced by this redesign.

## 10. Insights tab

Insights is deliberately sparse. It shows a pattern only when its source data exists and the
claim can be stated plainly.

Sections may include:

- **Pace** — current goal pace compared with the personal historical median, only after the
  authoritative active-day minimum is met.
- **Rhythm** — time-at-the-Mac by hour and the busiest verified period.
- **Focus quality** — work-type/context and interruption evidence, never a fabricated score.
- **Continuity** — streak, recent active days and change versus a correctly comparable period.

Each insight states its measure or opens a short `How this is calculated` explanation. When
the data is insufficient, show one useful empty state such as `Keep using Daybook;
patterns appear once there is enough comparable history.` Do not replace missing evidence
with a zero, an unearned comparison or generic motivational copy.

## 11. Settings tab

Settings is a first-class global tab. It uses a two-pane surface inside the tab canvas:

- a compact left settings-group list with SF Symbol and label;
- a right detail pane with grouped controls, explanatory text and a maximum readable measure.

At narrow widths the group list becomes a secondary pill/menu control above the detail pane.
Settings search filters groups and matching control labels.

### 11.1 Settings groups and controls

| Group | Controls and content |
|---|---|
| General | Main-window default tab; compact/comfortable density; open dashboard on launch if supported; menu-bar display preference if supported |
| Focus sessions | Daily goal; default work type; thread continuation and quick-start behaviour where the existing engine supports them |
| Away and breaks | Ask-me threshold; end-session threshold; full-screen prompt threshold; break reminder toggle; displayed explanation of all three fixed break tiers |
| Automatic and rewards | Automatic session toggle; auto-session gap; milestone/reward toggle; clear explanation that automatic records remain undoable/honest |
| Tracking and apps | Record app usage toggle; privacy explanation; app exclusions and app-purpose overrides only when their backing persistence and classification behaviour exist |
| Appearance | System/light/dark appearance; compact/comfortable density; timeline labels; reduced-motion behaviour follows macOS and is not overridden |
| Data and privacy | Reveal data folder; explanation of local-only app names/bundle IDs; accuracy epoch; legacy backup location; history retention only when a real retention mechanism exists |
| Advanced | Build/version diagnostics, evidence-preserving recovery information and clearly separated destructive data actions |

Current real settings — daily goal, away thresholds, full-screen prompt threshold, break
reminders, auto sessions, auto-session gap, rewards, sessions-per-app and app-usage recording
— must migrate with their values and explanatory copy intact. The redesign may add new
preferences only with a real persistence field, clear default and observable effect.

Destructive actions such as reset/remove history remain visually isolated in Advanced, explain
their exact scope, and require explicit confirmation. They never share a row with ordinary
preferences.

## 12. Away prompts, rewards and notifications

Away prompts remain non-blocking and truth-first. The full-screen prompt uses the same visual
language as Focus: one question, its honest time range, four clearly differentiated actions
and no moralising colour.

Rewards remain non-activating and earned by data. They inherit the new focus/progress colour
grammar but never interrupt active work or become a stream of notifications.

## 13. Empty, loading, error and integrity states

Every tab has a designed first-run state:

| Tab | First-run state |
|---|---|
| Focus | Start a session, with a short local-only explanation |
| Today | No activity recorded yet; timeline remains an empty scaffold |
| Review | No comparable days yet; explain that period history builds locally |
| Insights | Insufficient comparable history; do not display invented trends |
| Settings | All real defaults visible and explainable |

Integrity qualifications are visible but quiet: amber icon, one sentence, and a path to
inspect local data. Corrupt/preserved/read-only history must be described as a data condition,
not presented as user failure. The app must never silently downgrade or overwrite evidence.

## 14. Accessibility and macOS behaviour

- Every tab, chart, timeline and setting has an accessibility label that states its measure.
- Selected tab, period and date are announced to VoiceOver.
- Charts provide an equivalent list/table summary.
- Keyboard navigation, Escape behaviour and standard menu commands remain available.
- Do not encode meaning by colour alone; labels, symbols and shape/context accompany it.
- All targets meet a practical 28 pt minimum hit area, with larger primary actions.
- Light and dark screenshots are required for every material state.

## 15. Design-system requirements

The implementation should consolidate visual decisions into the existing Design layer:

- dynamic colour tokens for the new surfaces and semantic states;
- typography and spacing tokens above;
- reusable `TabRail`, `SurfacePanel`, `MetricLine`, `AppUsageRow`, `SectionHeader`,
  `EmptyState`, `IntegrityNotice` and settings-row primitives;
- app and work-type palette rules retained as shared data keys;
- no view-specific colour, font, padding or corner-radius literals except values intrinsic to
  a chart's geometry.

Views consume published `SessionStore` data. They never calculate accounting values or read
raw archive files. Core remains free of SwiftUI.

## 16. Visual verification matrix

The existing snapshot/gallery harness must render, at minimum, light and dark versions of:

- first-run Focus;
- running Focus;
- paused Focus;
- awaiting-decision Focus;
- Today with history;
- Today on a past day;
- Review Week;
- Review Month;
- Insights with enough data and without enough data;
- Settings at every group;
- away prompt quick and full.

Visual review checks hierarchy, clipping, selected-tab clarity, text contrast, empty states,
integrity warnings, keyboard focus, wide/narrow layouts and unchanged semantic values. The
headless test suite continues to prove time accounting; visual tests never replace it.

## 17. Acceptance criteria

- The main desktop window has five global tabs and each tab owns one
  distinct information/task hierarchy.
- Focus is action-first; Today is evidence-first; Review uses exact tracked daily bars;
  Insights is data-gated; Settings exposes every real user-configurable behaviour.
- Focused, Tracked, breaks, Watching, legacy accuracy and past-day semantics remain honest
  and visibly qualified when necessary.
- Work-type composition remains separate from tracked-time comparison.
- Settings contain no non-functional controls and destructive data actions are isolated and
  explicitly confirmed.
- The menu-bar popover remains a compact Focus entry point rather than duplicating the main
  window.
- The new visual system works in light/dark appearance, respects accessibility and reduce
  motion, and uses only macOS/system resources.
- The Core → App → Design/Surfaces boundary, macOS 13 target, direct `swiftc` build and
  existing one-second ticker are preserved.
