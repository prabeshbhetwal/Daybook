# FocusContinuity Story design system

## Authority

The final **Focus Continuity - Day as a Story.dc.html** in the supplied research
handoff is the visual reference. Earlier prototypes are alternatives. Native
macOS behaviour, accessible contrast and truthful recorded evidence take priority
over unsupported sample content. This document records the implemented remediation
language. The [original verification report](docs/superpowers/reviews/2026-08-31-story-remediation-verification.md)
and [interaction follow-up](docs/superpowers/reviews/2026-08-31-story-interaction-verification.md)
record the tested behaviour and remaining manual-verification limits.

## Composition

A persistent native chrome row holds Day / Week / Month, period navigation and
session controls. A readable Story column sits beside a 336-point supporting rail.
The canvas is warm off-white (`#FBFAF8`) with white entry cards; the rail is a
subtle neutral layer over the warm base. Dark appearance retains the same
hierarchy, without putting white labels on insufficiently dark fills.

Column insets: 26 top, 30 horizontal, 34 bottom. Rail insets: 22 top, 20 horizontal,
30 bottom, with 14-point tile gaps. These are reference-specific tokens, not a
reason to change every legacy surface's spacing.

## Type and colour

Use the native system typeface. Story headline: 25-point semibold, maximum
560-point reading width. Row titles: 14 points; secondary metadata: 12 points.
Values use monospaced digits. Prose wraps; diagnostics never truncate silently.

Focus identity is indigo, separate from blue action. The reference's `#4E4CCC`
is used for light-appearance emphasis; dark-appearance text uses `#B6B3FF`
to stay readable on dark cards instead of copying a low-contrast saturated fill
into small labels. Action blue is `#0071E3` / `#75B5FF`. Work types retain stable
identities; app colours are consistent within
the selected scope. Colour never implies goal credit where only focused duration
is known. Native controls preserve visible keyboard focus.

## Components

- Scope control: rounded rectangle, radius 9, neutral selected thumb radius 7.
- Entry cards: radius 13, 13-point vertical / 15-point horizontal padding,
  subtle hairline and shadow. The entire header toggles detail.
- Rail tiles: radius 14, 15-point vertical / 16-point horizontal padding.
- App row: icon, name and duration on one line; thin full-width share bar below.
- Entry detail: a matched pair of flexible columns for apps and **Shape of it**
  within the supported 980-point minimum shell. No fabricated activity waveform
  or typing claims. Meetings use a compact evidence paragraph and app-duration
  chips; current work uses a short coverage sentence beside a compact chart.
- Month: responsive square cells, 8-point gaps, 62-point weekly totals column,
  date and duration together. Intensity is relative focused duration, not goal
  attainment. Foreground is selected from resolved-fill contrast.
- Preferences: compact bounded native sheet with five groups, backed controls
  and contextual search. Native modal sheets block parent interaction and Escape
  dismisses. History remains searchable and opens historical stories explicitly.

## Measurement language

Focus time means logged session work after the state machine excludes pauses and
uncounted absences. It is not a claim that keyboard or app activity corroborates
every minute. The day headline therefore says **You've logged [duration] across
[count] focus sessions**, and its secondary line says **recorded app use**.
These can legitimately differ. Goal credit is their qualifying intersection.
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
minimum 28-point height. Semibold metadata keeps them secondary to the title.
Pause uses a restrained work-type tint. Hover, pressed, disabled and keyboard
focus states remain visible. The actions stay in the entry they affect; name
and type changes explicitly disclose that they apply to the whole thread.

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

**Open FocusContinuity** reveals the existing Story scope and date and dismisses
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
