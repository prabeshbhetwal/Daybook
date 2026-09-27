# Honest Usage Persistence Implementation Plan

**Goal:** Make app-usage checkpoints reversible, non-duplicating and gated on
confirmed human presence.

**Architecture:** A versioned archive owns storage metadata and mutation
revision. `AppUsageTracker` owns a small active/waiting/stopped state machine;
a pure `PresenceGate` distinguishes wake resets from actual input.

**Tech Stack:** Swift 5 language mode, Foundation, CoreGraphics, macOS 13.

**Spec:** `docs/specs/2026-08-28-focuscontinuity-stabilisation-design.md`

## Global constraints

- No historical session field may be changed during migration.
- Use the existing one-second ticker; add no timer or permission.
- All tests use injected clocks and temporary data.

---

### Task 1: Version and preserve app-usage storage

**Files:**
- Modify: `Sources/Core/AppUsage.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces `AppUsageMetadata`, the private v2 envelope, `revision`, `metadata`,
  `legacyBackupURL`, `onDidChange`, and `checkpoint(_:)`.

- [ ] Add `testLegacyUsageMigrationPreservesHistory` and
  `testUsageCheckpointReplacesByIdentity` to the runner and test body.
- [ ] Run a freshly compiled self-test and capture the expected compile/test
  failure caused by the missing v2 interfaces.
- [ ] Decode v2 first, fall back to the legacy array, copy the original bytes to
  `app-usage-v1-backup-<timestamp>.json`, and immediately save a v2 envelope.
- [ ] Implement `checkpoint(_:)`: replace by UUID; remove a corrected record
  below five seconds; apply capacity only to new UUIDs; increment `revision`,
  save and call `onDidChange` exactly once for a real mutation.
- [ ] Rebuild and run the complete suite; commit as
  `feat: version and preserve app usage history`.

### Task 2: Make usage checkpoints reversible and non-duplicating

**Files:**
- Modify: `Sources/Core/AppUsageTracker.swift`
- Modify: `Sources/App/SessionStore.swift`
- Modify: `Sources/App/SessionStore+History.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes Task 1 `checkpoint(_:)` and archive metadata.
- Produces `isObserving`, `currentStretchSeconds()`, `unpersistedSeconds()`,
  `observeIdle(seconds:)`, `prepareToResume(bundleID:name:)`, and
  `confirmPresence(at:)`.

- [ ] Add `testPeriodicCheckpointRollsBackIdleTail`; simulate two active
  checkpointed minutes, twenty idle minutes in the same app, then one active
  minute. Assert two UUIDs and exactly 180 seconds total.
- [ ] Assert repeated checkpoints retain one UUID, finalisation replaces
  `.stillOpen`, and total-today plus unpersisted time never double-counts.
- [ ] Run the new tests and preserve the expected failures.
- [ ] Replace `open` with stopped/active/waiting-for-presence state. A stable
  active UUID checkpoints its full corrected range and tracks its last persisted
  end separately.
- [ ] On idle cutoff, shorten/finalise the current UUID at `now - idle` and wait;
  confirmed presence starts a new UUID at the return.
- [ ] Make Running Now consume total stretch seconds, live totals consume only
  unpersisted seconds, checkpoint guards consume unpersisted seconds, and ticker
  lifetime consume `isObserving`.
- [ ] Rebuild and run the full suite; commit as
  `fix: make usage checkpoints idle-correctable`.

### Task 3: Distinguish machine wakes from human presence

**Files:**
- Create: `Sources/Core/PresenceGate.swift`
- Modify: `Sources/App/AppCoordinator.swift`
- Modify: `Sources/App/SessionStore.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces `PresenceObservation.active(since:)`, `.quiet(seconds:)` and
  `PresenceGate.noteMachineWake()`, `confirm(at:)`, `observe(...)`.

- [ ] Add `testWakePresenceGate`: increasing post-wake raw idle values remain
  quiet; unlock or a later downward reset confirms presence.
- [ ] Add `testWakeDoesNotCreateUsage`: a prepared resume candidate records
  nothing until confirmation, then starts at the confirmed return.
- [ ] Run both tests and capture the expected missing-interface failures.
- [ ] Move confirmed-active and wake-suppression bookkeeping into the pure gate.
- [ ] On `didWake`, note the wake and prepare the tracker; do not resume usage.
  On unlock, confirm and resume immediately.
- [ ] Feed the gate's quiet result into watching/idle engine transitions and
  `AppUsageTracker.observeIdle`.
- [ ] Rebuild and run the full suite; commit as
  `fix: require presence after a machine wake`.
