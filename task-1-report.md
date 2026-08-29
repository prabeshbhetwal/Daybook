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

## Concern

The full concurrency harness performs many serial warnings-as-errors builds and exceeded the available execution window. The implementation is intentionally limited to the requested release-boundary status check and regression harness extension.
