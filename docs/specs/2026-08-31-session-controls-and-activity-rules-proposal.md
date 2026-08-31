# Session controls, context and activity rules

Status: written specification approved for implementation in chat on 31 August
2026, including one primary activity and quiet shared-app choices. Implementation
and verification are in progress; this is not a completion report. The companion
interaction model is recorded in
[Story interaction model](2026-08-31-story-interaction-model-design.md).

Date: 31 August 2026. Code inspected at `73fb2cf` in the main project checkout.

## Intent

Provide one persistent application workspace, compact controls at the point of
use, optional session context and automation whose time accounting can be trusted.
Keep the existing native Story language. Do not introduce a separate notes app,
an always-on-top timer window or an opaque classifier that guesses intent from
the name of a general-purpose app.

## Confirmed causes and available foundations

| Observation | Current implementation |
| --- | --- |
| Wide empty menu-bar panel | `PopoverMetrics.fitting` selects 560 points on larger screens for a legacy two-column layout. The operational content remains one column. |
| Timer pill opens Focus | `StoryChromeBar` explicitly calls `navigation.openSheet(.focus)`. Its comment still describes a direct pause action, unlike its actual behaviour. |
| Shared apps cannot identify intent | `PurposeMap` supplies fixed/behavioural purposes, not user-defined activity memberships. `AutoSessionDetector` uses a score and a fixed five-minute dwell. |
| Long unchanging app use may not trigger at the chosen deadline | The existing detector evaluates at event boundaries. A custom dwell requires a real deadline and fresh validation, not waiting for another app switch. |
| Power/notes unavailable historically | `SessionRecord` has neither battery history nor user notes. Existing values cannot be reconstructed from the Mac's current state. |
| Shape is difficult to interpret | Eight bars show recorded coverage per equal elapsed-time bin. Colour distinguishes the predominant app from all others, not one colour per app. |
| Month grows too tall | Calendar cells use a square aspect ratio, so increasing content width also increases the entire calendar's height. |
| Dragging is undiscoverable | The rail installs drag/drop handlers on each tile without an explicit arranging mode. |

These findings come from source inspection and the supplied screenshots, not a
new live-app interaction test. No production data was opened or changed.

## 1. Two compact control surfaces, one persistent window

### Menu bar

Use a compact single-column panel approximately 320–360 points wide, bounded by
the actual display. Its contents should determine its height. Do not use screen
width as permission to grow a single-column panel to 560 points.

Hierarchy, from top to bottom:

1. Activity name and state, with the elapsed time beside them.
2. Pause/Resume, Away and End controls; only the valid actions for that state.
3. A quiet daily-goal line and a relevant break or attention message.
4. At most a few genuinely eligible continuations, excluding the current session.
5. Open app, Settings and Quit in a compact footer.

Idle substitutes the existing editable activity chooser and Start action.
An unresolved absence substitutes its question and safe answer controls. Preserve
drafts, original interval identities and visible save errors. Do not show several
large nested cards or repeat the current session in a Continue section.

Apple recommends a menu for menu-bar extras unless the functionality needs richer
controls. This app has a live clock, editable activity and an away-decision form,
so a small native popover-style menu-bar panel is a defensible exception. It is
not a second persistent workspace or a miniature copy of the Focus page.

### Main-window timer pill

Clicking the timer pill expands a short session-control strip immediately below
the existing chrome, within the same window. It does not open a Focus sheet or
navigate the reader away from History, Week or Month.

The strip contains the current activity, timer, relevant actions and a **Pin
controls** option. Pinning remembers that the strip remains visible in this
window; it does not detach the controls into another window. Clicking the pill
again or closing the unpinned strip collapses it. A pin does not change recording.

Keep Day/Week/Month and ordinary navigation visible. Avoid turning the whole
toolbar into a hidden menu just to expose the timer. Keyboard commands reveal the
same controls and restore focus to the pill on dismissal. The app still opens for
reading history without automatically showing an unpinned control strip.

**One-window boundary:** one persistent primary application window. Transient
native menu-bar panels and attached task confirmations are not detachable timer
workspaces. Audit the separate away-prompt paths before claiming all operational
prompts obey this model; do not silently remove an existing return question.

## 2. Installed apps and user-owned activities

Add an activity editor under Settings, with an activity name, work type and
searchable app picker. The picker shows app icons and names, with bundle identity
used internally. Membership is separate from whether a system app category can
pause a session and separate from an activity's work type.

Discover ordinary application bundles in standard local application locations,
supplemented by a bounded Spotlight query and apps already observed by the
recorder. Provide **Add application…** for an app outside those locations. Do not
promise an exhaustive scan of every disk, backup, nested helper and unindexed
directory. Deduplicate stable app identities and label missing/uninstalled apps.

Discovery runs when opening/refreshing the picker, not on every session tick.
Neither installation nor background launch counts as usage: qualifying evidence
comes from foreground app observations subject to the existing presence rules.
Keep the inventory and memberships local. This proposal requires no reading of
chat messages, code, documents, browser URLs or window titles.

Apple's `NSMetadataQuery` provides Spotlight queries with configurable search
scope. Its results are one discovery source, not proof that every installed app
has been found. `NSWorkspace` app-activation notifications already provide the
event boundary needed for foreground app changes.

## 3. Do not run duplicate focus clocks for shared apps

If ChatGPT is assigned to Coding and Research, ten minutes in ChatGPT does not
establish which activity occurred. Assigning ten minutes to each would produce
twenty category minutes from ten observed minutes and corrupt goal/period maths
if summed. More input activity does not solve this ambiguity.

### Options

| Model | Benefit | Cost |
| --- | --- | --- |
| One primary activity; apps may have multiple memberships | Honest non-overlapping totals, supports shared tools, explicit correction | An ambiguous start sometimes needs the user's choice |
| Multiple labels/filters on one underlying interval | A shared tool can be found in several contexts | Labels overlap and cannot be added together as separate session time |
| Each app can belong to only one activity | Very simple deterministic matching | Forces ChatGPT, browsers and other shared tools into an artificial category |

**Recommendation:** one primary activity for session accounting. Allow shared app
memberships as possible matches. Optional labels/filters can be added later with
explicit non-additive semantics, but they do not start concurrent session clocks.

This is consistent with the distinction Timing makes between a single project
assignment and potentially overlapping filters. Timing resolves project-rule
conflicts by priority; the proposed default here uses explicit current context and
a user choice instead of silently resolving an uncertain intention by list order.

### Proposed resolution order

1. A deliberately selected active activity wins. A shared browser or AI client
   does not silently relabel that manual session.
2. When idle, a qualifying app that matches exactly one enabled activity may
   auto-start that activity after its configured dwell.
3. A shared app may stay with an already established automatic activity while it
   remains a member. Short trips to shared supporting tools do not create a new
   session.
4. If a new run matches multiple activities and there is no established context,
   keep recording app use once and offer a quiet choice such as **Coding or
   Research?** in the control strip/menu. Do not start both or force a modal.
5. Choosing an activity attributes only the eligible, evidenced interval. The
   same interval is not copied into the other activity. Manual corrections are
   durable and remain effective when rules subsequently change.
6. A switch to an app exclusive to a different automatic activity starts a new
   qualifying run. Switching a manually started activity stays an explicit user
   operation. Paused/manual-away states and pending questions cannot be overridden.

Example: VS Code establishes Coding. ChatGPT, Claude and Chrome can then support
that Coding session. If Chrome also belongs to Browsing, it is not counted again
as Browsing. Starting Browsing explicitly changes context. Starting from shared
ChatGPT alone without a context prompts for a quiet choice or remains unassigned.

### Dwell and boundaries

Proposed default: **3 minutes**, with **30 seconds, 1 minute, 3 minutes and 5
minutes**, plus a validated custom duration in the advanced control. This is an
initial product setting to validate, not a research-backed optimum.

Show the rule in plain language: **Start Coding after 3 minutes in these apps**.
A qualifying run can span several apps assigned to the same resolved activity.
Lock, sleep, manual Away, disabled recording and an unresolved decision invalidate
the run. Opening an app in the background does not count.

Use a cancellable one-shot deadline and the existing observation/presence
machinery; do not add a repeating polling loop. At the deadline revalidate app,
presence, rule version, activity choice and recording coverage. Cancelling or
editing a rule invalidates an old callback. The deadline must work even if the
person stays in one app without a further app-switch event.

If the start is confirmed automatically, credit only the qualifying observed
interval from its beginning, excluding sleep, absence and already-accounted
work. Store the reason and expose Undo. A rejected automatic start enters a
cooldown so the same guess does not immediately return.

The approved 60-minute/latest-per-activity rule governs explicit **Continue
this**. Automatic starts must not silently merge old threads just because an
activity name matches. Retain the distinction between starting a new session and
continuing an eligible previous one.

**Approved policy:** one primary activity with quiet handling of ambiguous shared
apps. Rule-based automation is opt-in. Existing automatic behaviour must be
explicitly reconciled with the rule mode, not run as a second competing detector.

## 4. Optional session notes

An expanded timeline entry exposes a quiet **Add note** action. It opens a small
plain-text editor inside that entry, with a labelled Save action and normal text
editing shortcuts. An empty note occupies no permanent block. A saved note is
indicated subtly; its contents remain secondary to the session record.

Proposed scope: each recorded stretch owns its note, so another stretch in the
same continued thread can describe different work. Editing a note does not alter
name, type, timestamps or focus credit. A thread-level view may show those notes
chronologically without duplicating them onto every stretch.

Persist by stable record identity in compatible session metadata. Retain drafts
on save failure; collapse/navigation must not silently discard unsaved text.
Keyboard users can reach the editor, save with Command-Return and leave it
without trapping focus. Avoid a notebook sidebar, rich-text toolbar or separate
editor window.

Metadata must remain alongside the existing data files, so a complete data-folder
copy or removal includes it, and follow record retention. Source inspection found
no existing export or erase-history control; this change does not introduce a new
destructive workflow. Any future export/erase operation must include metadata.
Undoing a classification must not accidentally erase a note, and editing a note
must not invalidate an unrelated classification receipt.

## 5. Power context, only when actually recorded

Show a small secondary line beneath the duration, using a system battery/power
symbol and text. Proposed examples:

- **Battery · 78% → 64%**
- **Plugged in · 64% → 81%**
- **Power changed**, with the transitions visible in expanded detail

Capture source and charge level at session boundaries, power-source changes,
available charge-level notifications and wake/recovery. Apple's public IOKit
power-source APIs expose snapshots and change notifications. No repeating
battery-polling timer is needed.

Distinguish external power from actively charging: a plugged-in Mac may be
holding charge. Handle desktops without batteries, unavailable percentages and
mixed power sources without inventing a battery level. A percentage change is
not a measurement of how much energy this session or one app consumed.

Older sessions have no recorded power evidence. Omit the header badge or say
**Power not recorded** in detail. Never populate historical sessions with the
Mac's current battery level. A session containing an observation gap must not
claim continuous power coverage across that gap.

Power metadata remains separate from time accounting. Corrections to work type
or name cannot change observed power events.

## 6. Make the session chart legible and useful

Rename **Shape of it** to **App activity**. Prefer a compact, time-proportional
strip of actual foreground app intervals and explicitly marked recording gaps.
Reuse each app's colour from the adjacent app list, include start/end time labels
and expose exact app, time range and duration on keyboard focus as well as hover.

The strip answers **which app was observed when?** A short caption summarises
recording coverage; it does not infer typing intensity, engagement or quality.
Unknown/unrecorded time must look different from a recorded break. Use text or a
pattern as well as colour so missing evidence is not hidden by the palette.

For a very short session or no recording evidence, use a concise factual sentence
instead of eight identical bars. Longer timelines may aggregate tiny consecutive
runs for rendering, but their exact data remains available and totals stay
unchanged. The left app list retains its fixed cap and exact duration semantics.

This approved change supersedes the previous prototype's eight decorative-looking
bars. It is a semantic visual change, not a claim that
the existing chart measures input intensity.

Apply the same clarity review to headings, percentages, denominators, state
messages and tooltips throughout the affected surfaces. Visible essential meaning
comes first; extra precision may live in detail, not the only explanation.

## 7. Compact month and deliberate rail arranging

Month cells should have a compact bounded height independent of their width,
while keeping date, focused duration, today marker and selection recognisable.
Keep weekly totals, weekdays and the intensity legend. A six-row month must leave
useful space for the selected day's inline story at the supported window sizes.
Do not achieve compactness by shrinking text or removing accessible hit targets.

Add one **Arrange cards** control at the supporting rail's upper trailing edge.
Ordinary reading mode has no per-card permanent drag handles and cannot
accidentally begin dragging from a normal click. Arranging mode makes destinations
and movement clear, enables drag/drop, and exposes keyboard Move up/Move down.
An accessible **Finish arranging** control exits the mode; Escape also exits.

Persist the established tile order. Keep selected app details and unrelated
content stable while arranging. Offer a clear reset-to-default action through
the group control, not one reset button on every tile. Use subtle movement and
drop feedback with a reduced-motion equivalent.

## Delivery slices and verification

1. Implement and verify the already-approved Story interaction specification.
2. After approval, implement the compact controls, in-window strip, compact month
   and arranging mode as a presentation batch.
3. Implement notes and observed power context as compatible metadata changes,
   including retention, complete-folder portability/removal and interrupted-save tests.
4. Implement the app inventory/rule editor independently of automatic mutation;
   show conflicts before rules can start sessions.
5. Implement the approved exclusive-assignment detector with injected time and
   deterministic event tests, then connect it to the existing engine.
6. Verify the revised chart and cross-surface copy against canonical intervals.

Minimum adversarial tests include shared apps with no context, explicit manual
choice, duplicate app memberships, changing rule mid-dwell, no app-switch at the
deadline, lock/sleep/background apps, disabling tracking, past corrections,
midnight/DST, no battery, power switching, legacy metadata, failed note save,
retention, and Undo after a later note edit. One second of evidence must never
become two seconds of focus credit through membership or retries.

Use only fixture data and the fixture-only native executable for UI testing.
Keyboard, pointer/drag and VoiceOver coverage must be reported separately from
snapshot or compilation success. No live history migration or production app
launch is authorised merely to research these features.

## Sources and limits

- [Apple: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), including native menu-bar-extra guidance.
- [Apple: Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), including task-focused sizing, dismissal and avoiding nested popovers.
- [Apple: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), including deliberate grouping and discoverable commands.
- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), including its richer window presentation style.
- [Apple: NSMetadataQuery](https://developer.apple.com/documentation/foundation/nsmetadataquery), for scoped Spotlight discovery.
- [Apple: Application activation](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification), for foreground app events.
- [Timing: Rules in depth](https://timingapp.com/help/rules), for the distinction between exclusive project assignment and overlapping filters, and explicit rule precedence.
- Installed macOS SDK public headers `IOKit/ps/IOPowerSources.h` and
  `IOKit/ps/IOPSKeys.h`, inspected for snapshot/change APIs and power/charge fields.

These sources establish available mechanisms and conventions. The proposed
320–360-point width, three-minute default, one-primary-activity conflict policy,
note scope and inline pinning are design recommendations for this product, not
values mandated by Apple or comparative usability-study results.
