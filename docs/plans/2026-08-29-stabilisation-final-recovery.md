# FocusContinuity Final Recovery Implementation Plan

**Goal:** Close the two load-bearing residual findings from the stabilisation review: preserve the exact terminal app-usage boundary across a failed write, and make stale build-lock recovery mutually exclusive.

**Architecture:** Keep the existing Core → App → Design/Surfaces boundary and the existing direct `swiftc` build. App usage gains a private persistence-pending tracker state whose session boundary is immutable; build promotion gains an atomic recovery guard around stale-lock replacement. Neither change alters user-facing design or historical records.

**Tech Stack:** Swift 5 language mode, Swift 6.4 compiler, SwiftUI, AppKit, CoreGraphics, IOKit, Bash, macOS 13+, direct `swiftc`, no packages or Xcode project.

**Spec:** `docs/specs/2026-08-28-focuscontinuity-stabilisation-design.md`

## Global Constraints

- Preserve macOS 13 deployment and direct `swiftc` builds.
- No third-party package, network service, model, or new TCC permission.
- Retain exactly one repeating timer.
- Never semantically rewrite historical app-usage records.
- All tests use suite-scoped defaults and temporary directories; no live user history is touched.
- Generated application bundles and build scratch remain ignored by Git.
- Use Australian English in documentation and diagnostics.
- Implement each task test-first and commit only after its acceptance checks pass.

---

### Task 1: Freeze failed usage finalisation at the original event

**Files:**

- Modify: `Sources/Core/AppUsageTracker.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- Consumes: `AppUsageArchive.checkpoint(_:) -> Bool`, stable usage UUIDs, `prepareToResume(bundleID:name:)`, and `confirmPresence(at:)`.
- Produces: a private pending-persistence state that retains an immutable `AppUsageSession`, its last durable end, and any queued post-close continuation.

- [ ] **Step 1: Write the failing regression test**

Add `testFailedTerminalCheckpointRetainsOriginalBoundary` to `Sources/SelfTest.swift` and register it in the headless suite. Use the real `AppUsageArchive` with a temporary directory:

```swift
// Start at base, save a ten-minute prefix, then make the archive directory
// unwritable and suspend at minute eleven.
clock.advance(10 * 60)
tracker.flush()
clock.advance(60)
blockArchiveDirectory()
tracker.suspend()

// A retry twenty minutes later must preserve the original terminal boundary.
clock.advance(20 * 60)
repairArchiveDirectory()
tracker.flush()

expectClose(usage.sessions.first?.seconds ?? -1, 11 * 60,
            "a delayed retry must retain the original suspend boundary", &problems)
expect(usage.sessions.first?.endReason == .systemLock,
       "the delayed retry must retain the original terminal reason", &problems)
```

Also exercise a queued return: call `prepareToResume`, confirm presence at a literal return instant while the close remains blocked, repair storage, retry, and assert the old UUID ends at minute eleven while the new UUID begins exactly at the confirmed return.

- [ ] **Step 2: Run the focused self-test and verify RED**

Run:

```bash
./build.sh --check
```

Expected: the new assertion fails because `closeActiveSegment` recomputes `effectiveEnd()` on retry and records the extra twenty minutes.

- [ ] **Step 3: Implement immutable pending persistence**

Add private state equivalent to:

```swift
private enum PendingContinuation {
    case stopped
    case waitingForPresence(ResumeCandidate)
    case begin(ResumeCandidate, at: Date)
}

private struct PendingClose {
    let session: AppUsageSession
    let lastPersistedEnd: Date
    var continuation: PendingContinuation
}

private enum TrackingState {
    case stopped
    case active(ActiveSegment)
    case pendingPersistence(PendingClose)
    case waitingForPresence(ResumeCandidate)
}
```

Sample the terminal end and reason once. If `checkpoint(_:)` fails, retain the resulting session in `.pendingPersistence`. Every retry must submit that exact session without consulting `now()` or `IdleMonitor` again. Pending state accrues no additional time, but its unsaved tail remains visible to canonical totals. `prepareToResume`, `confirmPresence`, and ordinary activation may update only the continuation; after the frozen close persists, resolve that continuation without merging the absence into either stretch.

- [ ] **Step 4: Run the complete headless suite and verify GREEN**

Run:

```bash
./build.sh --check
```

Expected: every test passes, including the new delayed-retry and queued-return assertions.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AppUsageTracker.swift Sources/SelfTest.swift
git commit -m "fix: retain failed usage close boundaries"
```

### Task 2: Serialise stale promotion-lock recovery

**Files:**

- Modify: `build.sh`
- Modify: `scripts/test-build-concurrency.sh`

**Interfaces:**

- Consumes: repository-local `.build/promotion.lock`, per-run owner markers, rollback candidate/backup paths, and normal build promotion.
- Produces: an atomic recovery guard that admits at most one stale-lock recoverer and is released only by its recorded owner.

- [ ] **Step 1: Add a deterministic two-recoverer regression**

Extend `scripts/test-build-concurrency.sh` with a real two-process stale-recovery case. Arrange one stale primary lock and one interrupted transaction, then launch two normal builds against it. Use harness-local command wrappers or a condition barrier to hold the first recoverer after it observes the stale owner while the second contends. Assert observable outcomes rather than source text:

```bash
test "${FIRST_STATUS}" -eq 0 -o "${SECOND_STATUS}" -eq 0 \
  || fail "neither stale recoverer completed"
test ! -e "${LOCK_FILE}" || fail "stale recovery left the primary lock behind"
test ! -e "${RECOVERY_GUARD}" || fail "stale recovery left its guard behind"
codesign --verify "${APP_NAME}.app" \
  || fail "concurrent stale recovery left an invalid local app"
test "$(find "${PROMOTION_ROOT}" -maxdepth 1 \
  \( -name '*.candidate.*' -o -name '*.backup.*' \) | wc -l | tr -d ' ')" = "0" \
  || fail "concurrent stale recovery left transaction debris"
```

The harness must prove that a process cannot remove a newly acquired live primary lock. The existing single-recoverer case is retained.

- [ ] **Step 2: Run the concurrency harness and verify RED**

Run:

```bash
./scripts/test-build-concurrency.sh
```

Expected: the controlled interleaving demonstrates that the second stale observer can remove the first recoverer's newly linked primary lock.

- [ ] **Step 3: Add an atomic recovery guard**

Use an atomic directory creation as the stale-recovery admission point:

```bash
RECOVERY_GUARD="${PROMOTION_ROOT}/promotion-recovery.lock"

if ! mkdir "${RECOVERY_GUARD}" 2>/dev/null; then
  echo "error: another process is recovering a stale promotion lock" >&2
  return 1
fi
printf 'pid=%s\nrun_id=%s\n' "$$" "${RUN_ID}" \
  > "${RECOVERY_GUARD}/owner"
```

After acquiring the guard, re-read the primary lock and confirm its PID, run ID, start value, and filesystem identity still match the stale lock that was observed. Only the guard owner may unlink and replace the primary lock. Release the guard through the existing trap only when its owner marker still names the current run. A live or unverifiable recovery guard fails closed and preserves transaction evidence; no contender removes another process's guard.

- [ ] **Step 4: Run focused and full verification**

Run:

```bash
bash -n build.sh scripts/test-build-concurrency.sh
./scripts/test-build-concurrency.sh
./build.sh --check
./build.sh --test
codesign --verify --deep FocusContinuity.app
git diff --check
git status --short
```

Expected: the single- and dual-recoverer harnesses pass, all headless tests pass, staged strict verification passes, the promoted app passes ordinary verification, and Git remains clean apart from intended source changes before commit.

- [ ] **Step 5: Commit**

```bash
git add build.sh scripts/test-build-concurrency.sh
git commit -m "build: serialise stale promotion recovery"
```

## Acceptance Criteria

- A failed terminal checkpoint retry retains the original end and reason even after the clock advances.
- A confirmed return during a failed close begins a separate UUID at the confirmed return time.
- Pending persistence never accrues unattended time or double-counts a durable prefix.
- Exactly one process may replace a stale promotion lock.
- No contender may remove another process's live primary lock or recovery guard.
- Interrupted transaction recovery retains rollback evidence on failure.
- The concurrency harness, staged build, full self-test, signing checks, diff check, and Git-status check all pass.
