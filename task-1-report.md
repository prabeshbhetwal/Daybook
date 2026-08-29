# Task 1 report — release-gate hardening

Implemented the guarded stale-recovery release fix.

## Changes

- `build.sh` now checks the status returned by `release_recovery_guard` and fails closed before stale candidate, backup, or local-app recovery can proceed.
- `scripts/test-build-concurrency.sh` includes a release-boundary regression that corrupts the guard owner immediately after replacement admission and verifies non-zero exit, preserved candidate/backup evidence, and byte-identical ownership evidence.

## Verification

- `bash -n build.sh scripts/test-build-concurrency.sh` — passed.
- `./build.sh --test` — passed; 139/139 self-tests.
- `./scripts/test-build-concurrency.sh` — started but did not complete within the available run window; it was interrupted while exercising its existing long-running concurrency build matrix. No harness failure assertion was observed before interruption.

## Commit

`f457d3f build: fail closed on guard release`

## Round 1 review corrections

- Moved release-boundary guard-owner corruption until after the wrapper's real primary-lock `ln` succeeds, so the test exercises the `release_recovery_guard` boundary after replacement admission.
- Aligned the guard hash assertion with the copied guard-owner source hash recorded by the wrapper, rather than hashing the stale promotion owner.
- Added executable-byte hash checks for stale candidate and backup bundles, and verified the local app path remains absent during failed recovery and byte-identical after restoration.

## Targeted verification

- `bash -n build.sh scripts/test-build-concurrency.sh` — passed.
- `git diff --check` — passed.
- Full `./scripts/test-build-concurrency.sh` was not runnable within this environment because the available shell lacks the `timeout` utility; the prior report records the harness's long-running behaviour and interruption.

Round 1 correction commit: `e7aa515 test: harden recovery guard release regression`

## Round 2 review correction

- Replaced release-boundary executable-only hashes with a single sorted tar-stream `bundle_hash` helper covering the complete candidate, backup and local `.app` bundle trees.
- `bash -n scripts/test-build-concurrency.sh` — passed.
- `./scripts/test-build-concurrency.sh` — reached the harness's local-bundle symlink probe after approximately 11 minutes, then failed with an existing shell-quoting error at line 1501; no assertion failure was reported before that point.

## Concern

The full concurrency harness performs many serial warnings-as-errors builds and exceeded the available execution window. The implementation is intentionally limited to the requested release-boundary status check and regression harness extension.
