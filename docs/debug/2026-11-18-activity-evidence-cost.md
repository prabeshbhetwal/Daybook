# What recording activity evidence costs (18 November 2026)

Phase A, task 13, "the cost gate". The gate: beats, which carry no device
signals in Phase A, add under 1% CPU and under 2 MB resident memory against
today's idle figures. The task has two steps: a headless cost probe (step 1)
and a live comparison against the installed release (step 2).

**Status: step 1 passed with a wide margin. Step 2 (live) ran on 19 November 2026: CPU passes, memory is unresolved; see below. The full
gate is NOT yet passed.**

## Step 1 (headless): method

A throwaway copy of the build inputs (`rsync -a build.sh Sources Assets
scripts`) in a temporary folder, never the working tree. In the copy, a
`main.swift` compiled with every file under `Sources/Core`, as the
"Runtime probes" section of `CLAUDE.md` describes. `BeatRecorder`, `Beat`,
`BeatArchive`, `CountedTime` and `ActivityDerivation` are all Core, so this
is the shipped code, not a stand-in.

- **Flags:** the ones `build.sh` uses for the app, `-Osize
  -whole-module-optimization -swift-version 5 -target arm64-apple-macos14.0`.
  `-warnings-as-errors`, `-framework Cocoa` and Sparkle were left out because
  the probe is Core only and the flags do not change generated code.
- **Machine:** Apple M1 Pro (MacBookPro18,3), macOS 27.3, Swift 6.4.2.
- **Workload, the real size:** 28 800 ticks of 1 s (8 hours), 8 apps. The
  presence runs 5 to 300 s long and is drawn 58% input, 25% quiet, 8%
  watched, 6% agent, 2% watch-pause, 1% paused; the front app switches
  every 5 to 120 s (about every 63 s on average, through
  `BeatRecorder.activate`); the input counters move only while presence is
  input; watched holders are passed on watched and agent ticks. The random
  schedule is generated first, from a fixed seed, so the timed loop does only
  recorder work and every run sees the same day.
- **Mean tick:** the whole 28 800-tick loop (every `tick` call plus the
  `activate` calls, and the beat close every 30th tick), divided by 28 800,
  median of 5 loops after one warm-up. A second, separately clocked loop
  gives the spread per tick.
- **Archive:** every beat the recorder returned (including the partial beat
  from `stop`) went through `BeatArchive.append` into a scratch folder, one
  real day file on disk.
- **Derivation:** the call sequence the app makes for a session read in
  `SessionStore+SessionActivity.swift`: `CountedTime.spans`, then
  `ActivityDerivation.derive` over one session spanning all 8 hours (961
  beats, `countsWhileWatching` on, no signals, pauses taken from the beats,
  which is the heavier branch). Median of 5 after one warm-up. The
  whole read path is also timed: `archive.beats(in:)` plus the above, with the
  cache warm, and with a fresh `BeatArchive` (directory listing, file read and
  JSON decode of the day file).
- **Where it ran:** the probe binary ran outside the Bash sandbox, because
  inside it `createFile` in the scratch folder fails. It touched only its own
  scratch folders. The live Application Support folder and defaults were
  never read or written. Three runs were made.

## Step 1: figures

| Measure | Run 1 | Run 2 | Run 3 | Pass if |
|---|---|---|---|---|
| Mean time per tick | 0.613 us | 0.603 us | 0.644 us | under 100 us |
| 8-hour derivation (median of 5) | 18.6 ms | 19.8 ms | 17.8 ms | under 50 ms |
| Beats from 28 800 ticks | 961 | 961 | 961 | n/a |
| Day file on disk | 116 649 bytes | 116 649 bytes | 116 649 bytes | n/a |

Supporting figures, same three runs:

- Per-tick spread (clocked individually): p50 0.58 us, p99 1.4 to 1.6 us.
  The slowest single tick was 89 us, 375 us and 37 us in runs 1, 2 and 3. The
  gate is a mean, and one such tick in 28 800 moves it by about 0.01 us; an
  outlier that size is most likely the process being descheduled (not
  confirmed).
- Ticks that close a beat (the most expensive 1 in 30): mean 1.5 to 4.5 us.
- Appending a beat: 143 to 603 us per beat (one beat per 30 s), the first run
  slower while the file was new. About 0.15 to 0.6 ms of file I/O every
  30 seconds.
- Day file: 961 beats, 121 bytes a beat, 114 KB for 8 hours. A day of heavier
  app switching than this workload would write somewhat more.
- Whole read path with a warm cache: 19.4 to 22.4 ms. With a fresh archive
  (decode included): 27.2 to 30.3 ms.
- The derived shape for the synthetic day: 61 phases, 7 purposes credited,
  27 833 s counted.

## Step 1: verdict

**Pass.** The mean tick is about 0.6 us, roughly 160 times under the 100 us
limit; a tick every second is about 0.00006% of one core. The 8-hour
derivation is about 19 ms against a 50 ms limit, and even a cold read that
decodes the day file from disk is about 30 ms. The recorder's work is
dominated by the beat close every 30 ticks, and the file append is one small
write every 30 seconds.

What step 1 does not cover, and so what step 2 still has to:

- The real counter reads (`counters()` and `idleSeconds()` called only when a
  beat closes) and the app's own 1 Hz sampling were replaced by constants.
  Only the recorder's, archive's and derivation's own cost is measured.
- Resident memory was not measured. The only memory figure here is that the
  day file is 114 KB, and a decoded day is of that order.
- Main-thread effects (when the append and the derivation run relative to the
  UI) are not visible in a headless probe.
- The workload is synthetic, with the seed above; real days will differ in
  switch rate and presence mix.

## Step 2 (live run): run on 19 November 2026

The owner approved the run. Two 40-minute runs, one after the other on the same
Mac, each with a focus session started: 20 minutes of ordinary work, then 20
minutes idle with the session still running. Baseline: the installed 1.3.3
release. Candidate: a build of the Phase A branch (aedce23, the same content as
`main` after PR 87, without the later goals commits), launched from the
worktree, writing beats into the live data folder as approved. Only one copy
ran at a time, no build or other heavy job ran during either run, and the
installed app was relaunched afterwards.

Sampling: the process's cumulative CPU time and resident memory every 10 s.
Mean CPU is the CPU seconds gained divided by the wall seconds. This differs
from the plan's `ps %cpu`, which on macOS is a lifetime average and would hide
a change. Resident memory is `ps rss`.

| | Baseline (1.3.3) | Candidate (Phase A) | Difference |
|---|---|---|---|
| Working, mean CPU | 0.58% | 0.98% | +0.40 points |
| Idle, mean CPU | 0.51% | 0.42% | -0.09 points |
| Working, median memory | 46.9 MB | 46.0 MB | -0.9 MB |
| Idle, median memory | 46.6 MB | 51.8 MB | +5.2 MB |
| Whole run, median memory | 46.7 MB | 49.2 MB | +2.5 MB |

**CPU: passes.** The worst phase is +0.40 percentage points, against a limit
of 1.

**Memory: not a clean pass, and not conclusive.** The whole-run median is
+2.5 MB against a limit of 2 MB, and the idle half alone is +5.2 MB. But
resident memory on this Mac swings far more than that on its own: the median
of each five-minute block moved between 35 and 59 MB in the baseline and
between 30 and 57 MB in the candidate, because the machine was short of free
memory and compressed pages in and out. A 2 MB difference cannot be told apart
from that noise with one run each. The candidate also holds a few days of
decoded beats in memory (the archive caches up to eight day files, about 114 KB
each as measured above), which accounts for well under 1 MB.

**Verdict:** the CPU half of the gate passes. The memory half is unresolved: it
misses the 2 MB bar on the whole-run median and cannot be shown to pass or fail
under this noise. A repeat measuring physical footprint (`footprint -p`) on a
quieter machine would settle it. Release is the owner's call.

## Cleanup

The tree copy and every scratch folder (`fc-tree.*`, `fc-probe-beats-*`) were
moved to the trash with `trashmv`. Nothing under `Sources/` in the worktree
changed.
