# Daybook Story design system

## Authority

The final **Daybook - Day as a Story.dc.html** in the supplied research
handoff is the visual reference. Earlier prototypes are alternatives. Native
macOS behaviour, accessible contrast and truthful recorded evidence take priority
over unsupported sample content. This document records the implemented remediation
language. The [original verification report](docs/reviews/2026-08-31-story-remediation-verification.md)
and [interaction follow-up](docs/reviews/2026-08-31-story-interaction-verification.md)
record the tested behaviour and remaining manual-verification limits.

## Composition

A persistent native chrome row holds day navigation (History: Jump to date)
and session controls. A readable Story column sits beside a 300-point supporting rail.
The canvas is warm off-white (`#FBFAF8`) with white entry cards; the rail is a
subtle neutral layer over the warm base. Dark appearance retains the same
hierarchy, without putting white labels on insufficiently dark fills.

Column insets: 26 top, 30 horizontal, 34 bottom. Rail insets: 22 top, 20 horizontal,
30 bottom, with 14-point tile gaps. These are reference-specific tokens, not a
reason to change every legacy surface's spacing.

## Type and colour

Use the native system typeface. Type is set by role (`Sources/Design/Typography.swift`):

| Role | Size and weight | For |
|---|---|---|
| display | 36 semibold, rounded | the live timer |
| title | 22 semibold | a page naming itself |
| figure | 24 semibold, rounded | the number a tile exists to show |
| headline, clock | 20 semibold; the clock rounded | the story sentence (560-point measure); a strip's live clock |
| heading | 15 semibold | sections, sheets, rail headings, a day heading search results |
| rowTitle | 14 medium | a session, setting, category or History month, and its figure |
| control | 13 regular | fields, menus, a paragraph set for reading |
| body, label | 12 regular; 12 semibold | supporting text and durations; card labels, text actions, day rows |
| caption, eyebrow | 10 semibold; 10 bold capitals | chips, badges, chart labels; the line above a headline |
| ring, microFigure, micro | 11 rounded; 10 rounded; 9 bold | a ring's label; calendar figures; tiny marks |

The scale is 9, 10, 11, 12, 13, 14, 15, 20, 22, 24 and 36. A weight changes only
to show state; the menu bar panel steps each title down one role.
Values use monospaced digits. Prose wraps; diagnostics never truncate silently.

Focus identity is indigo, separate from blue action. The reference's `#4E4CCC`
is used for light-appearance emphasis; dark-appearance text uses `#B6B3FF`
to stay readable on dark cards instead of copying a low-contrast saturated fill
into small labels. Action blue is `#0071E3` / `#75B5FF`. Work types retain stable
identities; app colours are consistent within
the day or month shown. Colour never implies goal credit where only focused duration
is known. Native controls preserve visible keyboard focus.

## Components

- History journal: one list, newest first. A month header carries the month's
  totals over a thin bar per day; a day header carries its focus; a session row
  carries time, name, category, length, apps and the first line of its note.
  Runs of empty days fold into one line. The selected row is tinted, and a
  month, day or session selection sets what the rail describes.
- Entry cards: radius 13, 13-point vertical / 15-point horizontal padding,
  subtle hairline and shadow. The entire header toggles detail.
- Rail tiles: radius 14, 15-point vertical / 16-point horizontal padding.
- App row: icon, name and duration on one line; thin full-width share bar below.
- Entry detail: a matched pair of flexible columns for apps and **Shape of it**
  within the supported 980-point minimum shell. No fabricated activity waveform
  or typing claims. Meetings use a compact evidence paragraph and app-duration
  chips; current work uses a short coverage sentence beside a compact chart.
- Calendar: picks one day. Each date shows its focus, or a 4-point dot when
  only app use was recorded. A tick marks a met goal, and the month's sum sits
  in its header. The same figures are in each day's spoken label.
- Preferences: compact bounded native sheet with five groups, backed controls
  and contextual search. Native modal sheets block parent interaction and Escape
  dismisses. History remains searchable and opens historical stories explicitly.

## Chrome bar

One row: a slot for the way back, the workspace's controls, the session
control, Ask, Settings. The slot is the width of one round button and is empty on
the Story; History puts a bare back arrow in it. The Story's controls are its
day arrows and date, with a History link; History's is Jump to date, which
opens the calendar. The bar holds controls and the way back, never a title, and
History's search heads its page rather than sitting in the bar. The
session control never wraps.

Ask is a capsule, not a circle: the sparkles and the word "Ask", because an
icon alone would leave Ask as hidden as ⌘K. The sparkles take the
`askSparkles` gradient; Apple's Apple Intelligence glyph may only name
Apple Intelligence, so it appears only in the Ask sheet's line saying who
answers. Short of room, the word goes and the sparkles stay. The button is
absent on a Mac that can never run Ask and when its Settings switch is off.

## Vocabulary

- Corners: bar 3, mark 4, swatch 5, control 7, well 9, nested 12, panel 16;
  entry cards 13 and rail tiles 14 keep the reference's own radii.
- Icon actions are 28-point circles everywhere: the chrome's back, period
  and Settings buttons, the strip's pin and close.
- Text actions inside the app — the chrome's links, "Show all visits",
  "Undo", "Retry" — share one link style: the label role in the action
  colour with a hover tint. Native bordered buttons remain in native sheets.
- Type comes only from the roles; `build.sh` fails a raw size, a system text
  style or a reweighted role. Section headers are headings; labels inside a
  card are labels, in sentence case; a page names itself with the title role.
- Errors and refusals use the danger token, never a raw red.
- The chrome's period reads the same in Story and Insights: `Today`,
  `Yesterday`, `Mon 31 Aug`; `31 Aug – 6 Sep`, with the year only when it
  is not this year; `September 2026`. The session control is a dot and a
  clock; it carries a word only when that word names a different act
  (`Review away`).

## Measurement language

Focus time means logged session work after the state machine excludes pauses and
uncounted absences. It is not a claim that keyboard or app activity corroborates
every minute. The day headline therefore says **You've logged [duration] across
[count] focus sessions**, and the On this Mac card beside it gives **recorded app
use**. These can legitimately differ. Goal credit is their qualifying intersection.
Missing recording coverage is a separate limitation, never added to observed use.
Period bars and their average remain tracked; focus headlines and averages use
focused days only. Integrity notices precede the figures they qualify.

## Interaction and motion

Inline disclosures stay visually joined to their headers. Editing receives
keyboard focus and exposes save errors. Undo remains available after changing a
focus session to Break. Hover and press feedback are restrained; reveal/selection
transitions respect Reduce Motion. Do not choreograph everyday page loading.

### Activity entry: one name, optional classification

The editable activity field and its trailing suggestion menu form one control.
Its prompt is **Choose an activity or type your own**. The menu groups recently
started activities separately from built-in suggestions. Choosing an item fills
the field and brings text focus back to it; it does not start the timer. Return
or **Start focus** explicitly begins the session. The separate **Work type**
control names its purpose, so it cannot be mistaken for activity suggestions.
In the 300-point menu-bar presentation the shorter prompt is **Choose or type
an activity**. Work type sits above its picker and Start retains a single-line
label; compactness must not clip the prompt or wrap the primary action.

Remember up to 20 started names locally, most recent first, trimming whitespace
and deduplicating case-insensitively. Keep their work type with them. Unsaved
drafts are not remembered; a very short started session is still a reusable name,
even if it is below the threshold for a history record. History-derived names
also remain available. This provides the convenience of a chooser without making
free text a second-class option or starting work by accident.

### Expanded entries and colour

**Shape of it** is eight equal elapsed-time columns, separated by 2 points and
up to 44 points high. Height is the union of recorded app-use coverage inside
that interval divided by its duration, never the sum of overlapping records.
Zero coverage stays as a 2-point neutral baseline, not an invented waveform.
The predominant app uses the work-type colour; other apps use teal. The legend
states **Recorded app use, not typing intensity**, with exact times and durations
available to accessibility and help. A short sentence qualifies missing coverage.

The chart sits beside app names, durations and thin share bars, following the
reference's two-column anatomy. It explains the session without a second panel
or a long block of prose. A current session uses a 130-point compact chart,
an indigo duration and a softly tinted timeline halo. A Meetings card uses amber
for its type badge, dot and evidence chips. Do not reproduce sample claims about
participants or keyboard input that the recorder cannot establish.

**Rename**, **Change type** and **Continue this** are real buttons with neutral
soft fills, 7-point radii, 11-point horizontal / 5-point vertical padding and a
minimum 28-point height. The label role keeps them secondary to the title.
Pause uses a restrained work-type tint. Hover, pressed, disabled and keyboard
focus states remain visible. The actions stay in the entry they affect; name
and type changes explicitly disclose that they apply to the whole thread.

### Notes and power

**Add note** opens a small inline editor inside the expanded entry; there is
no permanent empty box. The note is saved by exact stretch identity and lives
in a sidecar beside the session archive, so editing it can never change
recorded time, session equality or an Undo. Command-Return saves only the
focused editor. A power line beneath the duration — **Battery · 78% → 64%**,
**Plugged in · 64% → 81%** — is drawn only from observations made while the
stretch ran; plugged in and charging are distinct states, a restored or
backdated start is marked partial, and a stretch with no observation shows
no power line rather than a placeholder. Percentage change is never presented
as energy used by an app.

### Activity rules and the quiet choice

Rule automation is opt-in and, when on, replaces the legacy heuristic. The
quiet choice is a soft well inside the session controls and the menu panel:
the question naming the candidates (for example **Coding or Research?**), one factual line stating that the
recorded external-app interval is credited once and that time in
Daybook is excluded, and bordered answers. It never modally interrupts.
An automatic start is announced by the HUD with its reason and an **Undo**
bound to that exact record; Undo carries a cooldown so the same guess cannot
return at once. The rule editor validates custom dwell in whole seconds and
scrolls its injected application picker; missing applications are labelled,
never hidden.

### Arranging the rail

**Arrange cards** is one control for the group. Only while arranging do cards
accept a drag; each also offers Move up / Move down for the keyboard. The
stored order is repaired on read — unknown cards dropped, missing ones
appended — so an arrangement survives a release that adds or removes a card.

### Decisions and Undo

A successful decision becomes one compact row at the affected interval: green
check, result, time range and blue **Undo**. Its pale green wash and hairline
confirm that the action was saved; green is never shown for a failed save. The
classified interval is not rendered again as a duplicate break card. Error and
retry messages remain visible without discarding the original record.

Every answer surface, including the menu popover and quick/full prompts, shows
**Answer not saved** with a local retry action when storage refuses the write.
The question and its entered reason remain visible. The quick prompt cancels its
automatic fade after failure. Retry belongs to the specific pending interval and
answer, not to an unrelated correction made elsewhere in the app.

Undo removes only the chosen classification or its exact credited seconds. It
does not rewind the timer, erase later work or overwrite an intervening edit.
The same row becomes an in-place question with **Count as focus**, **Call it a
break** and **Leave uncounted**. A new answer applies to that historical interval,
not to whatever the user happens to be doing now. One latest receipt is retained
across relaunch; this is a recoverable last action, not an unlimited undo stack.
Stable action identities and exact-record comparisons make interrupted saves
retryable without duplicating the interval. Ambiguous or conflicting evidence
fails closed rather than being silently rewritten.
If the interval spans calendar days, the green row declares the full duration
and multi-day scope before Undo is offered, both visibly and in its accessibility
hint. A locally clipped time range must not imply a locally clipped mutation.

### Reading order and bounded supporting content

The current/latest session comes first; earlier work, named rest and recording
gaps continue downwards. Core chronology remains ordered by time for accounting;
only the presentation reverses it. This keeps current controls reachable without
scrolling to the end of a long day. Time labels make the descending order clear.
Only the actual current stretch exposes Pause and End session. An earlier
stretch in the same thread can be corrected but does not imitate live controls.

The Apps tile always shows at most four apps, sorted by recorded duration, with
**Top 4 of [count]** when applicable. There is no expand-all control or nested
app-list scroller. Individual apps still open their scoped recorded visits.
The fixed cap keeps the supporting rail subordinate to the Story.

**Open Daybook** reveals the existing Story date and dismisses
an old secondary sheet. It does not open session controls merely because a timer
is running. **Session controls** and its explicit keyboard command still open
the operational sheet. Inspecting history and managing a timer are separate
intentions, so opening the app must not choose the latter for the user.

## Verification

Use isolated fixtures and inspect actual rendered content in both appearances at
980 and 1,160 points. Include native sheet Escape/focus, Light → System and
Dark → System, historical drill-in, live period totals, sparse recording and long
labels. A passing image-generation command is not a visual acceptance result.
Fixture stores disable the operational ticker, so real Mac idle samples cannot
change an injected-clock scenario during inspection. Production retains its
existing single ticker and presence rules.
Native UI automation uses `scripts/build-fixture-app.sh`, whose executable has
no production entry point. A command-line flag alone is not an isolation boundary
when a UI tool can relaunch the bundle without arguments.
