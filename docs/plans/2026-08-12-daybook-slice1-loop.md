# Daybook Slice 1 — The Loop — Implementation Plan

**Goal:** Replace Daybook's AppKit menu-bar UI with SwiftUI surfaces implementing the start → focus → reward loop: a menu bar popover with a focused intent field, one-click start, live timer, today's total, streak and weekly chart, plus a Today window and a `--gallery` state catalogue.

**Architecture:** `Core/` keeps all logic and never imports SwiftUI, so the existing headless self-test keeps running. A single `SessionStore` (`ObservableObject`) subscribes to the engine's callbacks and republishes `@Published` state to views. The engine moves from one continuous session to discrete records persisted to a Codable file store.

**Tech Stack:** Swift 5 language mode, SwiftUI, Swift Charts, AppKit (bridged where needed), Foundation. Built by `swiftc` via `build.sh` — no Xcode project, no SPM.

**Spec:** `docs/specs/2026-08-12-daybook-ui-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **No Xcode on this machine.** `@State` and `@Observable` do not compile (`SwiftUIMacros` plugin absent). All view state lives in `ObservableObject` + `@Published`, consumed via `@StateObject` / `@ObservedObject` / `@EnvironmentObject`. `@Binding`, `@Environment`, `@FocusState`, `@AppStorage` are verified working and may be used freely.
- **`-parse-as-library` is mandatory** once `@main` lands; `main.swift` and `@main` cannot coexist.
- **`Core/` never imports SwiftUI.** Violating this breaks the headless self-test.
- **macOS 13.0 deployment target**, host architecture only. No SwiftData (needs 14+), no CloudKit, no entitlements, no sandbox, ad-hoc signing only.
- **No TCC permissions.** No Accessibility, no Automation, no Screen Recording, no Input Monitoring. If a feature needs one, the feature is dropped, not the promise.
- **Zero warnings.** `build.sh` passes `-warnings-as-errors`; a warning fails the build.
- **No file deletion.** Retired files move to `_trash/` preserving the filename (user's standing rule), never `rm`.
- **Semantic colours only** — `.primary`, `.secondary`, `.tint`, materials. No hardcoded hex.
- **`./build.sh --test` must pass at the end of every task.** The suite currently has 14 tests; it only grows.
- **Not a git repository.** Commit steps are recorded but skipped. Run `git init` first if you want them to execute.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/Core/SessionState.swift` | Types: `SessionState`, `PauseReason`, `AwayTrigger`, `AppCategory`, `WorkType`, `SessionEvent`, `UserDecision`, `SessionRecord`, `PersistedState`, constants |
| `Sources/Core/SessionEngine.swift` | State machine, time arithmetic, discrete session start/stop |
| `Sources/Core/SessionArchive.swift` | **New.** Codable file store + today / week / streak / quick-start queries |
| `Sources/Core/PersistenceStore.swift` | Preferences in `UserDefaults`; live-state snapshot |
| `Sources/Core/CategoryManager.swift` | Bundle ID → `AppCategory` (auto-pause) + suggested `WorkType` |
| `Sources/Core/EventMonitor.swift` | Workspace + distributed notification subscriptions |
| `Sources/Core/HotKeyMonitor.swift` | **New.** Carbon `RegisterEventHotKey` wrapper |
| `Sources/Core/Notifier.swift` | **New.** `UNUserNotificationCenter` wrapper that degrades to a no-op |
| `Sources/App/DaybookApp.swift` | `@main`, arg gate, `MenuBarExtra` + `Window` scenes |
| `Sources/App/AppCoordinator.swift` | `NSApplicationDelegate` for lifecycle + monitor wiring |
| `Sources/App/SessionStore.swift` | The one bridge: engine callbacks → `@Published` view state |
| `Sources/Surfaces/PopoverView.swift` | Menu bar popover, three zones |
| `Sources/Surfaces/TodayView.swift` | Today window |
| `Sources/Surfaces/GalleryView.swift` | `--gallery` state catalogue |
| `Sources/Design/DesignTokens.swift` | Spacing, type ramp, durations, formatters |
| `Sources/Design/Components/*.swift` | `StartButton`, `LiveTimer`, `StreakBadge`, `StatTile`, `WeekChart`, `ResolveCard`, `QuickStartRow`, `IntentField` |
| `Sources/SelfTest.swift` | Headless tests (grows from 14) |

Retired to `_trash/`: `main.swift`, `MenuBarController.swift`, `AlertPresenter.swift`.

---

### Task 1: Spikes — notifications and global hotkey

Two unknowns in the spec change later tasks. Resolve them before building on them.

**Files:**
- Create: `/tmp/spike/Notify.swift`, `/tmp/spike/HotKey.swift` (scratch only — nothing enters the repo)

**Interfaces:**
- Consumes: nothing.
- Produces: two recorded yes/no answers that gate Task 10 and Task 11.

- [ ] **Step 1: Spike notification authorisation under ad-hoc signing**

Write a throwaway app bundle that requests authorisation and posts a notification. It must be a real `.app` with the project's bundle id, because `UNUserNotificationCenter` refuses to work for a bare executable.

```swift
import AppKit
import UserNotifications

final class D: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("granted=\(granted) error=\(String(describing: error))")
            let content = UNMutableNotificationContent()
            content.title = "Away 22m"
            content.body = "Was that a break?"
            let req = UNNotificationRequest(identifier: "spike",
                                            content: content,
                                            trigger: nil)
            c.add(req) { err in
                print("post error=\(String(describing: err))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
            }
        }
    }
}
let app = NSApplication.shared
let d = D(); app.delegate = d
app.setActivationPolicy(.accessory)
app.run()
```

Bundle it exactly as `build.sh` does (Info.plist with `CFBundleIdentifier = com.prabesh.daybook.spike`, `LSUIElement = true`), ad-hoc sign, and run it.

- [ ] **Step 2: Record the notification answer**

Expected on success: `granted=true error=nil`, `post error=nil`, and a banner appears.
If it prints an error mentioning a missing bundle proxy or authorisation fails outright, notifications are unavailable under ad-hoc signing.

Write the answer into the spec's §3 table, replacing **Unverified**. If unavailable, Task 10 drops the notification and relies solely on the attention badge and the popover resolve card — the flow already degrades safely, so nothing else changes.

- [ ] **Step 3: Spike the Carbon hotkey without Accessibility**

```swift
import AppKit
import Carbon.HIToolbox

var ref: EventHotKeyRef?
var id = EventHotKeyID(signature: OSType(0x46435459), id: 1) // 'FCTY'
let status = RegisterEventHotKey(UInt32(kVK_Space),
                                 UInt32(controlKey | optionKey),
                                 id, GetApplicationEventTarget(), 0, &ref)
print("RegisterEventHotKey status=\(status) (0 == success)")

var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                         eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    print("HOTKEY FIRED")
    return noErr
}, 1, &spec, nil, nil)

print("Press control-option-space within 15s. Accessibility must NOT be granted to this binary.")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { exit(0) }
app.run()
```

- [ ] **Step 4: Record the hotkey answer**

Expected: `status=0` and `HOTKEY FIRED` when the combination is pressed, with no Accessibility prompt and no TCC entry.
If registration fails or the handler never fires without an Accessibility grant, **Task 11 is dropped entirely** — the spec is explicit that the privacy promise outranks the convenience. Record the outcome in the spec.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 2: Core data layer — `WorkType`, `SessionRecord`, `SessionArchive`

**Files:**
- Modify: `Sources/Core/SessionState.swift`
- Create: `Sources/Core/SessionArchive.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: existing `FocusConstants`, `Diagnostics`.
- Produces:
  - `enum WorkType: String, Codable, CaseIterable { case deepWork, meetings, admin, learning, breakTime }` with `var displayName: String` and `var symbolName: String`.
  - `struct SessionRecord: Codable, Equatable, Identifiable` — `id: UUID`, `name: String`, `workType: WorkType`, `start: Date`, `end: Date`, `workSeconds: Double`, `detectedApp: String?`.
  - `final class SessionArchive` — `init(directory: URL, now: @escaping () -> Date)`, `append(_:)`, `var records: [SessionRecord]`, `todayTotal() -> TimeInterval`, `weekBars() -> [DayBar]`, `sessionsToday() -> Int`, `longestToday() -> TimeInterval`, `currentStreak() -> Int`, `quickStarts(limit: Int) -> [QuickStart]`.
  - `struct DayBar: Identifiable, Equatable` — `id: Date`, `label: String`, `minutes: Int`, `isToday: Bool`.
  - `struct QuickStart: Identifiable, Equatable` — `id: String`, `name: String`, `workType: WorkType`.

- [ ] **Step 1: Write the failing tests**

Add to `SelfTest.swift` and register them in the `tests` array:

```swift
private static func testArchiveQueries() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fc-selftest-\(UUID().uuidString)")
    let archive = SessionArchive(directory: dir, now: { clock.value })

    // Three sessions today totalling 90 minutes, one of them 50.
    for minutes in [20.0, 50.0, 20.0] {
        archive.append(SessionRecord(id: UUID(), name: "s", workType: .deepWork,
                                     start: clock.value,
                                     end: clock.value.addingTimeInterval(minutes * 60),
                                     workSeconds: minutes * 60, detectedApp: nil))
    }
    expectClose(archive.todayTotal(), 90 * 60, "todayTotal", &problems)
    expect(archive.sessionsToday() == 3, "sessionsToday", &problems)
    expectClose(archive.longestToday(), 50 * 60, "longestToday", &problems)

    // Week bars: 7 entries, last is today, today holds 90 minutes.
    let bars = archive.weekBars()
    expect(bars.count == 7, "weekBars should have 7 entries, got \(bars.count)", &problems)
    expect(bars.last?.isToday == true, "last bar should be today", &problems)
    expect(bars.last?.minutes == 90, "today should be 90 minutes, got \(bars.last?.minutes ?? -1)",
           &problems)

    try? FileManager.default.removeItem(at: dir)
    return problems
}

private static func testStreakRule() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fc-selftest-\(UUID().uuidString)")
    let archive = SessionArchive(directory: dir, now: { clock.value })
    let day: TimeInterval = 86_400

    func add(daysAgo: Int, minutes: Double) {
        let start = clock.value.addingTimeInterval(-Double(daysAgo) * day)
        archive.append(SessionRecord(id: UUID(), name: "s", workType: .deepWork,
                                     start: start,
                                     end: start.addingTimeInterval(minutes * 60),
                                     workSeconds: minutes * 60, detectedApp: nil))
    }

    add(daysAgo: 0, minutes: 30)   // today qualifies
    add(daysAgo: 1, minutes: 30)   // yesterday qualifies
    add(daysAgo: 2, minutes: 10)   // below the 25 minute bar — breaks the streak
    add(daysAgo: 3, minutes: 60)
    expect(archive.currentStreak() == 2,
           "streak should be 2, got \(archive.currentStreak())", &problems)

    try? FileManager.default.removeItem(at: dir)
    return problems
}

private static func testArchivePersistenceAndCorruption() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fc-selftest-\(UUID().uuidString)")

    let first = SessionArchive(directory: dir, now: { clock.value })
    first.append(SessionRecord(id: UUID(), name: "Refactor", workType: .deepWork,
                               start: base, end: base.addingTimeInterval(600),
                               workSeconds: 600, detectedApp: "com.apple.Terminal"))

    // A second instance reads what the first wrote.
    let second = SessionArchive(directory: dir, now: { clock.value })
    expect(second.records.count == 1, "record should survive a reload", &problems)
    expect(second.records.first?.name == "Refactor", "name should survive", &problems)

    // A corrupt file is moved aside, not fatal, and the store starts empty.
    let file = dir.appendingPathComponent("sessions.json")
    try? Data("not json".utf8).write(to: file)
    let third = SessionArchive(directory: dir, now: { clock.value })
    expect(third.records.isEmpty, "corrupt store should start empty", &problems)
    let salvaged = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    expect(salvaged.contains { $0.hasPrefix("sessions-corrupt-") },
           "corrupt file should be renamed aside, saw \(salvaged)", &problems)

    try? FileManager.default.removeItem(at: dir)
    return problems
}

private static func testQuickStarts() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("fc-selftest-\(UUID().uuidString)")
    let archive = SessionArchive(directory: dir, now: { clock.value })

    func add(_ name: String, _ type: WorkType, count: Int) {
        for _ in 0..<count {
            archive.append(SessionRecord(id: UUID(), name: name, workType: type,
                                         start: clock.value, end: clock.value,
                                         workSeconds: 600, detectedApp: nil))
        }
    }
    add("Refactor", .deepWork, count: 3)
    add("Standup", .meetings, count: 2)
    add("Email", .admin, count: 1)

    let quick = archive.quickStarts(limit: 7)
    expect(quick.count == 3, "3 distinct pairs, got \(quick.count)", &problems)
    expect(quick.first?.name == "Refactor", "most frequent first, got \(quick.first?.name ?? "nil")",
           &problems)
    expect(quick.first?.workType == .deepWork, "work type should ride along", &problems)

    try? FileManager.default.removeItem(at: dir)
    return problems
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.sh --test`
Expected: compile error — `cannot find 'SessionArchive' in scope`.

- [ ] **Step 3: Add the types to `SessionState.swift`**

```swift
enum WorkType: String, Codable, CaseIterable {
    case deepWork, meetings, admin, learning, breakTime

    var displayName: String {
        switch self {
        case .deepWork: return "Deep work"
        case .meetings: return "Meetings"
        case .admin: return "Admin"
        case .learning: return "Learning"
        case .breakTime: return "Break"
        }
    }

    var symbolName: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .meetings: return "person.2.fill"
        case .admin: return "tray.full.fill"
        case .learning: return "book.fill"
        case .breakTime: return "cup.and.saucer.fill"
        }
    }
}

struct SessionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var workType: WorkType
    var start: Date
    var end: Date
    var workSeconds: Double
    var detectedApp: String?
}

struct DayBar: Identifiable, Equatable {
    let id: Date
    let label: String
    let minutes: Int
    let isToday: Bool
}

struct QuickStart: Identifiable, Equatable {
    let id: String
    let name: String
    let workType: WorkType
}
```

Add to `FocusConstants`: `static let streakMinimum: TimeInterval = 25 * 60`, `static let archiveCapacity = 5000`, `static let quickStartWindowDays = 14`.

The old `SessionRecord` (name/start/end/workSeconds) is replaced. `PersistenceStore.appendArchive` and `completedSessions(on:)` move to `SessionArchive`; delete those two members and the `Key.archive` entry from `PersistenceStore`.

- [ ] **Step 4: Implement `SessionArchive.swift`**

Key logic — the rest is mechanical:

```swift
func currentStreak() -> Int {
    let calendar = Calendar.current
    var totals: [Date: TimeInterval] = [:]
    for record in records {
        let day = calendar.startOfDay(for: record.end)
        totals[day, default: 0] += record.workSeconds
    }
    var streak = 0
    var cursor = calendar.startOfDay(for: now())
    // A streak ending yesterday still counts today, so today's zero does not
    // erase it before the first session of the day.
    if (totals[cursor] ?? 0) < FocusConstants.streakMinimum {
        cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
    }
    while (totals[cursor] ?? 0) >= FocusConstants.streakMinimum {
        streak += 1
        guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
        cursor = previous
    }
    return streak
}

func quickStarts(limit: Int) -> [QuickStart] {
    let cutoff = now().addingTimeInterval(-Double(FocusConstants.quickStartWindowDays) * 86_400)
    var counts: [String: (QuickStart, Int, Date)] = [:]
    for record in records where record.end >= cutoff && !record.name.isEmpty {
        let key = "\(record.workType.rawValue)|\(record.name)"
        let entry = counts[key]
        counts[key] = (QuickStart(id: key, name: record.name, workType: record.workType),
                       (entry?.1 ?? 0) + 1,
                       max(entry?.2 ?? .distantPast, record.end))
    }
    return counts.values
        .sorted { $0.1 == $1.1 ? $0.2 > $1.2 : $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
}
```

Loading moves a corrupt file aside rather than failing:

```swift
private func load() -> [SessionRecord] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    do {
        return try JSONDecoder().decode([SessionRecord].self,
                                        from: Data(contentsOf: fileURL))
    } catch {
        let stamp = Int(now().timeIntervalSince1970)
        let aside = directory.appendingPathComponent("sessions-corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: aside)
        Diagnostics.log("archive unreadable, moved to \(aside.lastPathComponent): \(error)")
        return []
    }
}
```

Writes are atomic (`.atomic`) and the array is trimmed to `FocusConstants.archiveCapacity` on append.

- [ ] **Step 5: Run tests**

Run: `./build.sh --test`
Expected: 18/18 passed.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 3: Engine — discrete sessions

**Files:**
- Modify: `Sources/Core/SessionEngine.swift`, `Sources/Core/CategoryManager.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `SessionArchive`, `WorkType`, `SessionRecord` (Task 2).
- Produces:
  - `SessionEngine.start(workType: WorkType, intent: String)` — begins a session.
  - `SessionEngine.stop()` — writes a `SessionRecord` and returns to `.idle`.
  - `SessionEngine.activeIntent: String`, `SessionEngine.activeWorkType: WorkType`.
  - `CategoryManager.suggestedWorkType(for bundleID: String?) -> WorkType`.

- [ ] **Step 1: Write the failing test**

```swift
private static func testDiscreteSessions() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let engine = makeEngine(clock)

    engine.start(workType: .deepWork, intent: "Refactor")
    expect(engine.state == .running, "start should run", &problems)
    expect(engine.activeIntent == "Refactor", "intent should stick", &problems)
    clock.advance(1_500)                       // 25 minutes
    engine.transition(on: .manualPause)
    clock.advance(300)                         // 5 minutes paused
    engine.transition(on: .manualResume)
    clock.advance(600)                         // 10 more minutes
    engine.stop()

    expect(engine.state == .idle, "stop should idle, got \(engine.state)", &problems)
    guard let record = engine.archive.records.last else {
        problems.append("stop should write a record")
        return problems
    }
    expectClose(record.workSeconds, 2_100, "paused time excluded from the record", &problems)
    expect(record.name == "Refactor", "record keeps the intent", &problems)
    expect(record.workType == .deepWork, "record keeps the work type", &problems)
    expectClose(engine.archive.todayTotal(), 2_100, "today total", &problems)

    // A second session accumulates rather than replacing.
    engine.start(workType: .admin, intent: "Email")
    clock.advance(600)
    engine.stop()
    expectClose(engine.archive.todayTotal(), 2_700, "two sessions sum", &problems)
    expect(engine.archive.sessionsToday() == 2, "two sessions counted", &problems)
    return problems
}

private static func testAwayInsideADiscreteSession() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let engine = makeEngine(clock)

    engine.start(workType: .deepWork, intent: "Write")
    clock.advance(600)
    engine.transition(on: .awayBegan(trigger: .screenLock))
    clock.advance(480)                          // 8 minutes: micro-break, absorbed
    engine.transition(on: .awayEnded)
    clock.advance(600)
    engine.stop()

    expectClose(engine.archive.records.last?.workSeconds ?? -1, 1_200,
                "micro-break excluded from the record", &problems)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.sh --test`
Expected: compile error — `value of type 'SessionEngine' has no member 'start'`.

- [ ] **Step 3: Implement**

`SessionEngine` gains:

```swift
private(set) var activeIntent: String = ""
private(set) var activeWorkType: WorkType = .deepWork
let archive: SessionArchive

func start(workType: WorkType, intent: String) {
    if state != .idle { stop() }
    activeWorkType = workType
    activeIntent = intent.trimmingCharacters(in: .whitespacesAndNewlines)
    activeDetectedApp = currentAppBundleID
    transition(on: .launch)
}

func stop() {
    guard state != .idle else { return }
    archiveCurrentSession()
    cancelDwell()
    pauseStartDate = nil
    awayInterval = nil
    decisionStartDate = nil
    state = .idle
    persist()
    onStateChanged?(state)
}
```

`archiveCurrentSession()` is rewritten to emit the new `SessionRecord` shape with `id`, `workType`, `name: activeIntent`, `detectedApp: activeDetectedApp`, and to write through `archive` instead of `store`. `beginFreshSession()` keeps its behaviour for `.resetSession` and `.resetTimer`.

`sessionsToday` and the old `sessionName` accessor move to `archive`; delete the `sessionName` property and its `UserDefaults` key.

`CategoryManager` gains a second, advisory map:

```swift
static let suggestedWorkTypes: [String: WorkType] = [
    "com.apple.dt.Xcode": .deepWork,
    "com.microsoft.VSCode": .deepWork,
    "com.todesktop.230313mzl4w4u92": .deepWork,
    "com.googlecode.iterm2": .deepWork,
    "com.apple.Terminal": .deepWork,
    "us.zoom.xos": .meetings,
    "com.microsoft.teams2": .meetings,
    "com.apple.iChat": .meetings,
    "com.apple.mail": .admin,
    "com.apple.Notes": .admin,
    "com.figma.Desktop": .deepWork,
    "com.spotify.client": .breakTime
]

func suggestedWorkType(for bundleID: String?) -> WorkType {
    guard let bundleID else { return .deepWork }
    return CategoryManager.suggestedWorkTypes[bundleID] ?? .deepWork
}
```

- [ ] **Step 4: Run tests**

Run: `./build.sh --test`
Expected: 20/20 passed.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 4: SwiftUI shell — build system, `@main`, file reorganisation

At the end of this task the app is a SwiftUI menu bar app with a placeholder popover. It must still launch, still track, and still pass every test.

**Files:**
- Create: `Sources/App/DaybookApp.swift`, `Sources/App/AppCoordinator.swift`
- Modify: `build.sh`
- Move to `_trash/`: `Sources/main.swift`, `Sources/MenuBarController.swift`, `Sources/AlertPresenter.swift`
- Move within repo: existing `Sources/*.swift` into `Sources/Core/`, `SelfTest.swift` stays at `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `SessionEngine`, `EventMonitor` (Core).
- Produces: `DaybookApp` with `static func main()`; `AppCoordinator: NSObject, NSApplicationDelegate`.

- [ ] **Step 1: Reorganise sources**

```bash
mkdir -p Sources/Core Sources/App Sources/Surfaces Sources/Design/Components _trash
mv Sources/SessionState.swift Sources/SessionEngine.swift Sources/PersistenceStore.swift \
   Sources/CategoryManager.swift Sources/EventMonitor.swift Sources/SessionArchive.swift Sources/Core/
mv Sources/main.swift Sources/MenuBarController.swift Sources/AlertPresenter.swift _trash/
```

- [ ] **Step 2: Update `build.sh` to compile recursively with `-parse-as-library`**

Replace the `Sources/*.swift` argument and add the flag:

```bash
swiftc \
  -O \
  -whole-module-optimization \
  -swift-version 5 \
  -warnings-as-errors \
  -parse-as-library \
  -target "${TARGET_TRIPLE}" \
  -framework Cocoa \
  -o "${BINARY}" \
  $(find Sources -name '*.swift' | sort)
```

- [ ] **Step 3: Write the entry point**

```swift
import SwiftUI

@main
struct DaybookApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator

    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }
        // `--gallery` is handled in Task 9; until then it falls through to the app.
        DaybookApp.runApp()
    }

    // The synthesised entry point is unavailable once `main()` is custom, so the
    // scene phase is started explicitly.
    private static func runApp() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Daybook")
                .padding()
        } label: {
            Image(systemName: "infinity")
        }
        .menuBarExtraStyle(.window)
    }
}
```

If `NSApplicationMain` conflicts with the `App` lifecycle at runtime, use the documented alternative instead: keep `static func main()` doing only the argument check and then calling the compiler-synthesised entry via a nested type — see Step 5's verification, and prefer whichever actually launches.

- [ ] **Step 4: Write `AppCoordinator`**

```swift
import AppKit

final class AppCoordinator: NSObject, NSApplicationDelegate {
    let engine = SessionEngine()
    private let monitor = EventMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.onScreenLocked = { [weak self] in
            self?.engine.transition(on: .awayBegan(trigger: .screenLock))
        }
        monitor.onSystemWillSleep = { [weak self] in
            self?.engine.transition(on: .awayBegan(trigger: .systemSleep))
        }
        monitor.onScreenUnlocked = { [weak self] in self?.engine.transition(on: .awayEnded) }
        monitor.onSystemDidWake = { [weak self] in self?.engine.transition(on: .awayEnded) }
        monitor.onAppActivated = { [weak self] app in
            self?.engine.transition(on: .appActivated(bundleID: app.bundleIdentifier,
                                                      name: app.localizedName ?? "Unknown"))
        }
        monitor.onWillPowerOff = { [weak self] in self?.engine.persist() }
        monitor.start()

        if let snapshot = engine.store.loadState() { engine.restore(from: snapshot) }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            engine.transition(on: .appActivated(bundleID: frontmost.bundleIdentifier,
                                                name: frontmost.localizedName ?? "Unknown"))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.persist()
        monitor.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
```

Note the restore-before-seed order — reversing it overwrites the persisted session, which is the bug fixed in the previous plan.

- [ ] **Step 5: Build, run, verify**

Run: `./build.sh --test`
Expected: `Build succeeded`, 20/20 passed.

Run: `pkill -f Daybook; open Daybook.app; sleep 3; pgrep -f Daybook.app/Contents/MacOS/Daybook`
Expected: one process, one menu bar item showing the infinity glyph, clicking it shows the placeholder text, and no Dock icon.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 5: Design tokens and components

**Files:**
- Create: `Sources/Design/DesignTokens.swift`, and in `Sources/Design/Components/`: `StartButton.swift`, `LiveTimer.swift`, `StreakBadge.swift`, `StatTile.swift`, `WeekChart.swift`, `IntentField.swift`, `QuickStartRow.swift`, `ResolveCard.swift`

**Interfaces:**
- Consumes: `DayBar`, `QuickStart`, `WorkType` (Task 2).
- Produces: the eight views above, each taking plain values (no store dependency) so the gallery can drive them directly.

- [ ] **Step 1: Write `DesignTokens.swift`**

```swift
import SwiftUI

enum Tokens {
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12
        static let l: CGFloat = 16, xl: CGFloat = 24
    }
    static let popoverWidth: CGFloat = 320
    static let cardCorner: CGFloat = 10

    /// SF Pro with monospaced digits — the menu bar uses the system font.
    static let menuBarFont = Font.system(size: NSFont.systemFontSize).monospacedDigit()
    /// SF Mono — the popover's numeric hero.
    static let heroTimerFont = Font.system(size: 34, weight: .medium, design: .monospaced)
    static let statNumberFont = Font.system(size: 22, weight: .semibold, design: .monospaced)

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
```

- [ ] **Step 2: Write the components**

Each is a small `View` over plain values. `WeekChart` is the only non-trivial one:

```swift
import SwiftUI
import Charts

struct WeekChart: View {
    let bars: [DayBar]
    var height: CGFloat = 54

    var body: some View {
        Chart(bars) { bar in
            BarMark(x: .value("Day", bar.label), y: .value("Minutes", bar.minutes))
                .foregroundStyle(bar.isToday ? AnyShapeStyle(.tint)
                                             : AnyShapeStyle(.quaternary))
                .cornerRadius(3)
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks { AxisValueLabel() } }
        .frame(height: height)
        .accessibilityLabel("Focused minutes for the last seven days")
    }
}
```

`IntentField` owns Return and never blocks an empty start:

```swift
struct IntentField: View {
    @Binding var text: String
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("What are you working on?", text: $text)
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($focused)
            .onSubmit(onSubmit)
            .onAppear { focused = true }
            .accessibilityLabel("Session intent")
    }
}
```

`ResolveCard` maps to the engine's three decisions:

```swift
struct ResolveCard: View {
    let away: TimeInterval
    let onMerge: () -> Void
    let onBreak: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Away \(Tokens.duration(away))")
                .font(.headline)
            Text("Was that a break?").foregroundStyle(.secondary).font(.callout)
            HStack(spacing: Tokens.Space.s) {
                Button("Merge", action: onMerge).buttonStyle(.borderedProminent)
                Button("Break", action: onBreak)
                Button("Discard", action: onDiscard)
            }
        }
        .padding(Tokens.Space.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.cardCorner))
    }
}
```

- [ ] **Step 3: Verify it compiles with zero warnings**

Run: `./build.sh --test`
Expected: `Build succeeded`, 20/20 passed.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 6: `SessionStore` — the bridge

**Files:**
- Create: `Sources/App/SessionStore.swift`
- Modify: `Sources/App/AppCoordinator.swift`

**Interfaces:**
- Consumes: `SessionEngine`, `SessionArchive`.
- Produces: `final class SessionStore: ObservableObject` with `@Published` `state`, `elapsed`, `todayTotal`, `streak`, `weekBars`, `quickStarts`, `sessionsToday`, `longestToday`, `pendingAway`, `intent`, `workType`; methods `start()`, `startQuick(_:)`, `stop()`, `togglePause()`, `resolve(_:)`; plus `static func fixture(_:) -> SessionStore` for the gallery.

- [ ] **Step 1: Write the store**

```swift
import SwiftUI
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var todayTotal: TimeInterval = 0
    @Published private(set) var streak = 0
    @Published private(set) var weekBars: [DayBar] = []
    @Published private(set) var quickStarts: [QuickStart] = []
    @Published private(set) var sessionsToday = 0
    @Published private(set) var longestToday: TimeInterval = 0
    @Published private(set) var pendingAway: TimeInterval?
    @Published var intent: String = ""
    @Published var workType: WorkType = .deepWork

    private let engine: SessionEngine
    private var ticker: Timer?

    init(engine: SessionEngine) {
        self.engine = engine
        engine.onStateChanged = { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        engine.onNeedsDecision = { [weak self] away, _ in
            Task { @MainActor in self?.pendingAway = away }
        }
        apply(engine.state)
    }

    private func apply(_ state: SessionState) {
        self.state = state
        if case .awaitingUserDecision(let away, _) = state { pendingAway = away }
        else { pendingAway = nil }
        refresh()
        state.isRunning ? startTicker() : stopTicker()
    }

    /// Recomputes derived values. Cheap: one array pass over the archive.
    func refresh() {
        elapsed = engine.elapsed
        todayTotal = engine.archive.todayTotal() + (state == .idle ? 0 : engine.elapsed)
        streak = engine.archive.currentStreak()
        weekBars = engine.archive.weekBars()
        quickStarts = engine.archive.quickStarts(limit: 7)
        sessionsToday = engine.archive.sessionsToday()
        longestToday = engine.archive.longestToday()
    }
}
```

The ticker is the cosmetic timer from the original spec: 1s while a popover is open is wasteful, so it runs at 1s only while `state.isRunning` **and** a surface is visible, and is invalidated otherwise. Views call `store.refresh()` in `onAppear`.

Actions:

```swift
func start() {
    engine.start(workType: workType, intent: intent)
    intent = ""
}

func startQuick(_ quick: QuickStart) {
    engine.start(workType: quick.workType, intent: quick.name)
}

func stop() { engine.stop() }

func togglePause() {
    let resumable = !engine.state.isRunning && engine.state != .idle
    engine.transition(on: resumable ? .manualResume : .manualPause)
}

func resolve(_ decision: UserDecision) {
    engine.transition(on: .decision(decision))
}
```

- [ ] **Step 2: Wire it in `AppCoordinator`**

Add `lazy var store = SessionStore(engine: engine)` and pass it into the scenes via `.environmentObject(coordinator.store)`.

- [ ] **Step 3: Verify**

Run: `./build.sh --test`
Expected: `Build succeeded`, 20/20 passed.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 7: Popover surface

**Files:**
- Create: `Sources/Surfaces/PopoverView.swift`
- Modify: `Sources/App/DaybookApp.swift`

**Interfaces:**
- Consumes: `SessionStore`, all Task 5 components.
- Produces: `PopoverView` and the menu bar label view.

- [ ] **Step 1: Build the three zones**

```swift
struct PopoverView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            header
            hero
            if !store.quickStarts.isEmpty { QuickStartRow(items: store.quickStarts) { store.startQuick($0) } }
            footer
        }
        .padding(Tokens.Space.l)
        .frame(width: Tokens.popoverWidth)
        .background(.ultraThinMaterial)
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack {
            Text(Tokens.duration(store.todayTotal)).foregroundStyle(.secondary)
            Spacer()
            StreakBadge(days: store.streak)
        }
        .font(.callout)
    }

    @ViewBuilder private var hero: some View {
        if let away = store.pendingAway {
            ResolveCard(away: away,
                        onMerge: { store.resolve(.mergeTime) },
                        onBreak: { store.resolve(.continueSession) },
                        onDiscard: { store.resolve(.resetTimer) })
        } else if store.state == .idle {
            IntentField(text: $store.intent) { store.start() }
            StartButton(title: "Start Focus") { store.start() }
        } else {
            LiveTimer(seconds: store.elapsed, paused: store.state.isPaused)
            HStack {
                Button(store.state.isPaused ? "Resume" : "Pause") { store.togglePause() }
                Button("Stop") { store.stop() }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            WeekChart(bars: store.weekBars)
            Divider()
            Button("Open Dashboard") { NSApp.sendAction(#selector(AppCoordinator.openToday), to: nil, from: nil) }
                .buttonStyle(.link)
                .keyboardShortcut("d")
        }
    }
}
```

- [ ] **Step 2: Replace the placeholder in the scene**

```swift
MenuBarExtra {
    PopoverView().environmentObject(coordinator.store)
} label: {
    MenuBarLabel(state: coordinator.store.state, elapsed: coordinator.store.elapsed)
}
.menuBarExtraStyle(.window)
```

`MenuBarLabel` renders the four ambient states from the spec: glyph only when idle, glyph plus `Tokens.duration` when running, `⏸` prefix and secondary colour when paused, and a badge when `pendingAway != nil`.

- [ ] **Step 3: Verify by running**

Run: `./build.sh --run`
Expected: clicking the menu bar item shows the popover with a focused text field; typing and pressing Return starts a session; the menu bar shows elapsed time; Stop writes a record and the weekly chart updates.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 8: Today window

**Files:**
- Create: `Sources/Surfaces/TodayView.swift`
- Modify: `Sources/App/DaybookApp.swift`, `Sources/App/AppCoordinator.swift`

**Interfaces:**
- Consumes: `SessionStore`, Task 5 components.
- Produces: `TodayView`; `AppCoordinator.openToday()`.

- [ ] **Step 1: Build the view**

Hero (large start control or live timer), `WeekChart` at 120pt, then a four-column `LazyVGrid` of `StatTile`: today's focused time, current streak, sessions completed today, longest session today. Plain `Window`, not `NavigationSplitView` — there is exactly one destination in slice 1.

```swift
Window("Today", id: "today") {
    TodayView().environmentObject(coordinator.store)
}
.defaultSize(width: 720, height: 520)
.windowResizability(.contentMinSize)
```

- [ ] **Step 2: Open it from the popover and from the Dock-less app**

```swift
@objc func openToday() {
    NSApp.activate(ignoringOtherApps: true)
    openWindowAction?("today")
}
```

`openWindowAction` is set once from a `@Environment(\.openWindow)` value captured in `TodayView`'s parent scene, because `openWindow` is unavailable from an `NSApplicationDelegate`.

- [ ] **Step 3: Verify**

Run: `./build.sh --run`, click `Open Dashboard`.
Expected: the window opens, shows the same numbers as the popover, resizes gracefully, and both light and dark appearances are correct (toggle System Settings → Appearance).

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 9: `--gallery` state catalogue

**Files:**
- Create: `Sources/Surfaces/GalleryView.swift`
- Modify: `Sources/App/DaybookApp.swift`, `Sources/App/SessionStore.swift`

**Interfaces:**
- Consumes: `PopoverView`, `TodayView`, `SessionStore.fixture(_:)`.
- Produces: `GalleryView`; `SessionStore.Fixture` enum.

- [ ] **Step 1: Add fixtures to the store**

```swift
enum Fixture: String, CaseIterable {
    case firstRun, idleWithHistory, running, paused, needsResolution, brokenStreak
}

static func fixture(_ kind: Fixture) -> SessionStore { /* builds an in-memory engine
   pointed at a temporary directory, populated to match the state */ }
```

Fixtures must use a temporary directory, never the real archive.

- [ ] **Step 2: Build the gallery**

A `ScrollView` of every fixture rendered twice — `.preferredColorScheme(.light)` and `.preferredColorScheme(.dark)` — each labelled, popover and Today side by side.

- [ ] **Step 3: Gate it in `main()`**

```swift
if CommandLine.arguments.contains("--gallery") {
    GalleryApp.main()
    return
}
```

- [ ] **Step 4: Verify**

Run: `./build.sh && ./Daybook.app/Contents/MacOS/Daybook --gallery`
Expected: a window showing all six states in both appearances, no real user data touched.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 10: Non-blocking idle resolution

**Files:**
- Create: `Sources/Core/Notifier.swift`
- Modify: `Sources/App/AppCoordinator.swift`, `Sources/App/SessionStore.swift`

**Interfaces:**
- Consumes: Task 1's notification answer.
- Produces: `final class Notifier` with `requestAuthorization()`, `postAwayResolution(away:)`, `var isAvailable: Bool`.

- [ ] **Step 1: Implement the wrapper**

Every call is guarded so an unavailable notification centre is a silent no-op, never a crash:

```swift
import UserNotifications

final class Notifier {
    private(set) var isAvailable = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            [weak self] granted, error in
            self?.isAvailable = granted && error == nil
            if let error { Diagnostics.log("notification authorisation failed: \(error)") }
        }
    }

    func postAwayResolution(away: TimeInterval) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Away \(Tokens.duration(away))"
        content.body = "Was that a break?"
        content.categoryIdentifier = "away-resolution"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "away-\(UUID().uuidString)",
                                  content: content, trigger: nil))
    }
}
```

`Tokens` lives in `Design/`, which `Core/` may not import — so `Notifier` takes a pre-formatted string instead: `postAwayResolution(text: String)`. Fix this when implementing rather than importing upward.

- [ ] **Step 2: Wire it**

`AppCoordinator` requests authorisation on first launch only, and posts when `onNeedsDecision` fires. The resolve card already appears in the popover from Task 7, so the notification is purely an additional affordance.

- [ ] **Step 3: Verify**

Run the app, start a session, lock the screen for longer than the threshold, unlock.
Expected: no window steals focus; the menu bar shows the attention badge; if notifications are available a banner appears; opening the popover shows the resolve card; each button produces the right `workSeconds` in the archive.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 11: Global hotkey — **only if Task 1 Step 4 succeeded**

**Files:**
- Create: `Sources/Core/HotKeyMonitor.swift`
- Modify: `Sources/App/AppCoordinator.swift`

**Interfaces:**
- Produces: `final class HotKeyMonitor` with `register(onFire: @escaping () -> Void)`, `unregister()`.

- [ ] **Step 1: Implement the Carbon wrapper**

`RegisterEventHotKey` for ⌃⌥Space with an `InstallEventHandler` trampoline, storing the callback in a static box because Carbon takes a C function pointer. `unregister()` in `deinit`.

- [ ] **Step 2: Wire to the popover**

Firing toggles the `MenuBarExtra` popover open and focuses the intent field.

- [ ] **Step 3: Verify**

Press ⌃⌥Space with another app frontmost.
Expected: the popover opens focused, no Accessibility prompt appears, and `tccutil` shows no new grant.

If registration fails because another app owns the combination, log it and continue — the feature is absent, nothing else breaks.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 12: Final verification

**Files:** none — measurement only.

- [ ] **Step 1: Full suite**

Run: `./build.sh --test`
Expected: `Build succeeded`, all tests pass, zero warnings.

- [ ] **Step 2: Gallery review**

Run: `./Daybook.app/Contents/MacOS/Daybook --gallery`
Expected: all six states correct in both appearances; no clipped text, no white boxes in dark mode, no hardcoded colours.

- [ ] **Step 3: Idle cost**

Run the app, leave it idle 60s, then `ps -o %cpu,rss -p $(pgrep -f Daybook)` and `footprint -p <pid>`.
Expected: 0.0% CPU idle; `phys_footprint` under 60 MB (SwiftUI and Charts cost more than the AppKit build's 12 MB — the original 25 MB budget was set for a menu-only app and is recorded as superseded here).

- [ ] **Step 4: Accessibility pass**

Enable Reduce Motion and Increase Contrast in System Settings; confirm animations degrade to cross-fades and contrast holds. Tab through the popover; confirm every control is reachable and labelled.

- [ ] **Step 5: Manual loop test**

Start from the menu bar with an intent, work 2 minutes, lock the screen 20s, unlock (expect silence), stop. Confirm the record's `workSeconds` excludes the lock, today's total rises, the weekly chart updates, and the streak reflects the 25-minute rule.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*
