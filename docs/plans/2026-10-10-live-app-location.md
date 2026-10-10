# Where the live Daybook should live

**Status:** Sir chose option 1 on 10 October 2026. `build.sh --install`
exists; steps 3 to 5 below are Sir's.

## What goes wrong today

- The daily app runs from the main checkout's `Daybook.app`, under
  `~/Desktop`. Desktop and Documents are both iCloud file-provider domains
  (`com.apple.file-provider-domain-id` on each), so worktrees under
  `~/Documents/FocusContinuity` are in the same position: a worktree's
  `Daybook.app` carries `com.apple.fileprovider.fpfs#P`.
- iCloud puts `com.apple.quarantine` back after `build.sh` clears it. A launch
  that does not come through `build.sh` (Finder, Open at login, System
  Settings' Quit & Reopen) then runs translocated, from a read-only mount at
  `…/AppTranslocation/<UUID>/d/Daybook.app`.
- Translocated, Sparkle refuses to update: `SURunningTranslocated = 1005` in
  Sparkle 2.10.0's `SUErrors.h`. The copy also keeps running old code after
  the next build replaces the bundle.
- Launch Services keeps a record for every Daybook bundle it has seen, and
  Spotlight-indexed folders register theirs again: the
  `_trash/worktrees-2026-10-07/…/Daybook.app` record removed by hand on
  10 October was back by 21:05 the same day. Anything that opens Daybook by
  bundle identifier gets Launch Services' pick among them; on 10 October that
  was an old worktree's copy.

`build.sh` now removes the records its staged builds leave behind, and traces
a translocated copy back to its bundle so `--run` and `--test` can quit it.
Neither stops the quarantine.

## Options

| Option | Quarantine stops | Copies left competing for the ID | Cost |
|---|---|---|---|
| 1. `build.sh --install` into `~/Applications/Daybook.app` | Yes | Checkout and worktree builds | One flag, one-time login-item move |
| 2. The same into `/Applications/Daybook.app` | Yes | Same | Shared by every account on the Mac |
| 3. Move the repository out of Desktop & Documents | Main checkout only | Same | Worktrees are still created under `~/Documents`; Claude's per-project memory is keyed by the checkout path |
| 4. Promote into a `*.nosync` folder in the checkout | Unproven | Same | Needs a probe first: iCloud skips `.nosync` items, but nothing shows the quarantine stops, and the folder is still indexed |

## Recommendation: option 1

- `./build.sh --install` runs the same staging, self-test, lock and backup
  swap as `--test`, with `~/Applications/Daybook.app` as the target, then
  relaunches a copy running from there (or a translocation of it).
- `--check`, `--test` and `--run` stay as they are, so worktree builds and
  `scripts/release.sh` (which runs `--test` and zips the checkout's bundle)
  are unaffected.
- `~/Applications` belongs to Sir and is not synced: no admin prompt for
  Sparkle, and nothing puts the quarantine back.
- `/Applications` (option 2) works too (`root:admin rwxrwxr-x`, and Sir is an
  admin), but it is shared with every account and gains nothing here.

## Open at login

- `SMAppService.mainApp.register()` records the bundle that calls it, by
  path. If Open at login is on, today's record points at the checkout copy.
- 6 October: `register()` and `status` failed with error 22 because the
  running app's bundle had been deleted beneath it (`smd … errno = 2`). An
  install that replaces the running copy must relaunch it, as `build.sh`
  already does for the checkout.
- A record for a bundle that later disappears made `register()` fail with
  error 22 until `sudo sfltool resetbtm` and a restart (CLAUDE.md, Runtime
  probes). So the order matters:
  1. In the running checkout copy, turn Open at login off.
  2. Run `./build.sh --install` and open `~/Applications/Daybook.app`.
  3. Turn Open at login on there.
  4. Only then retire the checkout's `Daybook.app` (move it to `_trash/`).
- `sudo sfltool dumpbtm` shows the path each record holds.

## Sparkle

- An update replaces the running bundle where it is, so it needs that folder
  writable and the app not translocated. Both hold in `~/Applications`.
- Today an update would overwrite a build product inside the repository, and
  fails outright whenever the checkout copy runs translocated.
- A release installs over the `--install` copy, and a later `--install` puts
  a development build back. Sparkle compares `CFBundleVersion`, so a
  development build with the release's `APP_BUILD` is offered nothing until
  the next release, as now.

## Unchanged, and one unknown

- Live data (`~/Library/Application Support/Daybook/`, the
  `com.prabesh.daybook` defaults) does not depend on where the bundle is.
- Theory, unverified: privacy grants (Input Monitoring, Accessibility) for an
  ad-hoc signed app follow its signature, not its path, so the first
  installed build may need them granted again, as a rebuild can today.

## Steps if approved

1. `build.sh --install`, with the promotion target as a variable; probe it in
   a temp tree with `HOME` pointed at a scratch folder. About an hour.
2. The `ship` skill and CLAUDE.md: the main checkout updates the live app
   with `--install`.
3. Sir: the Open at login steps above. Five minutes.
4. Check: Launch Services resolves `com.prabesh.daybook` to
   `~/Applications/Daybook.app` (`NSWorkspace.urlForApplication(withBundleIdentifier:)`,
   which launches nothing); no `com.apple.quarantine` on the bundle a minute
   after installing; Check for Updates gives no error 1005.
5. Retire the checkout's `Daybook.app` to `_trash/`, with Sir's go.
