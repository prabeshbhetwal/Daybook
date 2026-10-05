# Story interaction follow-up

Date: 31 August 2026

Baseline: `f05d321`

Status: implementation and local verification complete within the limits below.
No push authorised or performed.

## Scope

This is the approved follow-up to the user's screenshot review, not another
whole-app redesign. Work is in the original project folder. The supplied images
govern the card anatomy, muted filled actions, work-type colour and contextual
green confirmation. Native controls and truthful evidence govern behaviour.
`DESIGN.md` records the detailed decisions and their rationale.

| Requested change | Implementation |
| --- | --- |
| Select an activity or type a name | Editable field with Recent activities and Suggestions in its trailing menu; selection fills the draft, Start begins work; up to 20 started names persist locally. Work type is explicitly separate. |
| Shape of it | Eight equal-time coverage columns beside app rows, derived from clipped, unioned recorded app-use intervals. Unknown intervals stay empty. |
| Reference-matched actions and highlights | Soft filled Rename / Change type / Continue this; amber Meetings evidence; tinted current duration, timeline halo, Pause and compact live shape. |
| Green Undo row | One saved receipt at the original interval, then an in-place re-answer card after Undo. Later work and intervening edits are protected. |
| No unsolicited focus sheet | Generic app opening reveals the existing Story. Explicit session-control routes remain available. |
| Bounded app list | Top four only, no expand-all or nested app-list scroll. App-specific visit inspection remains available. |
| Reverse timeline | Current/latest at the top, with earlier sessions, rest and gaps below. Core chronological accounting remains unchanged. |
| Inconsistent-looking totals | Header says logged focus-session time and separately labels recorded app use. No old history is rewritten to force unrelated measures to agree. |

## Regression and recovery work

The new checks cover reusable short-session names, ordering, truthful chart
coverage, navigation, contextual receipt placement, storage failure, later edits,
re-answering and restoration. Independent recovery review identified and drove
regressions for shifted restored ranges, double-debited Undo, archive-capacity
eviction, stale retries and duplicated insertion after interrupted persistence.
Further bounded checks preserve absence tracking after a locked relaunch and
refuse a conflicting recovered answer when its preceding stretch is already saved.

An archived effect has a stable identity and an expected before/after record.
Recovery reconciles a demonstrably saved result, refuses conflicting evidence
and never treats the current session as a substitute for the original interval.
The original shadow-absence regression now attributes 40 minutes before absence
and 12 minutes after the real return; its unchanged total is 52 minutes. The
previous allocation placed all 52 minutes before the absence and started the
successor at relaunch, which contradicted the preserved real return time.

The UI review additionally caught hidden failed-save feedback, premature prompt
dismissal and understated cross-day Undo scope. All answer surfaces now retain
the question/reason on failure. Their retry is restricted to that pending answer:
a later failed rename elsewhere cannot be executed by the away prompt's Retry.
The full duration and calendar-day scope are disclosed before a cross-day Undo.

Rendered inspection also exposed a clipped compact placeholder and a two-line
Start label. The compact chooser now uses shorter copy, a Work type label above
its picker and a single-line primary action. Earlier stretches of the active
thread no longer show live Pause/End controls. Fixture clocks no longer read the
Mac's operational idle timer; production timer/presence behaviour is unchanged.

## Verification record

The final staged check and promoted build both passed **260/260**, with warnings
treated as errors and strict staged signature verification. The promoted root
bundle also passes `codesign --verify --deep`. All **152/152** final snapshots
rendered successfully. The new visual fixtures are `storyShape`, `storyMeeting`,
`storyLive`, `storyDecision`, `focusSaveFailure`, `awayQuickFailure` and
`awayFullFailure`; they use isolated archives and injected clocks. No live history
or user preferences are used as test fixtures.

| Final gate | Result |
| --- | --- |
| `./build.sh --check` | 260/260; staged compilation/signature passed without promotion. |
| `./build.sh --test` | 260/260; verified 8.3 MB root app promoted. |
| `codesign --verify --deep Daybook.app` | Exit 0 after promotion and final checks. |
| Snapshot matrix | 152/152 from the promoted build, in `final-snapshots/`. |
| Fixture-only builder | Compiled, signed and passed deep/strict signature verification. |
| Flagless native relaunch | Reopened the configured failure fixture under its separate identity, never production mode. |
| Post-containment data comparison | Live session/app-use hashes and preference-file bytes unchanged through safe fixture testing and relaunch. |
| Independent review | Recovery, UI/retry integration and fixture-launch isolation scopes closed. |
| `git diff --check`; fixture script syntax | Exit 0. |

The bounded recovery reviewer independently recompiled and replayed interrupted
Undo/insertion, locked restore and conflicting-answer cases. The separate UI
reviewer checked the shared feedback, retained reason, cross-day scope and scoped
retry integration. No finding remains open within either reviewed scope; neither
source review substitutes for the remaining native/visual gates.

Native checks on the preceding interaction build observed:

- Opening the isolated main window showed Story; Command-7 explicitly opened
  session controls and Escape returned to Story.
- Selecting a recent activity filled and selected the editable name without
  starting. Replacing it with **Read the parser notes** still left Start visible.
  Return explicitly started that activity. After an immediate Stop, the new name
  appeared first under Recent activities despite having no durable short-session
  history record.
- Keyboard Undo replaced the green break row with the in-place question and
  reduced rest by its exact interval. Re-answering restored that same interval
  and left current focus unchanged. Filled actions and visible keyboard focus
  were observed in the actual native window.

The earlier native build still allowed its real idle sampler to affect a long
fixture inspection; this prompted the fixture-only ticker isolation above. The
final normal-entry fixture visibly exposed the failure message and Retry in its
native sheet before the incident below.

The subsequent **fixture-only executable** was launched without flags, then
quit and reopened through Launch Services without flags. Both launches remained
in the configured synthetic failure scenario. A named answer was entered and
submitted with Return: the rejected save retained the text, pending question,
error and Retry. Retry was keyboard-reachable and did not dismiss the still-failed
question. The displayed synthetic time stayed fixed. Live session/app-use hashes
and the real preference file remained unchanged throughout these checks.

### Visual inspection and remaining limits

Inspected representative light/dark and minimum/comfortable Story shapes,
Meetings, current work and decision rows, plus the compact idle chooser and
failed-save layouts in the Focus popover, quick prompt and full prompt. The
compact placeholder and Start action now fit on single lines; app/shape columns,
filled controls, type highlights, green receipt and wrapped error feedback stay
within their intended surfaces. This is representative inspection, not a claim
that all 152 images received an individual manual review.

Keyboard behaviour and native accessibility-tree content were exercised. Pointer
operations continued returning the Computer Use native-pipe error even in the
safe, regular-application fixture. Pointer hit testing, drag reordering, complete
VoiceOver traversal and real sleep/lock trials are therefore not claimed as
completed. Headless state/recovery tests, static renders and source review do not
substitute for those checks. No production interaction failure was inferred merely
from the automation error.

### Native-launch isolation incident

The UI automation tool relaunched the disposable production-binary copy without
`--fixture-window`. That instantiated the ordinary coordinator, despite the
initial command having selected a fixture. Process arguments and a process sample
confirmed the normal menu-bar/ticker path; the process was then stopped by its
verified PID. This was a verification-harness isolation failure, not evidence
that the application's normal launch or the new controls were unresponsive.

The unintended normal launch wrote ordinary app-use evidence and performed normal
session recovery. The main session archive, app-use archive and preferences were
preserved in a private, ignored `launch-audit` directory before further testing.
The uniquely entered test activity was not found in session history. No records
were deleted or rewritten as a speculative rollback; there is no pre-launch
byte-for-byte baseline that would justify one. The user was informed. Therefore
**this pass does not claim that live data remained completely untouched**.

`scripts/build-fixture-app.sh` and `scripts/NativeFixtureMain.swift` now provide a
separate executable which cannot call the production entry point. They use the
same production views and actions, isolated fixture factories, a separate bundle
identifier, and bundle-stored scenario selection. A flagless relaunch remains a
fixture. The helper copies only metadata and resources, never the production
binary, so even an interrupted fixture build cannot leave a normal-recording
executable at its output path. This replaces argument-only isolation for native
automation; the root app's production entry and behaviour are unchanged.
The two earlier temporary bundles from this pass were unregistered and their
executables moved outside the bundles, leaving them recoverable but no longer
launchable as apps. The verified root app was registered without launching it.

Generated output belongs under `.build/` or disposable temporary directories.
The supplied research additions are preserved and must not be staged as part of
this implementation. The root app is a local ad-hoc build, not a notarised release.
