---
name: ship
description: Ship the current Daybook change to main — check, commit in the repository's style, merge with main, push, and bring the main checkout up to date. Use only when the user asks to ship, commit and merge, merge to main, or push.
---

# Ship to main

Stop at the first step that fails and report it. Never force-push, and never
skip a failing check.

## 1. Where am I

```bash
git status --short
git branch --show-current
MAIN="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"   # the main checkout
```

If the current folder is not `$MAIN`, this is a worktree session. List the
files this session changed. Ship only those, never someone else's work in
progress.

## 2. Gate

- Behaviour changed under `Sources/` with no new or updated check: stop, and
  add one with the `add-check` skill first. Pure refactors and docs need no
  check.
- A fix to persistence, settings, session state or time arithmetic: run the
  `fix-reviewer` agent on the diff. Resolve a `FIX FIRST` verdict before going
  on.

## 3. Check

Run `./build.sh --check` with the sandbox disabled. It must end in
`N/N passed`. Skip it only when nothing under `Sources/`, `Assets/` or
`build.sh` changed, and say so in the report.

## 4. Commit

1. Stage the session's files by path. Never `git add -A` or `git add .`.
2. Show `git diff --cached --stat`.
3. The repository is public. Stop if the staged lines hold a secret or a
   machine path:
   `git diff --cached -U0 | grep -nE '^\+.*(/Users/[A-Za-z]|PRIVATE[ ]KEY|ghp_[A-Za-z0-9]{20}|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16})'`
4. Commit with `git commit -F -` and a heredoc:
   - Subject: one plain present-tense sentence stating what is now true for
     the user, about 80 characters at most, no type prefix. For example: "A
     relaunch no longer deletes the running session's power readings".
   - Body: prose wrapped at 72 columns. What the user now sees first, then
     how it works and why.
   - End with the co-author trailer this session's instructions give.

## 5. Merge with main

- Worktree session in the desktop app: call `sync_with_base_branch` (base
  `main`). Elsewhere: `git fetch origin && git merge origin/main`.
- Main checkout on `main`: `git pull --no-rebase origin main`.
- Conflicts: resolve them, `git add` the files, `git commit --no-edit`.
- If the merge brought in changes under `Sources/`, `Assets/` or `build.sh`,
  run step 3 again on the merged tree.

## 6. Push

Run `git push origin HEAD:main` with the sandbox disabled. If it is refused
because `main` moved, go back to step 5. Never force.

## 7. Update the main checkout

From a worktree, if `git -C "$MAIN" status --porcelain --untracked-files=no`
prints nothing and `$MAIN` is on `main`, run
`git -C "$MAIN" fetch origin && git -C "$MAIN" merge --ff-only origin/main`
with the sandbox disabled. Otherwise leave it alone and say why.

## 8. After the push

- If `$MAIN/graphify-out/` exists and code changed, run `graphify update .`
  in `$MAIN`.
- Never launch or relaunch the live app, and never run `./build.sh`,
  `--test` or `--run` in `$MAIN`. Each replaces `$MAIN/Daybook.app`, and
  each relaunches a copy running from it. The user opens Daybook from the
  Dock, and its single-instance lock turns away a second copy. If `Sources/`
  or `Assets/` changed, say the new build is on `main` and leave updating the
  app to the user.

## 9. Report

```
Shipped <sha> "<subject>"
origin/main <old>..<new>
Checks: N/N on the merged tree (or: skipped, docs only)
Main checkout: fast-forwarded | left alone (<reason>)
App: not touched (new build on main | docs only)
```
