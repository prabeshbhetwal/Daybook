# Site signal probe: steps for the owner (19 November 2026)

The site signal stays off for everyone until this probe passes on the macOS
major you run. The probe is the app's own reader (`AXSiteAddressReader`) and the
Core site rules, compiled with a small `main.swift` and run from Terminal. It
reads the front browser every 2 seconds and prints kinds and timings. Nothing
here launches Daybook, and nothing here needs Daybook's own Accessibility
permission: during the probe, Terminal holds the grant.

## Rules for the whole run

- Public test pages only (the list below). No banking, mail, work or personal
  pages in any window while the probe runs, including other tabs and windows of
  the browser under test.
- The probe never prints an address. `--show-site` also prints the site name
  (host only). Use it to find out why a read went wrong, never in a report.
- The report keeps kinds and timings only.
- Remove Terminal's Accessibility grant when you are finished (step 6).

## 1. Build

From the repository folder (the build takes well under a minute):

```sh
swiftc -O -module-cache-path "$TMPDIR/mc" -swift-version 5 -target arm64-apple-macos14.0 \
  -o "$TMPDIR/site-signal-probe" \
  $(find Sources/Core -name '*.swift') \
  Sources/App/AXSiteAddressReader.swift Sources/App/WebLinkApps.swift \
  scripts/site-signal-probe/main.swift
```

All of `Sources/Core` is needed because the site files use `PurposeRule` and
`FocusConstants`. Add `-warnings-as-errors` and swap `-O -o ...` for
`-typecheck` to check the build without producing a binary.

## 2. Grant Terminal Accessibility

1. System Settings > Privacy & Security > Accessibility.
2. Add Terminal (the plus button) or tick it, then restart Terminal.
3. The probe only asks `AXIsProcessTrusted()`. It never shows a prompt. If the
   grant is missing it prints how to give it and exits.

## 3. Run

Start the probe in Terminal, then click the browser under test so it is in
front and stays in front for the whole run. A run reads for 120 seconds by
default. For a pass check use 40 seconds, which gives 20 reads:

```sh
"$TMPDIR/site-signal-probe" --seconds 40 --expect video
```

`--expect` takes a kind (`video`, `documentation`, `codeHost`, `social`,
`shopping`, `mail`, `aiChat`, `meeting`) or `none`. The summary then also counts
the reads that gave the expected result.

Each read prints `browser | result | ms | elements walked`. `result` is a kind,
`none` (an address was read and has no kind), `failed` (no web area or address)
or `timedOut`. The reader does not report how many elements it walked, so that
column prints `n/a`; time is what the probe measures. The run starts with the
web-link apps macOS reports, which is what the app's browser list would offer.

For each browser you intend to support, run it once per page:

| Page | Expect |
|---|---|
| A YouTube video page (any public video) | `video` |
| developer.apple.com (any public page) | `documentation` |
| github.com (any public repository page) | `codeHost` |
| A heavy web app: a large public demo spreadsheet or web app with thousands of elements | note the result; `none` is fine, a wrong kind is not |
| A background tab: the test page in a tab that is not the front tab, with a different test page in front | the kind of the front tab |
| A private window with a test page in front | the kind of the page, or `failed` or `none` |

Do one extra run for a hung browser: in a second Terminal tab, find the
browser's process id (`pgrep -x Safari`, for example), freeze it with
`kill -STOP <pid>`, run the probe for 20 seconds with the browser still in
front, then `kill -CONT <pid>`. Expect `timedOut` on consecutive reads, the
summary line `two consecutive timeouts: yes`, and no read longer than
`readDeadline` plus `readTimeout`. The app stops reading a browser after
`timeoutsBeforeSkipping` (2) consecutive timeouts; that rule is in
`SiteSignalReader` and is covered by the self-checks, so the probe only has to
show the timeouts arrive promptly.

## 4. Pass criteria, per browser and per macOS major

- Each test page's kind is right in at least 19 of 20 reads (`right` in the
  summary).
- p95 latency under 250 ms.
- No read longer than 600 ms (`longest` in the summary), on the healthy pages.
- A hung browser times out and is skipped after two timeouts (the extra run
  above).
- The background tab never shows the background page's kind, and no run ever
  gives a wrong kind. `none` or `failed` loses a signal but is safe; a wrong
  kind is not.

If anything fails, do not make the gate line below. Size the timeouts and run
again (next section) or leave the signal off for that major.

## Sizing `readTimeout` and `readDeadline`

Both live in `SiteSignalConstants` (`Sources/Core/SiteSignalSettings.swift`).
`readTimeout` (now 0.5 s) is how long one Accessibility message may take.
`readDeadline` (now 1.0 s) is how long a whole read may take before it gives
up; one message can still run past the deadline, so a read ends within about
`readDeadline` plus `readTimeout`.

Read the probe's `ms` column on the healthy pages, then:

- Healthy reads usually under 150 ms and the longest under 300 ms: the values
  are fine. They can be lowered (for example 0.3 s and 0.6 s) to give up on a
  hung browser sooner, but there is no need.
- Healthy pages sometimes `timedOut`, or p95 near 250 ms: raise `readTimeout`
  first (0.5 to 0.75), then keep `readDeadline` at least twice `readTimeout`
  (1.0 to 1.5). The 600 ms ceiling is then at risk; if the longest healthy
  read still exceeds it, the browser is too slow to read and that browser fails.
- A heavy web app that gives `failed` after about `readDeadline`: the walk ran
  out of time or elements (`maxElements` 400, `maxDepth` 12). That is the safe
  failure; record it in the report.

Change the constants in one small commit, rebuild the probe and run it again.
Constants outside the signature mean no algorithm version bump.

## 5. Report

Write `docs/debug/<date>-site-signal-probe.md`: kinds and timings only, no
addresses, no site names beyond the test pages' kinds, nothing about other
windows.

```text
# Site signal probe (<date>)

macOS: <major.minor>, <hardware model>
Constants: readTimeout <s>, readDeadline <s>, maxElements 400, maxDepth 12

| Browser (version) | Page | Reads | Right | Successes | p50 ms | p95 ms | Longest ms | Two timeouts in a row |
|---|---|---|---|---|---|---|---|---|
| ... | video | 20 | | | | | | |

Hung browser run: <browser>, timed out <n> times, longest read <ms>.
Background tab: <result>.   Private window: <result>.
Result: pass or fail, per browser, per macOS major.
```

## What lands in the same commit if it passes

One commit, containing:

1. The report above.
2. `SignalGate.passing = [.siteKind: [<macOS major>]]` in
   `Sources/Core/SignalGate.swift`.
3. `BeatArchiveChecks` check 7 changed to expect the site signal's gate on for
   that major (`Sources/Verification/BeatArchiveChecks.swift`).

That commit gets a scoped security re-review before it merges, because it is
the one that turns the live path on. Run the full `./build.sh --check` (and the
two time-zone runs) on it first.

## 6. Afterwards

- Remove Terminal's Accessibility grant: System Settings > Privacy & Security >
  Accessibility, select Terminal, press the minus button.
- Delete the probe binary (`$TMPDIR/site-signal-probe`) and the module cache.
- Close the test windows. Nothing the probe read was stored or logged.
