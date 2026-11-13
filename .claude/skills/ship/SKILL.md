---
name: ship
description: Ship the current Daybook change to main through a pull request — check, commit in the repository's style, merge with main, push a branch, open a PR that auto-merges once CI passes, and bring the main checkout up to date. Use only when the user asks to ship, commit and merge, merge to main, or push.
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

- On `main` itself (the main checkout): move the commit to a branch first,
  `git switch -c ship/<short-topic>`, since `main` only takes pull requests.
- `git fetch origin && git merge origin/main`.
- Conflicts: resolve them, `git add` the files, `git commit --no-edit`.
- If the merge brought in changes under `Sources/`, `Assets/` or `build.sh`,
  run step 3 again on the merged tree.

## 6. Pull request

Every change reaches `main` through a pull request that merges only once
GitHub's required `check` passes. Never push to `main` directly, even though
GitHub would allow it.

1. `git push -u origin HEAD` with the sandbox disabled. Never force.
2. Open it: `gh pr create --base main --title "<the commit subject>"
   --body-file -`, the body from the commit body (several commits: one
   short paragraph each). Use the `pr` skill if one is installed.
3. In the desktop app, bind the PR to the session so its CI and review
   comments are watched, and offer Auto-fix.
4. Wait for Codex's review of the latest commit. The `check` can pass first
   (it runs on every push), and branch protection does not wait for Codex,
   so auto-merge stays off until the review is in. Answer each finding with
   a fix pushed to the branch, or a reply saying why not; a pushed fix gets
   a new review, so wait again.
5. Once Codex has reviewed the latest commit with nothing unresolved (it
   reacts 👍 or its findings are answered), turn on auto-merge:
   `gh pr merge <n> --auto --merge --delete-branch`. A merge commit keeps
   each commit's own subject for the release notes.
6. Report the PR link and where it stands. Do not poll CI or the review;
   the desktop app reports them.

## 7. Update the main checkout

Once the PR has merged: from a worktree, if
`git -C "$MAIN" status --porcelain --untracked-files=no` prints nothing and
`$MAIN` is on `main`, run
`git -C "$MAIN" fetch origin && git -C "$MAIN" merge --ff-only origin/main`
with the sandbox disabled. Otherwise leave it alone and say why.

## 8. After the merge

- If `$MAIN/graphify-out/` exists and code changed, run `graphify update .`
  in `$MAIN`.
- Never launch or relaunch the live app, and never run `./build.sh`,
  `--test`, `--run` or `--install` in `$MAIN`. Each replaces a bundle the
  user may be running (`--install` replaces the live app,
  `/Applications/Daybook.app`), and each relaunches a copy running from it.
  The user opens Daybook from the Dock, and its single-instance lock turns
  away a second copy.
- The user's app updates only from GitHub Releases, through Sparkle, never by
  a local `--install`. If `Sources/` or `Assets/` changed, say the new build
  is on `main` and offer a release: the next patch version (one past the
  latest `v*` tag) with `scripts/release.sh <version>` on an up-to-date
  `main` (a fresh clone if the main checkout is busy). It merges its version
  commit through its own PR, waits for the required check, and only then
  tags and publishes, so run it in the background. Run it with the sandbox
  disabled, a `--dry-run` first. Read the dry run's `notes.md` before the
  real run: every user sees those lines in the update window, so each must
  read as a release note for any user. A release publishes to a public repository,
  so run it only on the user's yes. The installed app then finds it on its
  next automatic check, or at once from Check for Updates.

## 9. Report

```
PR <link> "<subject>": auto-merge on, waiting for check (or: merged as <sha>)
Checks: N/N on the merged tree (or: skipped, docs only)
Main checkout: fast-forwarded | left alone (<reason>)
App: not touched (release offered: <version> | released: <version> | docs only)
```
