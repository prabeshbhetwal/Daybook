# FocusContinuity

A macOS menu-bar app that keeps focus sessions honest from foreground-app
evidence. Swift in the Swift 5 language mode (`-swift-version 5`), AppKit and
SwiftUI, deployment target macOS 13.0. There is no Xcode project and no
`Package.swift`: `build.sh` compiles every file under `Sources/` with `swiftc`
as one module.

## Commands

| Command | What it does |
|---|---|
| `./build.sh --check` | Build and run every self-check; never replaces the local app. Run before each commit. |
| `./build.sh --test` | The same, then replaces `FocusContinuity.app` |
| `./build.sh --run` | Build, verify and relaunch the app |
| `FC_KEEP_SYMBOLS=1 ./build.sh` | Keep symbols for profiling with `sample` |
| `scripts/release.sh 1.2.0 [--dry-run]` | Publish a release installed copies update to (Sparkle; key in the Keychain) |

- `build.sh` fails inside the Claude Bash sandbox at the `sips` icon step (it
  cannot write to the system temp folder). Run it with the sandbox disabled.
- Compile-only check that works in the sandbox, about 100 s:
  `swiftc -typecheck -module-cache-path "$TMPDIR/mc" -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 $(find Sources -name '*.swift')`
- A build that replaces the app holds `.build/promotion.lock`; a second build
  waits up to two minutes. Remove the lock only when no build is running.
- `codesign --verify --strict` fails on the promoted bundle in an
  iCloud-synced folder because Finder extended attributes come back. Plain
  `--verify` passes, and the staged candidate passes strict.

## Architecture

Core → App → Design/Surfaces, in one direction only; the README has the map.

- Core is UI-free: the session state machine, usage tracking, persistence
  formats and pure calculations. `build.sh` typechecks `Sources/Core` on its
  own beside the main compile, so a Core file that uses an App type fails the
  build; move the type into Core instead.
- App owns the macOS wiring and publishes read models. It is the only
  boundary for session actions, settings, refresh coalescing and navigation.
- Views never read storage or recalculate time. The one 1 Hz ticker lives in
  `SessionStore`; the UI adds no timers of its own.
- `SessionEngine` and `SessionStore` each span several files, so `build.sh`
  (`keep_internals`) enforces their privacy: a line outside
  `Sources/Core/SessionEngine*` or `Sources/App/SessionStore*` that touches a
  listed internal member fails the build. Add a method on the owner instead,
  and add any new internal member to its list.

## Self-checks

- The headless suite is `Sources/SelfTest.swift` plus `Sources/Verification/`.
  Use the `add-check` skill to add one.
- New suites go at the end of `registeredTests` in
  `Sources/Verification/SelfTest/SelfTest+Registry.swift`. A check's position
  is its number, and comments cite those numbers.
- Checks never touch live data: they use `TestClock`,
  `SelfTest.scratchDirectory()` and an isolated `fc-selftest-…` defaults suite.
- A fix comes with a check that fails on the old behaviour. Before committing
  a fix to persistence, settings, session state or time arithmetic, run the
  `fix-reviewer` agent on it.

## Runtime probes

A claim that something cannot happen needs a probe, not an argument. Probes
work in a fresh `mktemp -d` folder, never in the working tree and never on live
data, and report what they observed (`saved=false published=true`). For an
open-ended bug hunt over an area, use the `probe-hunter` agent.

- Core logic, about 20 s. Core compiles on its own, so drive it from a
  `main.swift`: `P="$(mktemp -d "$TMPDIR/fc-probe.XXXXXX")"`, write
  `"$P/main.swift"`, then
  `swiftc -module-cache-path "$TMPDIR/mc" -swift-version 5 -target arm64-apple-macos13.0 -o "$P/run" $(find Sources/Core -name '*.swift') "$P/main.swift" && "$P/run"`
- Anything above Core. `build.sh` reads only itself, `Sources/`, `Assets/`
  and `scripts/fetch-sparkle.sh`, so copy those:
  `T="$(mktemp -d "$TMPDIR/fc-tree.XXXXXX")"; rsync -a build.sh Sources Assets scripts "$T/"`.
  The copy fetches Sparkle once into its own `.build/vendor/` (15 MB, pinned
  checksum); copy `.build/vendor` across too to work offline.
  Add a temporary check or change in the copy and run `./build.sh --check`
  there with the sandbox disabled. The same copy serves a mutation test: put
  the old behaviour back and confirm the new check fails.
- Remove the folders when done.

## Live data

`~/Library/Application Support/FocusContinuity/` (`sessions.json`,
`app-usage.json`) and the `com.prabesh.focuscontinuity` defaults domain are the
user's real history. `.claude/hooks/guard-live-data.py` blocks Claude from
changing them. `FC_LIVE_DATA_OK=1` in a command lets one through; use it only
when the user has asked for that exact change. After editing the guard, run
`python3 .claude/hooks/guard-live-data.py --check`.

## Conventions

- Ship with the `ship` skill: it checks, commits in the style below, merges
  into `main`, pushes and updates the main checkout.
- Commit subject: one plain present-tense sentence stating what is now true
  for the user, e.g. "A relaunch no longer deletes the running session's power
  readings". No type prefixes. The body is wrapped prose: what changed and why.
- Edit Swift by exact text, never by line number. `.claude/hooks/swift-parse.sh`
  parses each Swift file Claude writes and reports a stray or missing brace.
- The repository is public: no secrets, personal data or machine-specific
  paths in commits.
- Documentation lives in `docs/specs/`, `docs/plans/`, `docs/reviews/`,
  `docs/debug/` (dated reports), `docs/design/` and `docs/screenshots/`.
  Preserve recorded evidence rather than rewriting it.
- Code questions go to CodeGraph (`.codegraph/`), and architecture and docs
  questions to `graphify-out/GRAPH_REPORT.md`. Do not use code-review-graph
  in this repository.
- Local only, ignored by git: `graphify-out/`, `.codegraph/`,
  `.code-review-graph/`, `research/`, `_trash/`, and everything in `.claude/`
  except `settings.json`, `hooks/`, `skills/` and `agents/`.

## Apple documentation

The `apple-docs` MCP server (`.mcp.json`) reads Apple's current documentation,
which is newer than model training. Use `search_framework_symbols` (for
example framework `swiftui`, `namePattern` `*numeric*`) and
`get_apple_doc_content` with a documentation URL. `search_apple_docs` returns
no results as of version 1.0.26.
