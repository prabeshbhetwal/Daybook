# Story interaction model

Status: behaviour model approved in chat on 31 August 2026. This written
specification records that approval. Implementation and verification are pending;
it is not a completion report.

Baseline inspected: `73fb2cf` on the main project checkout.

## Purpose and boundaries

Keep the user's reading context intact while making session actions predictable,
reversible and keyboard accessible. Preserve the approved Story design language.
The user's subsequent menu-bar, notes, power-context, chart and app-rule ideas are
separate proposals in
[the companion design note](2026-08-31-session-controls-and-activity-rules-proposal.md).
Those ideas do not revoke this approval or authorise ambiguous time attribution.

Work in the main project directory. Do not create a worktree or push changes.
Preserve unrelated user research files. Use native SwiftUI/AppKit, the existing
direct `swiftc` build, Swift 5 language mode and the macOS 13 deployment target.
Do not introduce a service, package, permission request or repeating timer for
these interaction changes.

## 1. Period stories expand in place

In Week and Month, choosing a day first selects its summary. Activating
**Open as a story** expands that day's story underneath the summary in the same
period view. Its label becomes **Hide story** while expanded. Selecting a different
day changes the child to that day; at most one child story is expanded.

The parent scope, period anchor, chart, supporting rail and totals remain about
the selected week or month. Opening the child must not set the global Day date,
reset the parent to Today or perform an implicit navigation to Day. Changing the
parent period clears a now-out-of-period child selection. Collapsing returns
keyboard focus to the disclosure control and preserves the reader's position.

The child has the same newest-first chronology, corrections, app details and
session actions as Day. Historical entries never acquire running controls simply
because a current thread shares their identity.

### Data boundary

`MainWindowModel` owns navigation and the expanded child date. Date-scoped,
immutable presentation values supply the child's facts, chronology, summaries
and app data. Mutations still use the existing `SessionStore` and engine.

Do not create another `SessionStore` around the same engine: its initialisation
installs callbacks and would displace the parent store. Do not temporarily mutate
`selectedDay` to render the child; that would silently alter other consumers.

Relevant existing code: `MainWindowModel.openStoryDay`, `StorySelectedDayCard`,
`SessionStore+StoryDetails`, `DayStory` and `StoryCanvas`.

## 2. Scope selection and keyboard focus

The selected Day/Week/Month thumb describes the displayed period, not the last
button that received focus. Remove the unmanaged native blue rectangle on this
custom selector. Do not remove keyboard accessibility to hide the symptom.

Use one coherent segmented-control keyboard interaction: a predictable Tab stop,
Left/Right navigation, visible keyboard-only focus and an accessible selected
state. Mouse selection must not leave a stale focus decoration on Day. Retain
meaningful focus cues elsewhere, including form fields and selected calendar days.
Do not change the user's global Full Keyboard Access settings.

## 3. Reversible decisions belong to their entries

The current code retains one `lastAwayDecision`. Earlier break rows therefore
cannot expose the latest-decision Undo control. Replace the presentation's
single-receipt assumption with durable, entry-scoped correction history.

Each recoverable decision displays its saved classification, original interval
and **Undo** in that interval's confirmation row. Multiple saved decisions may
coexist. Renaming another session, answering a later absence or navigating away
must not remove a still-valid earlier Undo.

Undo reverses only the chosen classification or its exact credited seconds. It
must not rewind the running clock, delete subsequent sessions, restore an obsolete
name/type or manufacture app-use evidence. Re-answering operates on that same
historical interval. Multi-day changes disclose their full scope before mutation.

For a legacy break whose original state was never retained, expose **Change
classification** instead of pretending an exact Undo is possible. A change to
uncounted removes that classification without inventing prior focus credit.
Counting it as work requires an explicit, valid attribution and confirmation.

### Persistence and recovery

- Migrate the currently retained receipt without losing its stable action ID.
- Keep source app-use records unchanged.
- Tie each receipt and Retry to the original interval and exact record identity.
- Retain recoverability across relaunch and failed/interrupted saves.
- Fail visibly on conflicting subsequent edits; never overwrite them silently.
- Retention follows the relevant history/correction retention, not a global
  single-action slot. Removing history must also remove its correction metadata.
- Preserve existing capacity-trimming safeguards: historical edits cannot evict
  newer work merely to make space for their temporary replacement records.

Relevant code: `SessionEngine`, persisted away receipts, `SessionCorrectionState`,
`SessionStore+History`, `SessionStore+StoryDetails` and `StoryDecisionRow`.

## 4. One factual duration vocabulary

The 31-second example currently formats its visible caption in seconds but its
tooltip through `SessionShape.duration`, which returns whole minutes. Fix the
source of the inconsistency, not just that tooltip string.

Use a Foundation-level duration presentation contract shared by prose and UI.
Positive sub-second observations display **<1s**, never **0s**; zero-duration
observations do not create app rows or app-switch claims. Seconds remain visible
for short sessions. Non-finite or invalid inputs fail safely.

Recorded coverage is the union of observed intervals within the relevant session
spans. Overlapping/duplicate records cannot inflate the denominator. Descriptions,
captions, tooltips and charts use the same factual projection. Do not claim an app
was used for the entire session when only part of the session was recorded.

Do not describe input gaps as proof of inactivity, app switching as distraction,
or a named break such as Driving as physiological rest. Prefer **recorded break,
not counted as focus**. Preserve the distinction between logged focus, observed
app use and qualifying goal credit.

When independently rounded component figures would appear not to reconcile,
explain the rounding or show appropriate precision. Never change stored seconds
to make rounded labels add up.

## 5. Day summary precedes chronology

Place **About this day** after the day headline and any integrity warning, before
the timeline. It starts collapsed, and the entire disclosure label is actionable.

When expanded, show a concise bullet list of supported facts: session structure,
predominant recorded apps, useful timing information and relevant coverage limits.
Omit empty/redundant claims and do not reproduce a long paragraph with a bullet
prefix. Use no fabricated descriptions of typing, attention or productivity.

## 6. Insights and History are separate reading contexts

Insights has Day/Week/Month scopes and a newest-first sequence of dated summaries.
The selected scope and date must be explicit. Current periods are marked **so
far**. Historical period navigation does not change the current timer or Story's
last-viewed date.

Factual summaries can appear immediately. Pattern/trend cards retain explicit
sample-size and recording-coverage gates, compare like periods and do not turn
one observed day into a weekly habit. Incomplete periods are not silently compared
with complete ones. No empty chart is presented as an insight.

History remains a separate searchable, date-first index. Opening a record reveals
its story in that reading context, with clear return/collapse navigation. Both
surfaces use the same factual projections and mutation boundary as Story; they
are not independent copies of the recording engine.

Keep access through the existing History/Insights commands discoverable. Preserve
the user's main-window state when returning to Story. Do not create a new
standalone application window for either surface.

## 7. Stable Settings and close controls

Settings uses one stable, bounded panel size across normal pages and search.
Category selection must not expand or contract the panel. Keep the liked visual
style, readable fonts and grouped controls. Adjust group spacing/layout so normal
pages fit without a compulsory scroll through a succession of tiny pages.

Scroll only when content genuinely exceeds the available height, such as a small
window, accessibility text sizing, long diagnostics or a long custom-app list.
Do not clip controls or reduce text size to force a no-scroll result. Search and
category controls retain focus and position when results change.

Secondary panel headers use a standard **X** close symbol with a readable
accessibility label and tooltip, Escape support and normal close-command
behaviour. Restore focus to the invoking control. Save/Cancel, inline editing
confirmations and task-specific actions are not indiscriminately renamed.

## 8. Continuation policy

An activity is its trimmed, case-insensitive user-entered name plus work type.
**Coding** and **Browsing** are different activities even when both use Deep work.
One anonymous activity does not silently alias a named one.

**Continue this is available only for the latest ended session of that activity,
within 60 minutes of its last end.** The boundary includes exactly 60 minutes;
future or invalid end dates are not eligible.

- Three separate Coding sessions leave only the most recent eligible.
- Browsing can have its own eligible latest session while Coding is running.
- The actual current session uses Pause/Resume, not a duplicate Continue action.
- An older stretch of the same thread does not present a duplicate continuation
  button. All start surfaces use the same policy, including menus and commands.
- After expiry, offer **Start new session** with the same activity name.
- Continuing closes the current stretch as appropriate and creates a new stretch
  in the chosen thread. The intervening absence is not credited automatically.
- This policy does not retroactively split old threads or change the separate
  Pause/Resume and unresolved-away rules.

Enforce eligibility again at the action boundary with fresh canonical state, not
just through a hidden/disabled button. An unresolved away decision continues to
block incompatible starts. Starting a different named activity must not silently
rename current work merely because its work type matches.

Relevant code: `SessionStore.start`, `startQuick`, `continueSession`,
`canContinue`, `ThreadStats`, `FocusContinuations` and `DayStory`.

## 9. Motion and accessibility

Apply consistent, brief feedback to presses, hover, selected scope, inline
expansion, chevrons, chart selection, saving, Undo and navigation. Most transitions
should be approximately 150–250 ms, interruptible and driven by state. Preserve
the current system font, semantic colours and readable metadata hierarchy.

Respect Reduce Motion. Use fades or immediate state changes instead of large
movement where appropriate. Do not choreograph ordinary page loading or delay a
command until animation completes. Animated numbers must not cause VoiceOver to
announce every tick or repeatedly move keyboard focus.

Every interaction must have a keyboard route, an accessible name and an
appropriate focus/selected/disabled state. Test Tab/Shift-Tab order, arrow-key
selection, Return/Space activation, Escape dismissal, focus restoration and
standard menu commands. Keep native text-editing shortcuts intact.

## Acceptance evidence

| Area | Required checks |
| --- | --- |
| Period stories | Week and Month retain scope/anchor/totals; selecting, expanding, collapsing and changing period; historical/live entries; independent child facts |
| Scope control | Pointer then keyboard selection; no stale Day decoration; one coherent keyboard sequence; accessible selected state |
| Decisions | Multiple receipts, relaunch, later edits, old/legacy breaks, cross-midnight intervals, failed save, interrupted Undo, re-answer and stale Retry |
| Duration facts | 0s, fractional second, 31s, minute/hour boundary, duplicate/overlapping intervals, partial recording and tiny secondary apps |
| Continuation | 59m59s/60m/60m01s, latest of three, separate Coding/Browsing, active/paused/pending states, midnight and stale action snapshots |
| Reading contexts | Summary above chronology; Day/Week/Month Insights; insufficient evidence; History search/drill-in/return; current period marked so far |
| Settings and close | Stable frame for every page/search, smallest supported window, content overflow, X/Escape/close command and restored focus |
| Accessibility/motion | Light/dark/System, reduced motion, keyboard-only flow, accessible names/values, hover/press/disabled feedback |

Run `./build.sh --check` and `./build.sh --test` after relevant test-first batches.
Inspect actual fixture renders at 980 and 1,160 points in both appearances.
Native interaction tests must use `scripts/build-fixture-app.sh`: a fixture-only
executable whose flagless relaunch cannot initialise the production coordinator.
Do not launch the production app or copy its executable for automation.

Report build/test/render coverage separately from manual pointer, drag and
VoiceOver coverage. Green compilation is not proof of persistent Undo correctness
or visual fidelity. Do not call this complete until the acceptance evidence is
recorded; do not publish without the user's separate approval.

## References

- [Apple: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Apple: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Existing Story language](../../../DESIGN.md)
- [Previous interaction verification](../reviews/2026-08-31-story-interaction-verification.md)

The one-hour continuation rule is the approved product decision, not a claim
about an Apple requirement or an established industry time limit.
