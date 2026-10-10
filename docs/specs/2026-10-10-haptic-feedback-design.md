# Haptic feedback

Date: 2026-10-10
Status: approved in conversation 2026-10-10; spec awaiting review

## Why

Daybook tells you things on screen: a break is due, the daily goal is met, a
streak continues, an automatic session started. When you are deep in another
app you can miss the corner notice. A short pulse in the hand you are already
using reaches you without taking your eyes off the work.

Goal: one setting that adds a haptic pulse to Daybook's notices and to a few
of your own actions, on the Force Touch trackpad and on a Logitech MX Master 4
mouse, with nothing to install.

## Decisions

| Question | Decision |
|---|---|
| Devices | The Force Touch trackpad (built-in or Magic Trackpad) and the MX Master 4 over Bluetooth. Both are sent every pulse; whichever has your hand on it is felt. |
| Mouse route | Daybook speaks HID++ 2.0 to the mouse itself through IOKit (`IOHIDManager`), feature `0x19B0`. Proven on 2026-10-10 (§9). |
| Rejected: Logi Actions SDK plugin | A second codebase in C#/.NET, shipped through the Logi Marketplace and run inside Logi Options+. |
| Rejected: HapticWebPlugin | A third-party plugin reached over HTTPS through someone else's domain (`local.jmw.nz`), and it accepts requests from any website. |
| Trackpad route | `NSHapticFeedbackManager.defaultPerformer`. Felt only while a finger rests on the pad (Apple's documented behaviour, confirmed in §9). |
| Moments | Notices (break due, away question, daily goal, other rewards, automatic session started) and your own actions (global start/stop hotkey, zoom slider steps, Story tile drop). |
| Setting | One switch, "Haptic feedback", off by default, with a Try button. |
| Mouse settings | Never written. Daybook reads the mouse's enable bit, strength and waveform list; Logi Options+ stays the owner of strength and on/off. |
| Pulse follows the notice | A pulse plays only with something you can see. No notice on screen (screen locked, display asleep, away, "Celebrate milestones" off), no pulse. |

## 1. Moments and pulses

`HapticMoment` (Core) names each moment and says what it plays. Waveform ids are
Solaar's (`HapticWaveForms`); every one used here was played and felt in §9 or
is OpenLogi's confirmed id.

| Moment | Hook | Mouse waveform | Trackpad pattern |
|---|---|---|---|
| `breakDue` | `store.onBreakDue`, HUD branch only (`AppCoordinator`) | happy alert (5) | generic |
| `awayQuestion` | `AwayPrompter.start()` subscription, when it presents a new question | happy alert (5) | generic |
| `goalReached` | `evaluateRewards`, reward kind `.goalReached` | completed (7) | generic |
| `notice` | `evaluateRewards` other kinds; `applyActivityRuleResult`; `apply(_ decision:)` automatic start | damp state change (1) | generic |
| `sessionToggled` | `toggleSessionFromHotKey`, only when a session started or stopped | damp state change (1) | generic |
| `zoomStep` | `ZoomControl` slider, each step the draft passes while dragging | subtle collision (4) | level change |
| `tileDropped` | `TileDropDelegate.performDrop`, when the move happens | subtle collision (4) | alignment |

The rule behind the table: asking for you, happy alert; good news, completed;
for your information or confirming an action, damp state change; a small step
under your hand, subtle collision.

- `HapticMoment(reward:)` maps a `RewardKind`: `.goalReached` to `goalReached`,
  every other kind to `notice`.
- No pulse for: `presentPendingDecision()` (you asked for the question with
  the hotkey, so `sessionToggled` does not fire either), the `--preview-away`
  previews, gallery and snapshot runs, and the notification branch of
  `onBreakDue`.

## 2. Core: `Sources/Core/Haptics.swift`

Pure, UI-free, testable without a mouse.

- `HapticMoment` (above), with `mouseWaveform: UInt8` and
  `trackpadPattern: TrackpadPattern` (`generic`, `levelChange`, `alignment`;
  Core cannot name the AppKit type).
- `HIDPP` byte layout for the long report: `request(feature:function:softwareID:parameters:)`
  returns 20 bytes `[0x11, 0xFF, feature, function << 4 | softwareID, parameters…]`,
  zero-padded; `reply(_:to:)` classifies an input report as the matching
  answer (payload from byte 4), a HID++ error (`0x8F` or `0xFF` at byte 2 with
  the same feature and function byte; code at byte 5), or unrelated.
- `HapticConfiguration(payload:)`: `isEnabled` is bit 0 of byte 0, `intensity`
  is byte 1. The byte is a bit field: the tested mouse reports `3`.
- `HapticCapabilities(payload:)`: the waveform mask is bytes 4–7, big-endian;
  `supports(_ waveform:)` tests bit `waveform`.
- `MouseHaptics.playable(configuration:capabilities:waveform:)`: true only when
  enabled, intensity above zero and the waveform is in the mask.

## 3. App: `Sources/App/HapticPlayer.swift`

One instance, created by `AppCoordinator`, given `isEnabled: () -> Bool`
(reads `PersistenceStore.hapticsEnabled`).

- `play(_ moment: HapticMoment)`: does nothing when disabled. Otherwise it
  performs the trackpad pattern on the main thread and hands the mouse
  waveform to the mouse queue. It never blocks the main thread.
- Mouse: an `IOHIDManager` matching vendor `0x046D`, product `0xB042`, opened
  without seizing the device (Logi Options+ keeps working), scheduled on a
  private serial dispatch queue. On first use, and again when the mouse
  reconnects, it asks the root feature for `0x19B0`'s index, then reads
  capabilities and configuration. A play is one output report with no wait
  for the reply.
- The mouse is opened when the setting turns on, or on the first play after
  launch with it on, and closed when the setting turns off. Any macOS
  permission prompt therefore appears when you flip the switch, never at
  launch.
- Idle cost stays zero. The input-report callback is registered only for a
  discovery exchange and removed after it; mouse movement must not wake
  Daybook (§8).
- Every failure is silent to the notice path: no mouse, haptics off in Logi
  Options+, waveform not in the mask, macOS refusing access. The last reason is
  kept for the Try button.
- `tryPulse() async -> HapticTryResult`: plays `goalReached` and reports what
  was reached, for the Settings line under the button.
- To SwiftUI it is an environment value, `\.haptics`, a closure taking a
  `HapticMoment`. The default is a no-op, so fixtures, the gallery and
  snapshots stay silent.

## 4. The setting

- `PersistenceStore.hapticsEnabled: Bool` under `fc.hapticsEnabled`; missing
  reads as `false`. Added to the key list that `removeAll()` clears.
- `SettingsModel.hapticsEnabled` writes through like `rewardsEnabled`, and
  tells the player to open or close the mouse.
- `SettingsControlKey.haptics` maps to `\SettingsModel.hapticsEnabled` so
  Settings search finds it.
- In the Settings panel that holds "Celebrate milestones" (titled "Automatic
  sessions" today, `SettingsGroups.swift`), the row after it:
  - toggle "Haptic feedback", detail: "A short pulse on the trackpad or an MX
    Master 4 mouse with Daybook's notices and a few of your own actions. The
    trackpad pulses only while a finger rests on it."
  - a Try button, enabled while the switch is on, and one line under it with
    the result.

## 5. Try results

| Result | Line shown |
|---|---|
| Mouse reached | "Sent to the MX Master 4 and the trackpad." |
| No mouse | "No MX Master 4 connected over Bluetooth. Sent to the trackpad: rest a finger on it to feel the pulse." |
| Haptics off on the mouse | "The MX Master 4 has haptics turned off. Turn them on in Logi Options+." |
| Access refused | "macOS blocked access to the mouse. Allow Daybook in System Settings › Privacy & Security › Input Monitoring." |

## 6. Hooks

All in App except the two SwiftUI ones, which read `\.haptics`.

- `AppCoordinator.onBreakDue`: `player.play(.breakDue)` beside `hud.show`,
  after the `guard reachesScreen` that sends the other cases to a
  notification, so a locked, asleep or away Mac gets no pulse.
- `AppCoordinator.evaluateRewards`: `player.play(HapticMoment(reward: reward.kind))`
  beside `hud.show`. Rewards keep their limits (four a day, 45-minute
  cooldown), so pulses do too.
- `AppCoordinator.applyActivityRuleResult` and `apply(_ decision:)`:
  `player.play(.notice)` beside each `hud.show`.
- `AppCoordinator.toggleSessionFromHotKey`: `player.play(.sessionToggled)`
  when `performSessionHotKeyAction()` returns `.started`, `.stopped` or
  `.stoppedPendingFinalisation`; not for `.saveFailed` or
  `.showAwayDecision`.
- `AwayPrompter`: takes the player; plays `.awayQuestion` in the `start()`
  subscription when it presents, not in `presentPendingDecision()` or
  `preview(_:)`.
- `ZoomControl`: plays `.zoomStep` when the dragged draft lands on a new step.
- `TileDropDelegate.performDrop`: plays `.tileDropped` when it moves a tile.

## 7. Out of scope

- Logi Bolt receiver (another product id and device index addressing).
- Other Logitech haptic devices and game controllers.
- Choosing waveforms or strength in Daybook.
- Pulses for confirmation dialogs.
- Announcing Awards, which are computed but never announced today.

## 8. Checks

New suites at the end of `registeredTests`. All use `MemoryDefaults` and no
hardware.

1. `HIDPP.request` bytes for getFeature(`0x19B0`), capabilities, configuration
   and play: report id, device index, function byte, padding to 20.
2. `HIDPP.reply`: matching answer, HID++ error (`0x8F` and `0xFF`), another
   client's software id, a mouse-movement report, a short report: each
   classified correctly.
3. `HapticConfiguration`: byte `3` with intensity 25 is enabled; `2` is off;
   intensity 0 is not playable.
4. `HapticCapabilities` on mask `0x08007FFF`: supports 0–14, not 15.
5. `HapticMoment` table and `HapticMoment(reward:)` for every `RewardKind`.
6. Setting: missing reads `false`; writes through once with one `onChange`;
   `removeAll()` clears it; `SettingsControlKey.haptics` reaches it.
7. Player gating with a fake mouse and trackpad sink: disabled plays nothing;
   enabled sends one trackpad pattern and one waveform per moment; a mouse
   whose configuration or mask refuses the waveform gets no report.

Mutation test: put back `byte0 == 1` for `isEnabled` and confirm check 3 fails.

Hand checks before shipping:

- Try with the switch on: pulse felt in the MX Master 4 and, finger resting, on
  the trackpad.
- First switch-on in the real Daybook bundle: does macOS ask for Input
  Monitoring? Record the answer here. Theory: no, because the mouse exposes
  no keyboard collection (§9).
- With the switch on, move the mouse for a minute: Daybook's CPU stays at its
  idle level (no wakeups from movement reports).
- Logi Options+ still applies its own button and haptic settings while
  Daybook is running.
- Added after the review: Easy-Switch the mouse away and back, then press the
  start/stop shortcut (not Try, which always looks the mouse up afresh): the
  pulse is felt. And with haptics turned off in Logi Options+, a notice does
  not pulse the mouse.

## Implementation note (2026-10-10, during the build)

§3 described one `IOHIDManager` with matching and removal callbacks. That
traps: a device owned by a manager on a dispatch queue is activated with it,
and registering its input-report callback afterwards fails with "Device has
already been activated/cancelled". The built link has no manager. Each
discovery creates a listening device object from the mouse's IOKit service
and cancels it when the three answers are in; plays go through a second
device object that never listens. There are no removal callbacks: a failed
play looks the mouse up again and sends once more (check 701), and a failed
discovery makes later pulses wait 10 s before looking again. A probe of the
built link against the mouse: ready in 0.33 s, three pulses felt, and 10 s
of continuous mouse movement afterwards cost 0.0004 s of CPU.

## 9. Evidence (probes, 2026-10-10, macOS 27, MacBook built-in trackpad, MX Master 4 over Bluetooth LE)

- Trackpad: an accessory-policy process, not frontmost (`probeActive=false`,
  System Settings in front), performed `generic`, `levelChange` and
  `alignment`, three each. All felt with a finger resting on the pad.
- Mouse: `IOHIDManagerOpen` without seize returned `0x0`; one device
  (`MX Master 4`, primary usage page 1). Root getFeature(`0x19B0`) returned
  index `0x0B`; waveform mask `0x8007FFF`; configuration `enabled=3
  intensity=25`. Plays of completed (7), happy alert (5) and damp state change
  (1) were each acknowledged and each felt. Logi Options+ was installed and
  running.
- `DeviceUsagePairs` for the mouse: (1, 2) mouse, (1, 1) pointer,
  (0xFF43, 0x0202) HID++. No keyboard usage.
- The probe ran under a process that already had Input Monitoring, so §8's
  hand check settles whether Daybook needs it.
- The probe's first run refused to play because it tested `enabled == 1`, as
  the reference implementation `herdr-haptic-alert` does; the mouse reports
  `3`. Hence bit 0 in §2.

References: [NSHapticFeedbackPerformer.perform](https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer/perform(_:performancetime:)),
[OpenLogi 0x19b0](https://openlogi.org/hidpp/features/x19b0-haptic-feedback),
[Solaar hidpp20_constants](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20_constants.py),
[herdr-haptic-alert](https://github.com/lfsmoura/herdr-haptic-alert),
[Logi Actions SDK haptics](https://logitech.github.io/actions-sdk-docs/csharp/haptics/haptics-tutorial/).
