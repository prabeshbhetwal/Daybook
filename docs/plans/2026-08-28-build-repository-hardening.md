# Build and Repository Hardening Implementation Plan

**Goal:** Make source authoritative, stage verified local builds and remove
verification/documentation drift.

**Architecture:** Build and sign in a temporary bundle, promote only verified
outputs, ignore generated artefacts, and keep the existing self-test fast and
self-cleaning.

**Tech Stack:** Bash, `swiftc`, `codesign`, Git, macOS 13+.

**Spec:** `docs/specs/2026-08-28-daybook-stabilisation-design.md`

## Global constraints

- The root app remains the convenient local launch target but is not tracked.
- Ad-hoc signing is local-only; do not claim notarisation or distribution.
- `--check` must not replace the local app or dirty Git.

---

### Task 1: Make source authoritative and stage verified builds

**Files:**
- Modify: `.gitignore`
- Modify: `build.sh`
- Untrack but retain locally: `Daybook.app/`
- Untrack: `.DS_Store`

- [ ] Extend parsing with `--check`; it implies self-test and disables promotion.
- [ ] Assemble in `mktemp -d`, clean with a trap, clear xattrs, ad-hoc sign,
  clear xattrs again and require strict verification on the staged bundle.
- [ ] Promote only after compilation, signing and requested tests succeed; then
  require normal verification on the local app.
- [ ] Untrack the app and `.DS_Store` with `git rm --cached`, leaving the local
  generated app in place.
- [ ] Run `./build.sh --check` and assert Git remains free of build artefacts.
- [ ] Commit as `build: stage and verify local app bundles`.

### Task 2: Accelerate verification and remove documentation drift

**Files:**
- Modify: `Sources/Core/SessionArchive.swift`
- Modify: `Sources/SelfTest.swift`
- Modify: `Sources/Core/SessionEngine.swift`
- Modify: `Sources/Core/DashboardStats.swift`
- Modify: `Sources/App/AppCoordinator.swift`
- Modify: `README.md`
- Modify: `docs/specs/2026-08-28-daybook-stabilisation-design.md`

- [ ] Add an internal archive-capacity injection, defaulted to the production
  capacity, and use a small literal capacity in the ring test.
- [ ] Track and remove self-test scratch directories during cleanup.
- [ ] Remove the duplicate `awayReturnedAt` assignment and unused
  `openTodayWindow` and private `deepWorkShare` symbols.
- [ ] Remove hard-coded test counts and correct the timer, persistence, build,
  historical-integrity and signing documentation.
- [ ] Run `./build.sh --check`, `./build.sh --test`, normal code-signature
  verification, `git diff --check`, and temporary visual snapshots.
- [ ] Commit as `test: harden Daybook verification`.
