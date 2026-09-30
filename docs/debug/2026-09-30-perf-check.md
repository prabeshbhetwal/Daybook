# Performance and weight check, 2026-09-30

Commit under test: `0867c1d`; the changes it led to are `299aed0`, `96ef825` and `57404ec`. Machine: the author's Mac, macOS 27.2, Apple silicon, the real archive (about 200 sessions, 7,200 app-use records). Tools: `top`, `ps`, `sample`, `heap`, `leaks`, `vmmap`, `malloc_history`, `/usr/bin/time`.

## Bottom line

At rest the app is idle. With its window open it spends about 3–5 % of one core, spread thinly across SwiftUI's own graph updates, with no hot spot in app code. Memory is 45 MB resident at rest and about 100 MB with the window open. `leaks` finds nothing, but the window-open footprint was climbing by 8–9 MB a minute: text under `.contentTransition(.numericText())` that changes every second keeps its glyph bitmaps on macOS 27, and the story had three such clocks plus three animations keyed on per-second values. Fixed; the climb is gone. The binary was 17.5 MB and is now 5.6 MB, with the self-tests running slightly faster.

## 1. CPU

| State | CPU (one core) | Idle wakeups/s |
|---|---|---|
| Menu bar only, session running, window closed | 0.1–0.5 %, bursts to 4 % when the journal is written | not measured |
| Window open on the day's story, session running | 5.2–5.9 % | 62–66 |

Where the window-open cost goes, from an 8 s and a 4 s `sample`:

- The main thread has no branch worth 0.5 % of the run. Its non-idle time is many small SwiftUI `AttributeGraph` updates, `swift_retain`/`release` and layout compares, which is the story re-evaluating when the store publishes once a second.
- The heaviest app-code frames over 8 s: a copy of `PowerObservation` (14 samples), `DurationText.spoken(in:)` (9) and inside it `NSRegularExpression.init` (9), `DashboardStats.ensure` (5). Together under 0.5 %. The regex was being compiled on every accessibility label; it is compiled once now.
- Nothing in app code runs per frame. The only two repeating animations are the microphone's listening pulse and the welcome tour's breathing ring, and neither is on the story.

The 60 Hz wakeups therefore belong to CoreAnimation and SwiftUI while a live clock is on screen, not to a timer of ours. The app's one timer ticks at 1 Hz with a 0.25 s tolerance and stops when nothing runs.

## 2. Memory

| State | Resident | Physical footprint |
|---|---|---|
| Rest | 45 MB | 119 MB |
| Window open | ~100 MB | 147 MB |

- `leaks`: 0 leaks, 0 bytes.
- `heap`: 128 MB malloced in 565k nodes. The largest live sites are SwiftUI drawing layers (`CGDrawingLayer.draw`) and the `PropertyList.Element` tree (61k, 9.5 MB); three arrays of `AppUsageSession` hold 1.3 MB, the whole archive.
- **The window-open footprint climbed by 8–9 MB a minute** (106 → 133 MB in three minutes on a fresh launch with nothing attached but `top`; a 30-minute-old process had reached 200 MB). With the window closed it is flat and falling (43 → 32 MB over three minutes).
- `malloc_history` under `MallocStackLogging=lite`, two snapshots 90 s apart: every growing site was glyph bitmaps (`CGGlyphBuilderLockBitmaps`) drawn through `RenderBox … Layer::make_cgimage` from a `CGDrawingLayer`, 5–9 new blocks a second per site, and on the second pass `RBInterpolatedDisplayListContents`: an animation being interpolated again every second.
- A 30-line probe app settled the cause: static text flat; plain text changing every second flat (20 → 19 MB in 75 s); the same text under `.contentTransition(.numericText())` with the animation keyed on the minute, 20 → 26 MB in 75 s. On this macOS the numeric transition keeps the glyphs of every value it has shown.
- Six sites on the story hit this: the bar clock, the hero clock and the running card's clock (all `hh:mm:ss` under the numeric transition, changing every second); the rail's goal and app-use figures rolling on the raw seconds behind a figure printed in minutes; and the goal ring settling on the raw share every second.

Fixes, all invisible in the rendered result: `ClockText` draws the hours and minutes as the rolling text and the seconds as plain text beside them; the rail figures roll on their printed text; the ring settles per half per cent. 536/536.

Watch after the fixes, fresh launch, window open, nothing attached but `top`:

| Minute | 0 | 1 | 2 | 3 | 5 | 7 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|
| Footprint | 114 MB | 114 | 121 | 131 | 143 | 147 | 151 | 152 |

The rate fell from about 4 MB a minute to nothing over the last minute, against a steady 9 MB a minute before the fixes. Two periodic refreshes (20 % CPU for a minute at 23:36 and 23:41) fall inside the window. Whether 152 MB is the plateau or a slower climb needs an hour with the window open; the remaining numeric transitions on the page (the ring's percentage, finished totals) change rarely and are the next suspects if it keeps rising.

## 3. Weight

| Build | Binary | `__text` | Stripped |
|---|---|---|---|
| `-O` (before) | 17.5 MB | 7.0 MB | 8.8 MB |
| `-O -dead_strip` | 17.2 MB | 7.0 MB | 8.8 MB |
| `-Osize` | 15.3 MB | 4.1 MB | 5.95 MB |
| `-Osize -dead_strip` | 15.2 MB | 4.1 MB | 5.94 MB |

Half of the old file was the symbol table (42,524 symbols, 9 MB of `__LINKEDIT`), which serves only `sample` and crash reports. Dead-stripping removes nothing worth having. `-Osize` shrinks the code by 41 %.

Speed under `-Osize`, the full 535-check self-test run as the proxy, two runs each, alternating:

| | Run 1 | Run 2 |
|---|---|---|
| `-O` | 26.5 s | 19.4 s |
| `-Osize` | 19.1 s | 17.0 s |

Not slower on either run, so the build now uses `-Osize` and strips local symbols. `FC_KEEP_SYMBOLS=1 ./build.sh` keeps them for a profiling build. The shipped binary is 5.6 MB, signed and verified, 535/535.

Left as it is, on purpose:

- The verification code (24,771 lines, 40 % of the source) is compiled into the app so `--selftest`, `--snapshot` and the fixture app work from the one binary. Cutting it out would make the binary smaller still and remove a documented feature; not done.
- The app icon is 1.7 MB of the 7.4 MB bundle.

## 4. What a further pass would do, and why it was not done now

1. **Split the ticking values into their own `ObservableObject`.** The store publishes once a second while a session runs and every observer of it re-evaluates; the clock, the goal ring and the running card are the only views that need the second. This is the remaining 3–5 % with the window open. It touches the store's observers across the surfaces (131 observers), so it is a deliberate refactor with its own checks, not a cleanup.
1. **Retire `.contentTransition(.numericText())` on anything that changes often.** The remaining uses (finished totals, the calendar, the ring's percentage) change rarely; if a later macOS still keeps glyphs, they go too.
2. **`PowerObservation` copies in the rail.** Under 0.2 %; not worth its diff.
3. **Launch.** The archive (1.3 MB) and session metadata (0.6 MB) are decoded at launch in well under a second on this data. Nothing to do until the archive is ten times larger.

## How to repeat

```bash
P=$(pgrep -x FocusContinuity); top -l 9 -s 2 -pid $P -stats pid,cpu,idlew,mem
sample $P 8 -file /tmp/fc.sample.txt        # needs FC_KEEP_SYMBOLS=1 build for names
leaks $P | tail -3
/usr/bin/time -l ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest
```
