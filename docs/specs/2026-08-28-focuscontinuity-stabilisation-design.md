# FocusContinuity Stabilisation Design

**Date:** 2026-08-28  
**Status:** Approved for implementation

## Goal

Stabilise time accounting, historical reporting, live dashboard consistency,
persistence safety and local build integrity without redesigning the approved
product.

## Locked constraints

- Preserve the macOS 13 target and direct `swiftc` build in Swift 5 language mode.
- Add no package, service, model, network dependency or TCC permission.
- Keep one repeating timer: the existing one-second `SessionStore` ticker.
- Never semantically rewrite historical app-usage records. Copy the legacy bytes
  to a timestamped backup before migrating only the container format.
- Persist the date from which corrected usage recording is authoritative and
  qualify older app-usage views.
- Week and Month bars show exact tracked time. Work-type composition remains a
  separate donut.
- Keep existing user-facing time terminology except where this specification
  explicitly corrects it.
- Do not split large files merely to meet the superseded 500-line guideline.
- Tests use suite-scoped defaults and temporary directories only.
- Use Australian English in UI copy and documentation.

## Data integrity

`app-usage.json` moves from a raw `[AppUsageSession]` array to a versioned
envelope containing `AppUsageMetadata(schemaVersion: 2, accurateFrom:)` and the
unchanged sessions. Loading legacy data copies the original file byte-for-byte
to `app-usage-v1-backup-<unix timestamp>.json`, then writes the envelope. No
session field is repaired or reclassified.

An open app stretch has one stable UUID. Periodic checkpoints replace that
record; they never append fragments. If later idle evidence moves the true end
backward, the same record is shortened or removed. Confirmed activity after the
idle interval starts a new UUID.

## Presence

A machine wake is not human presence. After wake, a monotonically increasing HID
idle counter remains quiet. Presence is confirmed only by an unlock or by the
counter advancing and later resetting. Wake can prepare the frontmost app as a
resume candidate, but cannot start recording it.

## Reporting

- Today's goal and the historical usual-pace median both use focus-session time
  intersected with hands-on app usage.
- Historical pace excludes days before `accurateFrom` and remains absent until
  three authoritative active days exist.
- Day sessions, running spans, summaries and focus brackets are clipped to the
  selected calendar day.
- `.breakTime` records remain rest evidence and never enter focus spans, focus
  counts or focus-quality work-type shares.
- Period bars and their average use exact tracked seconds. Work-type shares stay
  in the donut and do not determine bar height.
- Dashboard day slices invalidate on an archive revision, including same-count
  checkpoint replacements.

## Build and repository

Generated app bundles, root snapshots, `.build`, `.worktrees` and `.DS_Store` are
ignored. `build.sh` assembles and signs in a temporary directory, verifies the
staged bundle strictly, runs requested tests, and only then promotes a normal
build. `--check` performs the staged build, strict verification and self-test
without replacing the local app. The local app is ad-hoc signed and is not
represented as notarised or distributable.

## Implementation and verification notes (2026-08-29)

- `SessionArchive` accepts an internal capacity argument that defaults to the
  production archive capacity. The self-test injects a capacity of three and
  verifies eviction, retained ordering and count without repeatedly writing a
  production-sized ring.
- `SelfTest` records each scratch directory made through its helper and removes
  every recorded path in its private cleanup utility. The test utility remains
  outside production code.
- The duplicate long-absence reset and the unused dashboard and coordinator
  symbols were removed. The README now records the single ticker’s presence,
  checkpoint, live-figure and break duties; v2 usage provenance; source-only
  Git; non-promoting `--check`; generated root app; and local ad-hoc signing.
- One observed comparable end-to-end self-test run took 91.71 seconds with the
  former production-sized ring exercise and 41.03 seconds with capacity three.
  That single observed run was 55.3% faster; it is not a benchmark estimate.
  The detailed RED/GREEN, command and visual-snapshot evidence is recorded in
  the task report.

## Acceptance

1. Periodic persistence cannot retain idle tails or checkpoint fragments.
2. Wake alone neither ends an absence nor records usage.
3. Legacy usage records survive field-for-field with a byte-identical backup.
4. Current and historical goal pace use the same focused-active definition.
5. Cross-midnight rows and spans remain inside their selected day.
6. Break records never count as focus.
7. Every period bar equals that day's tracked total.
8. A visible dashboard updates after same-count archive mutations.
9. Pre-fix usage is qualified and its data folder is revealable.
10. A fresh staged build, strict verification, full self-test and visual snapshot
    pass succeed without reintroducing generated files to Git.
