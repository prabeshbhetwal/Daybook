# Haptic Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Daybook pulses the Force Touch trackpad and an MX Master 4 mouse with its notices and a few of the user's own actions, behind one off-by-default setting.

**Architecture:** Pure moment-to-pulse rules and HID++ byte handling live in Core (`Haptics.swift`). The App layer (`HapticPlayer.swift`) owns the devices: AppKit for the trackpad, an IOKit `IOHIDManager` link for the mouse. `AppCoordinator` creates one player and hands it to `SettingsModel`, `AwayPrompter` and, through an environment value, the Story rail.

**Tech Stack:** Swift 5 mode, AppKit (`NSHapticFeedbackManager`), IOKit HID, SwiftUI; no new dependencies.

**Spec:** `docs/specs/2026-10-10-haptic-feedback-design.md`

## Global Constraints

- Core stays UI-free: `Sources/Core/Haptics.swift` imports only Foundation. `build.sh` typechecks Core alone.
- No new dependency, no network, no Logitech software at runtime.
- Never write the mouse's settings: no HID++ function 2 (`set_configuration`) anywhere.
- Mouse match: vendor `0x046D`, product `0xB042`, opened without seize (`kIOHIDOptionsTypeNone`).
- HID++ long report: `[0x11, 0xFF, feature, function << 4 | softwareID, parameters…]`, 20 bytes, report ID byte included in the `IOHIDDeviceSetReport` buffer.
- Waveforms: damp state change 1, subtle collision 4, happy alert 5, completed 7.
- Setting key `fc.hapticsEnabled`, missing reads `false`.
- Checks use `MemoryDefaults`, never `UserDefaults(suiteName:)`; new suite appended at the very end of `registeredTests`.
- Lengths in App/Design/Surfaces are tokens or `.zoomed` (none should be needed here).
- `-warnings-as-errors`: the build fails on any warning, including actor-isolation warnings.
- Commit subjects: one plain present-tense sentence of what is now true for the user; body is wrapped prose; end with the Co-Authored-By line.
- Repository is public: no machine paths or personal data in commits.

## Review Focus

1. Mouse movement must not wake Daybook: the input-report callback exists only during a discovery exchange (Task 4, hand step).
2. Mouse reconnect (sleep, Easy-Switch to another host and back): the link forgets the device and feature index on removal and rediscovers on the next play, never crashes on a stale device (Task 4, hand step; Task 3 check for close-then-play).
3. Discovery waits up to 1.5 s for replies: it must never run on the main thread (Task 4 constraint; Task 5 Try is `async`).
4. Turning the switch off while discovery is in flight: open, close, discovery and play are serialised on one queue (Task 4).
5. Launch with the switch on and no mouse: no prompt, no error, trackpad still pulses (Task 3 check).

## Commands

- Typecheck, works in the sandbox (about 100 s): the `swiftc -typecheck …` line from `CLAUDE.md`. This worktree has no `.build/vendor`; point `-F` at the main checkout's `.build/vendor/Sparkle-2.10.0`, or run Task 1's first `./build.sh --check` to fetch it.
- Full suite: `./build.sh --check` with the sandbox disabled. Pass means every check passes and the summary count is the previous total plus this plan's new checks.

---

### Task 1: Core haptics rules and HID++ bytes

**Files:**
- Create: `Sources/Core/Haptics.swift`
- Create: `Sources/Verification/HapticsChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (append `+ HapticsChecks.tests` after `+ HistoryCurrentPeriodChecks.tests`, as the last line of the chain)

**Interfaces:**
- Consumes: `RewardKind` (`Sources/Core/RewardEngine.swift`).
- Produces:
  - `enum TrackpadPattern: Equatable { case generic, levelChange, alignment }`
  - `enum MouseWaveform { static let dampStateChange: UInt8 = 1; static let subtleCollision: UInt8 = 4; static let happyAlert: UInt8 = 5; static let completed: UInt8 = 7 }`
  - `enum HapticMoment: CaseIterable, Equatable { case breakDue, awayQuestion, goalReached, notice, sessionToggled, zoomStep, tileDropped }` with `init(reward: RewardKind)`, `var mouseWaveform: UInt8`, `var trackpadPattern: TrackpadPattern`
  - `enum HIDPP` with `static let longReportID: UInt8 = 0x11`, `static let directDevice: UInt8 = 0xFF`, `static let reportLength = 20`, `static let hapticFeature: (UInt8, UInt8) = (0x19, 0xB0)`, `static func request(feature: UInt8, function: UInt8, softwareID: UInt8, parameters: [UInt8] = []) -> [UInt8]`, `enum Reply: Equatable { case answer([UInt8]), error(UInt8), unrelated }`, `static func reply(_ report: [UInt8], to request: [UInt8]) -> Reply`
  - `struct HapticConfiguration: Equatable { let isEnabled: Bool; let intensity: UInt8; init?(payload: [UInt8]) }`
  - `struct HapticCapabilities: Equatable { let waveformMask: UInt32; init?(payload: [UInt8]); func supports(_ waveform: UInt8) -> Bool }`
  - `enum MouseHaptics { static func playable(configuration: HapticConfiguration, capabilities: HapticCapabilities, waveform: UInt8) -> Bool }`

- [ ] **Step 1: Write the failing checks** in `HapticsChecks.swift` (`enum HapticsChecks: CheckSuite`), five entries:

```swift
("HID++ requests are 20-byte long reports addressed to the mouse", requestBytes)
// request(feature: 0, function: 0, softwareID: 0x0B, parameters: [0x19, 0xB0, 0])
//   == [0x11, 0xFF, 0x00, 0x0B, 0x19, 0xB0, 0x00] + 13 zeros
// request(feature: 0x0B, function: 4, softwareID: 0x0B, parameters: [7, 0, 0])[2...3] == [0x0B, 0x4B]
// every request's count == 20

("HID++ replies are matched to their request and errors are told apart", replyMatching)
// req = request(feature: 0x0B, function: 1, softwareID: 0x0B)
// [0x11,0xFF,0x0B,0x1B,3,25] + padding        → .answer(payload from byte 4: [3,25,…])
// [0x11,0xFF,0x8F,0x0B,0x1B,0x05] + padding   → .error(0x05)
// [0x11,0xFF,0xFF,0x0B,0x1B,0x02] + padding   → .error(0x02)
// same feature, softwareID 0x0C ([…,0x0B,0x1C,…]) → .unrelated
// mouse movement report [0x02, 0x00, 0x05, 0x00, 0xFE, 0xFF, 0x00] → .unrelated
// short report [0x11, 0xFF, 0x0B]             → .unrelated

("The mouse's haptic switch is one bit of its configuration byte", configurationBit)
// HapticConfiguration(payload: [3, 25])!: isEnabled true, intensity 25
// HapticConfiguration(payload: [2, 25])!: isEnabled false
// HapticConfiguration(payload: [1, 0])!: playable(...) false for any supported waveform
// HapticConfiguration(payload: [3]) == nil

("The waveform mask says which pulses the mouse offers", capabilityMask)
// caps = HapticCapabilities(payload: [0, 0, 0, 0, 0x08, 0x00, 0x7F, 0xFF])!
// caps.waveformMask == 0x08007FFF; supports(0...14) all true; supports(15) false; supports(40) false
// HapticCapabilities(payload: [0, 0, 0]) == nil
// playable(configuration: [3,25], capabilities: caps, waveform: 7) true; waveform 15 false

("Each moment has its pulse, and the goal reward gets its own", momentTable)
// breakDue, awayQuestion → 5, .generic; goalReached → 7, .generic;
// notice, sessionToggled → 1, .generic; zoomStep → 4, .levelChange; tileDropped → 4, .alignment
// HapticMoment(reward: .goalReached) == .goalReached; every other RewardKind.allCases → .notice
```

- [ ] **Step 2: Register the suite and run the typecheck.** Expected: FAIL, the Core types are undefined.

- [ ] **Step 3: Implement `Sources/Core/Haptics.swift`** to the Interfaces above. `reply(_:to:)`: needs `report.count >= 7` and byte 0 in `[0x10, 0x11]` and byte 1 `0xFF`; error when byte 2 is `0x8F` or `0xFF` and bytes 3–4 equal the request's bytes 2–3 (code = byte 5); answer when bytes 2–3 equal the request's bytes 2–3 (payload = `Array(report[4...])`); otherwise unrelated. `isEnabled` = `payload[0] & 1 == 1`. Mask = bytes 4–7 big-endian. `supports` is false for `waveform >= 32`. `playable` = enabled, intensity > 0, and supported. A doc comment on `isEnabled` cites the tested mouse reporting `3`.

- [ ] **Step 4: Run `./build.sh --check`.** Expected: all pass, five new.

- [ ] **Step 5: Mutation test.** In a scratch copy (`CLAUDE.md`, Runtime probes), change `isEnabled` to `payload[0] == 1` and run `./build.sh --check` there. Expected: "The mouse's haptic switch is one bit…" fails. Remove the copy.

- [ ] **Step 6: Commit.** Subject: "Daybook knows which pulse each moment plays and how to speak to the MX Master 4's haptics".

---

### Task 2: The setting

**Files:**
- Modify: `Sources/Core/PersistenceStore.swift` (Key `hapticsEnabled = "fc.hapticsEnabled"`, property beside `rewardsEnabled`, key list in `removeAll()` near line 777)
- Modify: `Sources/App/SettingsModel.swift` (`SettingsControlKey.haptics` → `\SettingsModel.hapticsEnabled`; `hapticsEnabled` beside `rewardsEnabled`)
- Modify: `Sources/Surfaces/Settings/SettingsSidebar.swift` (`.automatic` search terms gain `"Haptic feedback"`; `.automatic` controls gain `.haptics`)
- Test: `Sources/Verification/HapticsChecks.swift`

**Interfaces:**
- Produces: `PersistenceStore.hapticsEnabled: Bool` (missing → `false`); `SettingsModel.hapticsEnabled: Bool` (writes through `write { }`); `SettingsControlKey.haptics`.

- [ ] **Step 1: Write the failing check** `("Haptic feedback is off until turned on, and the switch is saved", settingWritesThrough)`: over `MemoryDefaults.suite(named: "fc-selftest-haptics-\(UUID().uuidString)")`, a fresh store reads `hapticsEnabled == false`; a `SettingsModel` (constructed as in `EditorAndReportChecks.settingsModels()`, inside `MainActor.assumeIsolated`) set to `true` makes `store.hapticsEnabled == true` with exactly one `onChange`; `store.removeAll()` brings it back to `false`; `SettingsControlKey.haptics.modelKeyPath == \SettingsModel.hapticsEnabled`. Remove the suite at the end.

- [ ] **Step 2: Run the typecheck.** Expected: FAIL, `hapticsEnabled` undefined.

- [ ] **Step 3: Implement** the three file changes. The existing settings-surface checks require every `SettingsControlKey` to appear in a section, which the sidebar change satisfies.

- [ ] **Step 4: Run `./build.sh --check`.** Expected: all pass, one new.

- [ ] **Step 5: Commit.** Subject: "Settings remembers whether haptic feedback is on, off by default".

---

### Task 3: The player

**Files:**
- Create: `Sources/App/HapticPlayer.swift`
- Modify: `Sources/App/SettingsModel.swift` (init parameter `haptics: HapticPlayer? = nil`; `hapticsEnabled` setter also calls `haptics?.setEnabled(newValue)`; `func playHaptic(_ moment: HapticMoment)`; `func tryHaptics() async -> MouseLinkStatus?`)
- Test: `Sources/Verification/HapticsChecks.swift`

**Interfaces:**
- Consumes: Task 1 types; `PersistenceStore.hapticsEnabled` (through the `isEnabled` closure).
- Produces:
  - `enum MouseLinkStatus: Equatable { case closed, ready, noMouse, hapticsOff, notPermitted, noReply }` with `var tryMessage: String` (copy in Task 5)
  - `protocol MouseHapticLink: AnyObject { func open(); func close(); func play(_ waveform: UInt8); func rediscover(completion: @escaping (MouseLinkStatus) -> Void) }`
  - `final class HapticPlayer { init(isEnabled: @escaping () -> Bool, mouse: MouseHapticLink, trackpad: @escaping (TrackpadPattern) -> Void = HapticPlayer.performOnTrackpad); func setEnabled(_ on: Bool); func play(_ moment: HapticMoment); func tryPulse() async -> MouseLinkStatus; static func performOnTrackpad(_ pattern: TrackpadPattern) }`
  - `EnvironmentValues.haptics: (HapticMoment) -> Void`, default `{ _ in }` (key in this file)

- [ ] **Step 1: Write the failing check** `("The player stays silent while off and sends one pulse per moment while on", playerGating)` with a `FakeMouseLink` (records `open`/`close` counts and played waveforms; `rediscover` answers a set status) and a trackpad closure that records patterns:
  - `isEnabled` false: `play(.goalReached)` records nothing on either device.
  - `isEnabled` true: `play(.goalReached)` records `[.generic]` and `[7]`; `play(.zoomStep)` adds `.levelChange` and `4`.
  - `setEnabled(true)` calls `open()` once; `setEnabled(false)` calls `close()` once, and a `play` after it with `isEnabled` false records nothing.
  - Fake answering `.noMouse`: `await tryPulse()` returns `.noMouse` and the trackpad still records `.generic` (Review Focus 5). Run the async part with a `Task` and a run-loop wait, or a blocking `DispatchSemaphore` off the main thread.

- [ ] **Step 2: Run the typecheck.** Expected: FAIL, `HapticPlayer` undefined.

- [ ] **Step 3: Implement `HapticPlayer.swift`.** `play` returns at once when `isEnabled()` is false, else calls `trackpad(moment.trackpadPattern)` and `mouse.play(moment.mouseWaveform)`. `tryPulse` plays `.goalReached` on the trackpad and resolves `mouse.rediscover`, playing `MouseWaveform.completed` when the status is `.ready`. `performOnTrackpad` maps `TrackpadPattern` to `NSHapticFeedbackManager.FeedbackPattern` and calls `defaultPerformer.perform(_, performanceTime: .now)` on the main thread, wrapping in `MainActor.assumeIsolated` (or `DispatchQueue.main.async` off main) so the build stays warning-free. The player is not actor-isolated: `AppCoordinator.settings` builds it from a non-isolated lazy property. Production callers construct it with `mouse: MXMaster4Link()` from Task 4; until then the check is the only user.

- [ ] **Step 4: Run `./build.sh --check`.** Expected: all pass, one new.

- [ ] **Step 5: Commit.** Subject: "Haptic pulses go to the trackpad and the mouse only while the setting is on".

---

### Task 4: The MX Master 4 link

**Files:**
- Create: `Sources/App/MXMaster4Link.swift`

**Interfaces:**
- Consumes: `HIDPP`, `HapticConfiguration`, `HapticCapabilities`, `MouseHaptics.playable` (Task 1); `MouseHapticLink`, `MouseLinkStatus` (Task 3).
- Produces: `final class MXMaster4Link: MouseHapticLink` with `init()`.

- [ ] **Step 1: Implement.** Requirements, each one line in the code's doc comments:
  - One private serial `work` queue: `open`, `close`, `play`, `rediscover` all `async` onto it, so a switch-off during discovery waits its turn (Review Focus 4). A second private `callbacks` queue is given to `IOHIDManagerSetDispatchQueue`. `IOHIDManagerActivate` is called after it and before open. Discovery blocks `work`, never `callbacks` and never main (Review Focus 3).
  - `open()`: create the manager if needed, match `[kIOHIDVendorIDKey: 0x046D, kIOHIDProductIDKey: 0xB042]`, register matching and removal callbacks, and open with `kIOHIDOptionsTypeNone`. `kIOReturnNotPermitted` sets `.notPermitted`. No device sets `.noMouse`.
  - Removal callback: drop the device, feature index, configuration and capabilities, and set `.noMouse` (Review Focus 2). Matching callback: remember the device, status `.closed` until discovered.
  - Discovery on `work`: register the input-report callback with a 64-byte buffer and send getFeature (`HIDPP.request(feature: 0, function: 0, softwareID: 0x0B, parameters: [0x19, 0xB0, 0])`). Wait for `HIDPP.reply` = `.answer` (1.5 s per request, using a semaphore signalled from `callbacks`), then read capabilities (function 0) and configuration (function 1). **Always unregister the input-report callback when discovery ends**, on success and failure (Review Focus 1). Feature index 0 or a missing answer sets `.noMouse` or `.noReply`; a configuration that is off or has intensity 0 sets `.hapticsOff`; otherwise `.ready`.
  - `play(_:)` on `work`: open first if the manager is nil (first play after a launch with the switch on), discover if not `.ready`, then send `HIDPP.request(feature: index, function: 4, softwareID: 0x0B, parameters: [waveform, 0, 0])` only when `MouseHaptics.playable` holds. Don't wait for a reply.
  - `rediscover(completion:)`: run discovery even if `.ready` (fresh configuration for Try), then call `completion` on main with the status.
  - `close()`: close and release the manager, status `.closed`.
  - A `ponytail:` comment on keeping the manager open while the switch is on: if the idle hand check shows wakeups from movement, switch to opening per play.

- [ ] **Step 2: Typecheck and run `./build.sh --check`.** Expected: all pass, no new checks. The link needs hardware; Task 6 proves it by hand.

- [ ] **Step 3: Commit.** Subject: "Daybook can pulse an MX Master 4 over Bluetooth without Logitech software".

---

### Task 5: Settings row and Try

**Files:**
- Modify: `Sources/App/AppCoordinator.swift` (`private(set) lazy var haptics = HapticPlayer(isEnabled: { [weak self] in self?.engine.store.hapticsEnabled ?? false }, mouse: MXMaster4Link())`; pass `haptics: haptics` to the `settings` initialiser)
- Modify: `Sources/App/HapticPlayer.swift` (`MouseLinkStatus.tryMessage`)
- Modify: `Sources/Surfaces/Settings/SettingsGroups.swift` (after "Celebrate milestones" in the `.automatic` panel: `rowDivider`, the toggle, the Try row)
- Modify: `Sources/Surfaces/Settings/SettingsSidebar.swift` (`.automatic` search terms gain `"Try"`)

**Interfaces:**
- Consumes: `SettingsModel.hapticsEnabled`, `SettingsModel.tryHaptics()` (Tasks 2–3), `MXMaster4Link` (Task 4).

- [ ] **Step 1: Write the failing check** `("Try explains what it reached in words", tryMessages)`: `.ready`, `.noMouse`, `.hapticsOff`, `.notPermitted` and `.noReply` each give the exact strings below; `.closed` gives the same text as `.noMouse`.

| Status | `tryMessage` |
|---|---|
| `.ready` | `Sent to the MX Master 4 and the trackpad.` |
| `.noMouse`, `.closed` | `No MX Master 4 connected over Bluetooth. Sent to the trackpad: rest a finger on it to feel the pulse.` |
| `.hapticsOff` | `The MX Master 4 has haptics turned off. Turn them on in Logi Options+.` |
| `.notPermitted` | `macOS blocked access to the mouse. Allow Daybook in System Settings › Privacy & Security › Input Monitoring.` |
| `.noReply` | `The MX Master 4 did not answer. Move it to wake it, then try again.` |

`.noReply` is an addition to the spec's §5 table. The mouse can be asleep, and none of the four spec lines would be true then.

- [ ] **Step 2: Run the typecheck.** Expected: FAIL, `tryMessage` undefined.

- [ ] **Step 3: Implement.**
  - `toggleRow("Haptic feedback", detail: "A short pulse on the trackpad or an MX Master 4 mouse with Daybook's notices and a few of your own actions. The trackpad pulses only while a finger rests on it.", isOn: $model.hapticsEnabled)`.
  - `preferenceRow("Try", detail: <last tryMessage or "Plays the goal pulse.">) { Button("Try") { … } .disabled(!model.hapticsEnabled) }`.
  - The button runs `Task { result = await model.tryHaptics() }`, keeping the result in the view's `@State`.

- [ ] **Step 4: Run `./build.sh --check`.** Expected: all pass, one new. Existing settings snapshot or search checks may need the new row's terms; update their expectations only where they list the panel's rows.

- [ ] **Step 5: Commit.** Subject: "Settings can turn on haptic feedback and try it on the trackpad and mouse".

---

### Task 6: Hooks

**Files:**
- Modify: `Sources/App/AppCoordinator.swift`
  - `onBreakDue`: `haptics.play(.breakDue)` inside the `Task { @MainActor in … }` beside `hud.show`, after `guard reachesScreen`
  - `evaluateRewards`: `haptics.play(HapticMoment(reward: reward.kind))` after `hud.show`
  - `applyActivityRuleResult`, `apply(_ decision:)`: `haptics.play(.notice)` beside each `hud.show`
  - `toggleSessionFromHotKey`: play `.sessionToggled` for `.started`, `.stopped`, `.stoppedPendingFinalisation`
  - the `awayPrompter` initialiser: `playHaptic: { [weak self] in self?.haptics.play($0) }`
- Modify: `Sources/App/AwayPrompter.swift` (init parameter `playHaptic: @escaping (HapticMoment) -> Void = { _ in }`; call `playHaptic(.awayQuestion)` in `start()`'s sink right after `self.present(away:)`. Not in `presentPendingDecision()` or `preview(_:)`)
- Modify: `Sources/Surfaces/Settings/ZoomControl.swift` (`.onChange(of: draft)`: `if isDragging { model.playHaptic(.zoomStep) }`)
- Modify: `Sources/Surfaces/Story/StoryRail.swift` (`@Environment(\.haptics) private var haptics`; the `TileDropDelegate` `move:` closure becomes `{ moved, before in move(moved, before: before); haptics(.tileDropped) }`)
- Modify: `Sources/Surfaces/Main/MainWindowView.swift` (`.environment(\.haptics) { settings.playHaptic($0) }` beside `.environment(\.openSessionReport)` on the window root)

**Interfaces:**
- Consumes: `HapticPlayer.play`, `HapticMoment(reward:)`, `SettingsModel.playHaptic`, `EnvironmentValues.haptics`.

- [ ] **Step 1: Implement the hooks above.** No new checks: each hook is one call placed inside a branch that existing checks already cover (`testBreakReminderUsesOneChannel` for the break channels). The gallery, snapshots and fixtures inject nothing, so `\.haptics` stays a no-op there.

- [ ] **Step 2: Run `./build.sh --check`.** Expected: all pass, total unchanged from Task 5.

- [ ] **Step 3: Commit.** Subject: "Breaks, the daily goal, other notices and a few of your own actions now pulse when haptic feedback is on".

---

### Task 7: Hand checks and record

**Files:**
- Modify: `docs/specs/2026-10-10-haptic-feedback-design.md` (§8 Input Monitoring answer and idle-CPU result, under a dated "Hand checks" note)

- [ ] **Step 1:** The person installs the build, from Finder or with `./build.sh --test`, never from a sandboxed shell. They turn the switch on and record whether macOS asks for Input Monitoring.
- [ ] **Step 2:** Try with a finger resting on the trackpad and a hand on the mouse. Expected: "Sent to the MX Master 4 and the trackpad." and both pulses felt.
- [ ] **Step 3:** With the switch on, move the mouse continuously for 60 s while watching Daybook in Activity Monitor (or `top -pid`). Expected: CPU at its idle level. If not, apply Task 4's `ponytail:` fallback and repeat.
- [ ] **Step 4:** Easy-Switch the mouse to another channel and back, then Try. Expected: pulse felt, no crash. Then change a button or the haptic strength in Logi Options+ with Daybook running. Expected: Logi Options+ still applies it.
- [ ] **Step 5:** Drag the zoom slider across its steps; reorder a Story tile; press the global start/stop shortcut twice. Expected: a pulse for each step, the drop, and each toggle.
- [ ] **Step 6:** Record the results in spec §8 and commit. Subject: "The haptic feedback spec records its hand checks". Then ship through the `ship` skill when the person says so.
