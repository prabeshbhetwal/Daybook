# Story remediation and verification

Date: 31 August 2026

Baseline: `13a1cf3`

Status: audit fixes, independent review and local verification complete, with
the manual-verification limits below. Publication still requires approval.

## Scope and design authority

This work addresses the 31 August design-and-behaviour audit, using the final
**Day as a Story** reference in the supplied research handoff. Earlier prototypes
are alternatives, not additional specifications to combine. The main checkout
is authoritative; no worktree or remote publication is part of this change.

`DESIGN.md` records the implemented design language. The warm canvas, neutral
336-point rail, measured insets, restrained cards, system typography and indigo
focus emphasis follow the reference. Dark text colours are adapted for legibility.
Native windowing, keyboard operation and truthful metrics take precedence over
copying unsupported mock features such as sync, typing activity or invented insights.

## Audit changes

| Finding | Resolution |
| --- | --- |
| F01: incorrect historical route | Historical drill-in selects the actual store date before presenting Day; repeated routes also work. |
| F02: stale period selection | Changing scope, period or available evidence clears an unavailable selected day. |
| F03: disconnected commands | Commands, keyboard shortcuts and menu-bar routes reach the same Story scopes or native secondary sheets. |
| F04: mixed averages | Focus summaries use focused days and focused averages; tracked averages remain separate. |
| F05: disappearing live focus | Day, Week, Month and History project the running session without inventing durable records. |
| F06: misleading Mac totals | Mac use is recorded app time only. Session membership is a temporal intersection; uncovered focus is separate. The legacy narrative no longer calls a focused/tracked quotient an overlap. |
| F07: ineffective active corrections | Rename and work-type changes operate on active and archived portions of a thread; active type and identity survive restoration. |
| F08: false save success | Candidates are written atomically before publication. Failure remains visible and retryable; field-scoped Undo preserves later work and remains reachable after conversion to Break. |
| F09: lost qualifications | Day/period/History qualifications precede the figures affected by legacy recording. |
| F10: System appearance | Production colour-scheme overrides are removed; System returns to AppKit inheritance. |
| F11: oversized preferences | Five bounded pages retain every backed control. Page/search changes start at the first control; paths and diagnostics wrap and scroll. |
| F12: imitation modal behaviour | Production sheets are native. Rename requests focus after installation; app detail has explicit Escape dismissal and restores source-row focus. |
| F13: misleading calendar | Square cells show dates and focused durations; relative intensity is independent of goal attainment. Cell text meets the tested 4.5:1 contrast floor. |
| F14: inert controls | Session actions, History, Insights, Awards, app drill-ins, visit limits, timestamps and entry expansion have real destinations/effects. |
| F15: incomplete day | Chronology preserves individual stretches, named rest, observed app-only intervals and explicitly unrecorded gaps. Longest means a stretch. |
| F16: stale verification/docs | Snapshot scenarios target their actual surfaces; a disposable native-window mode exercises interaction. README describes the shipped Story architecture. |

## Cross-component regressions covered

- Legacy record UUID equal to its thread UUID: archived and live History rows
  have distinct presentation identities while preserving source provenance.
- Uncheckpointed visits: disclosure app totals include the same live overlay
  as the rail, including the first visit and a post-checkpoint tail.
- Short focus/rest separators are never bridged into outside-use time. Ordinary
  gaps may be grouped visually but add no observed seconds. Overlapping, nested,
  identical and adjacent visits do not trap or rewrite original records.
- Repeated overnight ticks preserve unique History dates and full-period
  stretch durations, including stored cross-midnight records.
- Full refresh requests dominate live-only requests in either nested order.
  Mutations raised during publication remain pending until consumed.
- A live-value subscriber that corrects a checkpoint cannot advance the cached
  frame beyond the evidence actually read. The next fixed-clock tick consumes
  the newer revision instead of retaining stale live totals.
- Stable archive queries are invalidated by corrections and ring eviction.
  Unchanged idle/paused frames do not rebuild reports; changing day figures must
  agree with a full rebuild using the same injected clock.

## Verification record

The final root-source gates include the last live-publication regression:

| Gate | Result |
| --- | --- |
| `./build.sh --check` | 234/234 passed; warnings-as-errors compilation and strict staged signature verification passed; root app not replaced by this command. |
| `./build.sh --test` | 234/234 passed; verified 7.8 MB local bundle promoted. |
| `codesign --verify --deep Daybook.app` | Exit 0 after promotion. |
| `git diff --check` | Exit 0. |
| Targeted accounting/presentation regressions | 25/25, including a demonstrated RED → GREEN live-publication reproduction. |
| Independent review | Original audit, integration findings and targeted follow-up closed; no open finding within the reviewed scope. |
| Final snapshot rerun | 126/126 rendered from the promoted post-regression bundle at `/tmp/fc-story-final.8QUit6`. |

The capacity fixture verifies that it loaded all 5,000 focus records and 20,000
app-use records before timing the real visible read-model update. In the final
root check, a live tick took 23.87 ms and three unchanged idle ticks took 0.034 ms
in total. The promoted build measured 24.48 ms and 0.026 ms respectively. These
are local read-model measurements, excluding SwiftUI drawing; they are not a
universal frame-rate or animation-smoothness guarantee.

### Native interaction evidence

Production UI was exercised in disposable `--fixture-window` bundles, including
the final UI build. The only subsequent production change was the tested
non-visual consumed-frame correction described above.

| Interaction | Observed result |
| --- | --- |
| Historical Month selection → explicit Story action | Selected date and actual records changed together; no substitution of today's records. |
| History and Insights keyboard commands | Opened their native sheets. Escape dismissed the sheet and restored the parent accessibility tree. |
| History row, activated with Space | Expanded beneath the same row, showed its downward chevron, retained row focus and collapsed with Space. |
| Whole-header About this day disclosure | Expanded with Space while focus remained on its complete header. |
| Rename → Save / Cancel | Existing name was selected immediately. Return saved; Escape discarded the draft. Both returned focus to Rename. |
| Change type → Break → Undo correction | Focus and goal credit dropped to zero in the fixture; Undo remained keyboard-reachable and restored both stretches and focus totals. |
| App detail → Escape | Close was focused on opening; Escape dismissed the popover and returned focus to its app row. |
| Light → System and Dark → System | Both native sheet and parent returned to the actual macOS dark appearance. |
| Settings page change | The earlier General-bottom → Sessions check reset the scroll from 1 to 0 and revealed Daily goal; Away also opened at 0. |
| Settings search | `Recent app visits` showed Recording and its actual picker. Replacing it with `Record app usage` on the same page retained typing focus and showed the matching group from its beginning. |
| Session controls | Start, Pause, Resume, Away, return and Stop reached their expected production states. The injected clock makes this an action-routing check, not a real-time timing trial. |

Native screenshots and build logs are retained locally in
`.build/story-verification-2026-08-31/`. The temporary app was closed after testing.

### Visual inspection

Inspected Day, expanded entry, Week, Month, first-run, paused, awaiting-decision,
selected History and all five Settings page compositions across light/dark and
minimum/comfortable examples. Checked hierarchy, chart containment, calendar
dates/durations, joined disclosures, wrapped text and sheet viewport bounds.
The 12 corresponding pre-final images checked by SHA-256 were byte-identical
after the non-visual T1 correction; the final minimum-width light Week and dark
Month were also opened and inspected directly. Privacy paths vary by disposable
fixture directory and were checked for wrapping, not byte equality. This is
representative content inspection, not a claim that every one of 126 PNGs received
an individual manual review.

The snapshot path uses offscreen AppKit hosting with real controls and scroll
views. Its static sheet composition checks layout only. Native modal focus and
keyboard behaviour are checked separately in `--fixture-window`; neither a PNG
count nor headless tests establishes complete pointer, VoiceOver or animation QA.

Computer Use pointer/scroll operations intermittently returned a native-pipe
error. Keyboard and accessibility-tree checks succeeded, but pointer hit testing,
drag reordering, full VoiceOver traversal and real sleep/lock trials were not
independently completed in this pass. The final search test did not replay a
non-zero scroll offset because of that tool limitation; page/query identity was
also reviewed in source. These are verification limits, not claims of proven
failures or a reason to alter the user's live settings.

## Evidence and repository safety

All test records, corrections and preferences use isolated suites and temporary
directories. No live history is repaired or used as a test fixture. Generated
bundles, snapshots and internal execution artefacts remain ignored. The supplied
research additions remain local and are not staged as project implementation.

Two duplicate Settings source files were byte-identical to the baseline and
were moved, not deleted, to `.build/duplicate-source-quarantine-2026-08-31/`.
They remain recoverable and are outside compiler source enumeration.

The root app remains a local ad-hoc build. Signature checks do not make it
notarised or distributable. Publication requires separate user approval.
