# FocusContinuity Implementation Plan

**Goal:** Build a native macOS menu bar utility that tracks one continuous work session and keeps it honest across screen locks, sleeps and app switches, distinguishing silent micro-breaks from extended breaks that require a user decision.

**Architecture:** A notification-driven state machine. `EventMonitor` converts `NSWorkspace` and `DistributedNotificationCenter` notifications into typed closures; `SessionEngine` is the single owner of state and time arithmetic, exposing one total `transition(on:)` method; `MenuBarController` renders the `NSStatusItem` and menu; `AlertPresenter` handles the two modal alerts. `AppDelegate` owns all four and wires them together with closures, never strong back-references. Nothing polls — the only repeating timer is cosmetic and refreshes the status title.

**Tech Stack:** Swift 5 language mode, AppKit/Cocoa/Foundation, `swiftc` via a hand-written `build.sh`, `UserDefaults` for persistence.

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the spec.

- **C1 Language/frameworks:** Pure Swift 5.9+, AppKit, Cocoa, Foundation only. No SwiftUI. No SPM. No third-party packages. No Xcode project.
- **C2 Build system:** A single `build.sh` at repo root using `swiftc` to emit `FocusContinuity.app` in the current directory.
- **C3 Idle cost:** 0.0% CPU and < 25 MB resident memory when the menu is closed and the session is paused.
- **C4 No state polling:** State transitions driven **only** by `NSWorkspace.shared.notificationCenter`, `DistributedNotificationCenter.default()` and `NSMenuDelegate`. No repeating timer may read or infer state (D3's cosmetic timer excepted).
- **C5 Concurrency:** All UI mutation on `DispatchQueue.main`. All observer closures capture `[weak self]`. No retain cycles. No `DispatchQueue.main.sync`.
- **C6 Completeness:** Zero stubs, zero placeholders, zero `TODO`, zero `fatalError("unimplemented")`. Every declared function has a working body.
- **C7 Persistence:** `UserDefaults` only. No files, no CoreData, no iCloud.
- **C8 Deployment target:** macOS 13.0+. Compile for the host architecture; no universal binary.
- **Entry point:** `Sources/main.swift` with an explicit bootstrap. No `@main` / `@NSApplicationMain` — they conflict with `main.swift`.
- **Bundle identifier:** `com.prabesh.focuscontinuity`.
- **File size:** One type per file, no file over ~300 lines.
- **Anti-patterns (automatic rejection):** repeating `Timer` that reads state; `NotificationCenter.default` for workspace notifications; strong `self` in observer closures; `TODO`/`FIXME`/stub bodies; `Thread.sleep`/busy-wait/`usleep`; requesting Accessibility or Automation permissions; force-unwrapping values derived from system APIs; presenting an alert off the main thread or while one is up; mutating `sessionStartDate` to fake elapsed time.
- **Version control:** This directory is **not** a git repository and the spec did not request one. The `Commit` step in each task is therefore recorded but skipped. Run `git init` first if you want the commit steps to execute.

---

## File Structure

| File | Responsibility |
|---|---|
| `build.sh` | Clean, compile, write `Info.plist`, ad-hoc sign; `--run` and `--test` flags |
| `README.md` | What it does, how to build/test, state machine behaviour |
| `Sources/main.swift` | `NSApplication` bootstrap, `--selftest` gate |
| `Sources/SessionState.swift` | `SessionState`, `PauseReason`, `AwayTrigger`, `AppCategory`, `SessionEvent`, `UserDecision`, `SessionRecord`, `PersistedState`, constants, diagnostics |
| `Sources/PersistenceStore.swift` | Codable `UserDefaults` wrapper, archive ring, preferences |
| `Sources/CategoryManager.swift` | Bundle ID → `AppCategory`, overrides, built-in map |
| `Sources/SessionEngine.swift` | State machine, time arithmetic, dwell guard, snapshot/restore |
| `Sources/EventMonitor.swift` | All system subscriptions, typed closures, teardown |
| `Sources/AlertPresenter.swift` | `NSAlert` construction, focus forcing, rename prompt |
| `Sources/MenuBarController.swift` | `NSStatusItem`, menu, `NSMenuDelegate`, title rendering, cosmetic timer |
| `Sources/AppDelegate.swift` | Lifecycle, ownership graph, wiring, teardown |
| `Sources/SelfTest.swift` | Ten headless logic tests with an injected clock |

Ownership: `AppDelegate` owns `SessionEngine`, `EventMonitor`, `MenuBarController`, `AlertPresenter`. `SessionEngine` owns `CategoryManager` and `PersistenceStore`. All upward references are `weak` or closures.

---

### Task 1: Model types and constants

**Files:**
- Create: `Sources/SessionState.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum AppCategory: String, Codable, CaseIterable { case work, breakTime, neutral }` with `var displayName: String` → `"Work"`, `"Break"`, `"Neutral"`.
  - `enum PauseReason: Equatable { case manual, distractionApp(bundleID: String), extendedBreak, systemSleep }` with `var displayName: String`.
  - `enum AwayTrigger: String, Codable, Equatable { case screenLock, systemSleep }`.
  - `enum SessionState: Equatable { case idle, running, paused(reason: PauseReason), awaitingUserDecision(away: TimeInterval, lastApp: String) }` with `isRunning`, `isPaused`, `displayName`.
  - `enum SessionEvent: Equatable { case launch, awayBegan(trigger: AwayTrigger), awayEnded, appActivated(bundleID: String?, name: String), dwellExpired(bundleID: String), manualPause, manualResume, decision(UserDecision), resetSession, overrideApplied(bundleID: String) }`.
  - `enum UserDecision: String, Equatable, CaseIterable { case continueSession, mergeTime, resetTimer }`.
  - `struct SessionRecord: Codable, Equatable { let name: String; let start: Date; let end: Date; let workSeconds: Double }`.
  - `struct PersistedState: Codable, Equatable` with `kind`, `name`, `sessionStart`, `totalPaused`, `pauseStart`, `pauseReason`, `pauseBundleID`, `awayStart`, `awayTrigger`, `pendingAway`, `lastApp`, `savedAt`; nested `enum Kind: String, Codable { case idle, running, paused, awaiting }`.
  - `extension PersistedState`: `init(state:name:sessionStart:totalPaused:pauseStart:away:lastApp:savedAt:)` flattening a live state, and `var restoredPauseReason: PauseReason`.
  - `enum FocusConstants` — `awayDebounce: 5`, `distractionDwell: 20`, `thresholdOptions: [300, 600, 900, 1800]`, `defaultThreshold: 900`, `archiveCapacity: 50`, `titleRefreshInterval: 30`, `titleRefreshTolerance: 15`, `alertPresentationDelay: 1.5`, `bundleIdentifier: "com.prabesh.focuscontinuity"`.
  - `enum Diagnostics { static func log(_ message: String) }` writing to stderr.

- [ ] **Step 1: Write the state and event types**

`SessionState` must be `Equatable` so the engine can detect real transitions; `PauseReason` carries the distraction bundle ID so the menu can explain itself.

```swift
enum SessionState: Equatable {
    case idle
    case running
    case paused(reason: PauseReason)
    case awaitingUserDecision(away: TimeInterval, lastApp: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
```

- [ ] **Step 2: Write the persistence models and the flattening initialiser**

Associated values are flattened to primitives so the stored format stays stable:

```swift
extension PersistedState {
    init(state: SessionState, name: String, sessionStart: Date, totalPaused: TimeInterval,
         pauseStart: Date?, away: (start: Date, trigger: AwayTrigger)?,
         lastApp: String, savedAt: Date) {
        var kind: Kind
        var reason: String?
        var bundleID: String?
        var pending: TimeInterval?
        switch state {
        case .idle: kind = .idle
        case .running: kind = .running
        case .paused(let pauseReason):
            kind = .paused
            switch pauseReason {
            case .manual: reason = "manual"
            case .extendedBreak: reason = "extendedBreak"
            case .systemSleep: reason = "systemSleep"
            case .distractionApp(let id): reason = "distractionApp"; bundleID = id
            }
        case .awaitingUserDecision(let away, _): kind = .awaiting; pending = away
        }
        self.init(kind: kind, name: name, sessionStart: sessionStart, totalPaused: totalPaused,
                  pauseStart: pauseStart, pauseReason: reason, pauseBundleID: bundleID,
                  awayStart: away?.start, awayTrigger: away?.trigger, pendingAway: pending,
                  lastApp: lastApp, savedAt: savedAt)
    }
}
```

- [ ] **Step 3: Write the constants and diagnostics**

```swift
enum Diagnostics {
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("[FocusContinuity] \(message)\n".utf8))
    }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `swiftc -parse Sources/SessionState.swift`
Expected: no output, exit 0.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

```bash
git add Sources/SessionState.swift && git commit -m "feat: session state and persistence model types"
```

---

### Task 2: PersistenceStore

**Files:**
- Create: `Sources/PersistenceStore.swift`

**Interfaces:**
- Consumes: `PersistedState`, `SessionRecord`, `FocusConstants`, `Diagnostics` (Task 1).
- Produces: `final class PersistenceStore` with `init(defaults: UserDefaults = .standard)`, `loadState() -> PersistedState?`, `saveState(_:)`, `clearState()`, `var archive: [SessionRecord]`, `appendArchive(_:)`, `completedSessions(on:calendar:) -> Int`, `var overrides: [String: String]`, `var breakThreshold: TimeInterval`, `var sessionName: String`, `removeAll()`.

- [ ] **Step 1: Implement the Codable state slot with corruption tolerance**

Decode failures must not crash and must not wedge the app on every launch — drop the bad blob and continue:

```swift
func loadState() -> PersistedState? {
    guard let data = defaults.data(forKey: Key.state) else { return nil }
    do {
        return try decoder.decode(PersistedState.self, from: data)
    } catch {
        Diagnostics.log("discarding unreadable persisted state: \(error)")
        defaults.removeObject(forKey: Key.state)
        return nil
    }
}
```

- [ ] **Step 2: Implement the capped archive ring (D13)**

```swift
func appendArchive(_ record: SessionRecord) {
    var records = archive
    records.append(record)
    if records.count > FocusConstants.archiveCapacity {
        records.removeFirst(records.count - FocusConstants.archiveCapacity)
    }
    do { defaults.set(try encoder.encode(records), forKey: Key.archive) }
    catch { Diagnostics.log("failed to persist archive: \(error)") }
}
```

- [ ] **Step 3: Implement preferences with a non-zero default threshold**

`UserDefaults.double(forKey:)` returns `0` for a missing key, which must not be mistaken for a zero-second threshold:

```swift
var breakThreshold: TimeInterval {
    get {
        let stored = defaults.double(forKey: Key.threshold)
        guard stored > 0 else { return FocusConstants.defaultThreshold }
        return stored
    }
    set { defaults.set(newValue, forKey: Key.threshold) }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `swiftc -parse Sources/SessionState.swift Sources/PersistenceStore.swift`
Expected: no output, exit 0.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 3: CategoryManager

**Files:**
- Create: `Sources/CategoryManager.swift`

**Interfaces:**
- Consumes: `AppCategory` (Task 1), `PersistenceStore` (Task 2).
- Produces: `final class CategoryManager` with `static let builtInMap: [String: AppCategory]`, `init(store:)`, `category(for bundleID: String?) -> AppCategory`, `setOverride(_:for:)`, `clearOverride(for:)`, `hasOverride(for:) -> Bool`.

- [ ] **Step 1: Write the code-constant built-in map**

Work: `com.todesktop.230313mzl4w4u92`, `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`, `com.apple.Terminal`, `com.googlecode.iterm2`, `com.docker.docker`, `com.postmanlabs.mac`, `com.apple.dt.Xcode`, `com.jetbrains.WebStorm`, `com.figma.Desktop`, `com.tinyapp.TablePlus`, `com.github.GitHubClient`.
Break: `com.spotify.client`, `com.apple.Music`, `com.apple.TV`, `com.netflix.Netflix`, `com.hnc.Discord`, `com.apple.iChat`, `tv.parsec.www`, `com.valvesoftware.steam`.
Neutral (explicit, though also the default): `com.apple.Safari`, `com.google.Chrome`, `company.thebrowser.Browser`, `com.apple.finder`, `com.apple.systempreferences`, `com.apple.systemsettings`, `com.apple.mail`, `com.apple.Notes`.

- [ ] **Step 2: Implement D4 precedence, tolerating a nil bundle ID**

`NSRunningApplication.bundleIdentifier` is optional and frequently nil — never force-unwrap it:

```swift
func category(for bundleID: String?) -> AppCategory {
    guard let bundleID, !bundleID.isEmpty else { return .neutral }
    if let raw = store.overrides[bundleID], let override = AppCategory(rawValue: raw) {
        return override
    }
    return CategoryManager.builtInMap[bundleID] ?? .neutral
}
```

- [ ] **Step 3: Verify it compiles**

Run: `swiftc -parse Sources/SessionState.swift Sources/PersistenceStore.swift Sources/CategoryManager.swift`
Expected: no output, exit 0.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 4: SessionEngine — time arithmetic

**Files:**
- Create: `Sources/SessionEngine.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: `final class SessionEngine` with `init(store:ownBundleID:schedulesDwell:now:)` where `now: () -> Date = Date.init`; `var onStateChanged: ((SessionState) -> Void)?`; `var onNeedsDecision: ((TimeInterval, String) -> Void)?`; `let store`, `let categories`; `private(set) var state`, `sessionStartDate`, `totalPausedDuration`, `currentAppName`, `currentAppBundleID`; `var elapsed: TimeInterval`; `var sessionsToday: Int`; `var sessionName: String`; `var breakThreshold: TimeInterval`.

- [ ] **Step 1: Inject the clock**

The engine must never call `Date()` directly, so the self-test can drive it:

```swift
init(store: PersistenceStore = PersistenceStore(),
     ownBundleID: String? = Bundle.main.bundleIdentifier,
     schedulesDwell: Bool = true,
     now: @escaping () -> Date = Date.init) {
    self.store = store
    self.categories = CategoryManager(store: store)
    self.ownBundleID = ownBundleID
    self.schedulesDwell = schedulesDwell
    self.now = now
    self.sessionStartDate = now()
}
```

- [ ] **Step 2: Implement skew-clamped intervals (D1)**

```swift
private func interval(from date: Date) -> TimeInterval {
    let raw = now().timeIntervalSince(date)
    if raw < 0 {
        Diagnostics.log("clock skew: negative interval \(raw)s clamped to 0")
        return 0
    }
    return raw
}
```

- [ ] **Step 3: Implement the elapsed formula (D2)**

`totalPausedDuration` only accumulates on *exit* from a pause, so the in-flight pause is subtracted live and the displayed time freezes while paused:

```swift
var elapsed: TimeInterval {
    let gross = interval(from: sessionStartDate)
    let live = pauseStartDate.map { interval(from: $0) } ?? 0
    return max(0, gross - totalPausedDuration - live)
}
```

- [ ] **Step 4: Verify with a scratch check that two pause cycles subtract correctly**

600s work, 120s pause, 300s work, 60s pause, 100s work ⇒ `elapsed == 1000`, `totalPausedDuration == 180`. This becomes self-test 1 in Task 10.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 5: SessionEngine — the total transition table

**Files:**
- Modify: `Sources/SessionEngine.swift`

**Interfaces:**
- Consumes: Task 4's stored properties.
- Produces: `func transition(on event: SessionEvent)`; `func applyOverride(_ category: AppCategory, to bundleID: String)`.

- [ ] **Step 1: Write one exhaustive switch over `(state, event)`**

Every pair is listed; illegal pairs `break` with a comment. Never a crash, never a `default:` that hides a missing case.

```swift
switch (state, event) {
case (.idle, .launch):
    beginFreshSession()
case (.running, .awayBegan(let trigger)):
    recordAway(trigger)                       // record only; no state change yet
case (.running, .awayEnded):
    resolveAway()
case (.running, .dwellExpired(let bundleID)):
    if currentAppBundleID == bundleID,
       categories.category(for: bundleID) == .breakTime {
        enterPause(reason: .distractionApp(bundleID: bundleID))
    }
case (.paused, .appActivated(let bundleID, let name)):
    recordApp(bundleID: bundleID, name: name)
    cancelDwell()
    if categories.category(for: bundleID) == .work { leavePause() }
    // .neutral and .breakTime leave the pause untouched (D5)
case (.awaitingUserDecision, .launch), (.awaitingUserDecision, .awayEnded),
     (.awaitingUserDecision, .dwellExpired), (.awaitingUserDecision, .manualPause),
     (.awaitingUserDecision, .manualResume), (.awaitingUserDecision, .overrideApplied):
    break // documented no-op: the alert owns the next transition (D10)
}
```

- [ ] **Step 2: Emit exactly once per real transition**

```swift
if state != previous || forceEmit {
    persist()
    onStateChanged?(state)
}
if case .awaitingUserDecision(let away, let app) = state, state != previous {
    onNeedsDecision?(away, app)
}
```

`forceEmit` is set only where the session identity changes but the state name does not (reset while already `.running`).

- [ ] **Step 3: Implement away resolution (D7/D8/D9)**

The first away event wins and resolution is idempotent:

```swift
private func recordAway(_ trigger: AwayTrigger) {
    guard awayInterval == nil else { return }
    awayInterval = (start: now(), trigger: trigger)
}

private func resolveAway() {
    guard let interval = awayInterval else { return }
    awayInterval = nil
    resolve(away: self.interval(from: interval.start))
}

private func resolve(away: TimeInterval) {
    if away < FocusConstants.awayDebounce { return }
    if away < breakThreshold {
        totalPausedDuration += away
        persist()
        return
    }
    cancelDwell()
    state = .awaitingUserDecision(away: away, lastApp: currentAppName)
}
```

- [ ] **Step 4: Implement the decision semantics (D12)**

Merge Time credits the away time as work (it was never subtracted); Continue Session discards it; Reset Timer archives and starts fresh. Any away interval opened *while the alert was up* dies with the decision so the next lock starts clean:

```swift
private func apply(_ decision: UserDecision) {
    guard case .awaitingUserDecision(let away, _) = state else { return }
    awayInterval = nil
    switch decision {
    case .continueSession: totalPausedDuration += away; state = .running
    case .mergeTime:       state = .running
    case .resetTimer:      archiveCurrentSession(); beginFreshSession()
    }
}
```

- [ ] **Step 5: Implement the dwell guard (D6)**

A single-shot `DispatchWorkItem` on main, cancelled whenever focus leaves. This is not a repeating timer and does not violate C4:

```swift
private func scheduleDwell(for bundleID: String) {
    guard schedulesDwell else { return }
    let item = DispatchWorkItem { [weak self] in
        self?.pendingDwell = nil
        self?.transition(on: .dwellExpired(bundleID: bundleID))
    }
    pendingDwell = item
    DispatchQueue.main.asyncAfter(deadline: .now() + FocusConstants.distractionDwell,
                                  execute: item)
}
```

- [ ] **Step 6: Implement immediate override evaluation (§5)**

An explicit override is applied against the current state rather than waiting out a fresh 20 s dwell:

```swift
func applyOverride(_ category: AppCategory, to bundleID: String) {
    categories.setOverride(category, for: bundleID)
    let previous = state
    transition(on: .overrideApplied(bundleID: bundleID))
    if state == previous { onStateChanged?(state) }
}
```

- [ ] **Step 7: Implement snapshot/restore (D14)**

`restore` resolves the gap since the last persist through the same away path a live lock/wake would take:

```swift
case .running:
    state = .running
    let gap = interval(from: snapshot.awayStart ?? snapshot.savedAt)
    resolve(away: gap)
```

- [ ] **Step 8: Verify it compiles**

Run: `swiftc -parse Sources/SessionState.swift Sources/PersistenceStore.swift Sources/CategoryManager.swift Sources/SessionEngine.swift`
Expected: no output, exit 0.

- [ ] **Step 9: Commit** *(skipped — not a git repository)*

---

### Task 6: EventMonitor

**Files:**
- Create: `Sources/EventMonitor.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure AppKit).
- Produces: `final class EventMonitor` with `var onScreenLocked`, `onScreenUnlocked`, `onSystemWillSleep`, `onSystemDidWake`, `onAppActivated: ((NSRunningApplication) -> Void)?`, `onWillPowerOff`, plus `start()`, `stop()`, `deinit`.

- [ ] **Step 1: Subscribe to the distributed lock notifications**

These are *not* available on `NSWorkspace`:

```swift
distributedTokens.append(
    distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                            object: nil, queue: .main) { [weak self] _ in
        self?.onScreenLocked?()
    })
```

- [ ] **Step 2: Subscribe to the workspace notifications**

Use `NSWorkspace.shared.notificationCenter`, never `NotificationCenter.default` — the latter silently delivers nothing. Sleep and screen-sleep both map to `onSystemWillSleep`; wake and screen-wake both map to `onSystemDidWake` (the engine coalesces them per D8). `sessionDidResignActive`/`sessionDidBecomeActive` map onto lock/unlock.

```swift
for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
    workspaceTokens.append(
        workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.onSystemDidWake?()
        })
}
```

- [ ] **Step 3: Extract the activated app without force-unwrapping**

```swift
workspaceTokens.append(
    workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                          object: nil, queue: .main) { [weak self] note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        self?.onAppActivated?(app)
    })
```

- [ ] **Step 4: Store every token and remove it in `stop()` and `deinit`**

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 7: AlertPresenter

**Files:**
- Create: `Sources/AlertPresenter.swift`

**Interfaces:**
- Consumes: `UserDecision`, `Diagnostics` (Task 1).
- Produces: `final class AlertPresenter` with `private(set) var isPresentingAlert: Bool`, `presentExtendedBreak(away:lastApp:afterDelay:completion:)`, `presentRename(currentName:completion:)`, `static func humanDuration(_:) -> String`.

- [ ] **Step 1: Guard re-entrancy (D10)**

```swift
guard !isPresentingAlert else {
    Diagnostics.log("suppressed a second extended-break alert")
    return
}
isPresentingAlert = true
```

- [ ] **Step 2: Force focus and restore the policy (D11)**

```swift
private func runFocused(_ alert: NSAlert,
                        beforeRun: (() -> Void)? = nil) -> NSApplication.ModalResponse {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    alert.window.level = .floating
    alert.window.center()
    beforeRun?()
    let response = alert.runModal()
    NSApp.setActivationPolicy(.accessory)
    return response
}
```

- [ ] **Step 3: Delay presentation after a wake so the WindowServer is ready (D11)**

Wrap the whole presentation in `DispatchQueue.main.asyncAfter(deadline: .now() + delay)` with `[weak self]`. Buttons are **Merge Time / Continue Session / Reset Timer**, mapped from `.alertFirstButtonReturn` / `.alertSecondButtonReturn` / `.alertThirdButtonReturn`.

- [ ] **Step 4: Build the rename prompt with an `NSTextField` accessory view**

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 8: MenuBarController

**Files:**
- Create: `Sources/MenuBarController.swift`

**Interfaces:**
- Consumes: `SessionEngine` (Tasks 4–5), `FocusConstants`, `AppCategory`.
- Produces: `final class MenuBarController: NSObject, NSMenuDelegate` with `init(engine: SessionEngine)`, `var onRenameRequested: (() -> Void)?`, `func stateChanged(_ state: SessionState)`, `static func format(_ seconds: TimeInterval) -> String`.

- [ ] **Step 1: Create the status item**

`.variableLength` lives on `NSStatusItem`, not on `CGFloat`:

```swift
private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
```

- [ ] **Step 2: Implement the cosmetic timer (D3)**

Created on entry to `.running`, invalidated on exit. It reads no state-machine input and decides nothing — it only re-renders the title:

```swift
private func startTitleTimer() {
    guard titleTimer == nil else { return }
    let timer = Timer(timeInterval: FocusConstants.titleRefreshInterval, repeats: true) { [weak self] _ in
        self?.refreshTitle()
    }
    timer.tolerance = FocusConstants.titleRefreshTolerance
    RunLoop.main.add(timer, forMode: .common)
    titleTimer = timer
}
```

- [ ] **Step 3: Render the title (D15, D16)**

Monospaced digits so the width does not jitter; `⏸` prefix and `secondaryLabelColor` when paused:

```swift
static func format(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
```

- [ ] **Step 4: Rebuild volatile items in `menuWillOpen(_:)`**

```swift
func menuWillOpen(_ menu: NSMenu) {
    refreshTitle()
    rebuildMenu()
}
```

Menu order: `Session: "<name>"` ⌘N; `Status: <state> · <elapsed>` (disabled); `Active: <app> — <category>` (disabled); separator; `Pause Session`/`Resume Session` ⌘P; `Override "<app>" as…` ▸ Work/Break/Neutral with a checkmark on the current one; `Settings` ▸ `Break Threshold` ▸ 5m/10m/15m/30m with a checkmark; separator; `Sessions today: N` (disabled); `Reset Session` ⌘R; `Quit FocusContinuity` ⌘Q.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 9: main.swift and AppDelegate

**Files:**
- Create: `Sources/main.swift`, `Sources/AppDelegate.swift`

**Interfaces:**
- Consumes: `SessionEngine`, `EventMonitor`, `AlertPresenter`, `MenuBarController`, `SelfTest.run()` (Task 10).
- Produces: the running application.

- [ ] **Step 1: Write the explicit bootstrap with the self-test gate**

```swift
import Cocoa

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Wire the monitor to the engine with `[weak self]` throughout**

```swift
monitor.onScreenLocked = { [weak self] in
    self?.engine.transition(on: .awayBegan(trigger: .screenLock))
}
monitor.onAppActivated = { [weak self] app in
    self?.engine.transition(on: .appActivated(bundleID: app.bundleIdentifier,
                                              name: app.localizedName ?? "Unknown"))
}
```

- [ ] **Step 3: Restore the snapshot, *then* seed the frontmost app, then launch**

Order matters and is easy to get backwards. From `.idle`, a work-app activation calls `beginFreshSession()`, which changes state, which persists — overwriting the very snapshot you are about to read. Restore first:

```swift
if let snapshot = engine.store.loadState() { engine.restore(from: snapshot) }
if let frontmost = NSWorkspace.shared.frontmostApplication {
    engine.transition(on: .appActivated(bundleID: frontmost.bundleIdentifier,
                                        name: frontmost.localizedName ?? "Unknown"))
}
if engine.state == .idle { engine.transition(on: .launch) }
```

Seeding second also means the restored state is evaluated against what is actually on screen: a session restored into `.paused(.distractionApp)` while you are already back in your editor resumes immediately instead of waiting for the next activation notification.

- [ ] **Step 4: Persist on terminate and on power-off (D14)**

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 10: SelfTest — ten headless logic tests

**Files:**
- Create: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `SessionEngine`, `PersistenceStore`, `PersistedState`.
- Produces: `enum SelfTest { static func run() -> Bool }`.

- [ ] **Step 1: Build an injectable clock and an isolated defaults suite**

Tests must not touch the real `com.prabesh.focuscontinuity` domain, and must not schedule work items that outlive the process:

```swift
private static func makeEngine(_ clock: Clock) -> SessionEngine {
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    let store = PersistenceStore(defaults: defaults)
    store.removeAll()
    return SessionEngine(store: store,
                         ownBundleID: FocusConstants.bundleIdentifier,
                         schedulesDwell: false,
                         now: { clock.value })
}
```

- [ ] **Step 2: Write tests 1–5**

1. Elapsed maths with two pause cycles → `elapsed == 1000`, `totalPaused == 180`.
2. Debounce — 3 s away → `totalPaused == 0`, still `.running`.
3. Micro-break — 8 min away at a 15 min threshold → `totalPaused == 480`, still `.running`, zero `onNeedsDecision` calls.
4. Extended break — 22 min away → `.awaitingUserDecision(away: 1320, …)` and the callback fires; then events during the alert must not resume, and the decision must not leave a stale away interval behind.
5. Merge Time vs Continue Session → `merged - continued == 1320` exactly.

```swift
let merged = elapsedAfter(.mergeTime)
let continued = elapsedAfter(.continueSession)
expectClose(merged - continued, away, "merge minus continue", &problems)
```

- [ ] **Step 3: Write tests 6–10**

6. Category precedence — override beats the built-in map; clearing falls back; unknown and nil are `.neutral`.
7. Coalescing — lock, +5 s sleep (ignored), unlock, wake → `totalPaused == 600`, resolved exactly once.
8. Negative clock skew — a backwards jump clamps to 0, so the interval is discarded and `elapsed` never goes negative.
9. `Codable` round-trip — encode/decode `snapshot()`, compare equal, then `restore` and confirm the state and elapsed survive.
10. Exhaustive transition table — four state setups × sixteen events; no crash, no negative elapsed, and no unexpected exit from `.idle`.

- [ ] **Step 4: Run the suite**

Run: `./build.sh --test`
Expected: ten `[PASS]` lines and `10/10 passed`, exit 0.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 11: build.sh and README

**Files:**
- Create: `build.sh`, `README.md`

**Interfaces:**
- Consumes: all of `Sources/*.swift`.
- Produces: `FocusContinuity.app` in the repo root.

- [ ] **Step 1: Write the build script**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TARGET_TRIPLE="$(uname -m)-apple-macos13.0"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
swiftc -O -whole-module-optimization -swift-version 5 -warnings-as-errors \
  -target "${TARGET_TRIPLE}" -framework Cocoa \
  -o "${BINARY}" Sources/*.swift
```

The target triple pins the deployment version to 13.0 rather than the host OS version: it satisfies C8 and keeps APIs deprecated in later releases (such as `activate(ignoringOtherApps:)`) warning-free under `-warnings-as-errors`.

- [ ] **Step 2: Write the complete `Info.plist`**

`CFBundleExecutable`, `CFBundleIdentifier` = `com.prabesh.focuscontinuity`, `CFBundleName`, `CFBundlePackageType` = `APPL`, `CFBundleShortVersionString` = `1.0.0`, `CFBundleVersion` = `1`, `LSMinimumSystemVersion` = `13.0`, `LSUIElement` = `true`, `NSPrincipalClass` = `NSApplication`, `NSHighResolutionCapable` = `true`.

- [ ] **Step 3: Ad-hoc sign (D17)**

`codesign` rejects any Finder metadata the filesystem attached, so strip extended attributes first:

```bash
xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"
```

- [ ] **Step 4: Print the binary size and support `--run` / `--test`**

- [ ] **Step 5: Write the README** — what it does, how to build, how to test, how the state machine behaves.

- [ ] **Step 6: Verify the full pipeline**

Run: `./build.sh --test`
Expected: `Build succeeded: FocusContinuity.app`, then `10/10 passed`.

- [ ] **Step 7: Commit** *(skipped — not a git repository)*

---

### Task 12: Verification

**Files:**
- Modify: none (measurement only).

- [ ] **Step 1: Clean build with zero warnings**

Run: `./build.sh`
Expected: `Build succeeded`. `-warnings-as-errors` means any warning fails the build.

- [ ] **Step 2: All self-tests pass**

Run: `./build.sh --test`
Expected: `10/10 passed`.

- [ ] **Step 3: Anti-pattern scan**

Run: `grep -rnE 'TODO|FIXME|fatalError|Thread\.sleep|usleep|NotificationCenter\.default|DispatchQueue\.main\.sync' Sources/`
Expected: no matches other than the comment noting that `NotificationCenter.default` is *not* used.

- [ ] **Step 4: Launch and confirm no Dock icon**

Run: `open FocusContinuity.app` then `lsappinfo list | grep -A4 -i focuscontinuity`
Expected: `type="UIElement"`.

- [ ] **Step 5: Measure idle cost against C3**

Run: `ps -o %cpu,rss -p $(pgrep -f FocusContinuity)` after 60 s idle, and `footprint -p <pid>`.
Expected: 0.0% CPU and an app footprint under 25 MB. Note that `ps rss` counts shared framework pages resident across all processes; `phys_footprint` is the app's own memory and is the figure to compare against C3.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*
