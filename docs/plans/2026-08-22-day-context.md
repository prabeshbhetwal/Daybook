# Day Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dashboard follow the selected day and the selected session — a Sessions card, a collapsed Now strip on past days, cross-highlighting between sessions, apps and the timeline, hover data on every chart — so the page reads as one dynamic instrument rather than a set of static cards.

**Architecture:** The store already publishes `daySessions`, `selectedSession`, `hoveredSession`, `highlightedBundleID`, `sessionAppRanks`, `sessionTracked`, `selectedDaySummary`, `framedSession`, `selectSession/clearSession/hoverSession/highlightApp/selectHour` (built before this plan; tests 91–92). This plan is the views: a `SessionsCard`, a `NowStrip` branch in `DashboardHero`, framing and app-highlighting in `DayTimelineView`, hover/click on `RhythmChart` and `PeriodChart`, the layout in `DashboardView`, and the "App usage" rename.

**Tech Stack:** Swift 5, SwiftUI (+ Charts), AppKit. `swiftc` via `./build.sh`. macOS 13.

**Spec:** the design canvas `docs/superpowers/design/2026-08-22-day-context/` (Main + SessionSelected artboards, annotations), approved in chat.

## Global Constraints

- Not a git repository; commit steps recorded, skipped. No `@State`/`@Observable`; `ObservableObject` + `@Published`. `Sources/Core` imports Foundation/CoreGraphics only. One repeating `Timer`. No new TCC, no packages, no warnings. Never delete — `_trash/`. Files under 500 lines.
- Build/test: `./build.sh 2>&1 | grep -E "error|warning|Build succeeded"` then `./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`. Snapshot dir: `/private/tmp/claude-501/-Users-prabeshbhetwal-Desktop-Files-Development-Project-FocusContinuity/d9e74462-42ba-4aac-8014-68ac6cc6464b/scratchpad/snaps`. Relaunch: `pkill -x FocusContinuity; sleep 1; open FocusContinuity.app`.
- Tokens: `Tokens.Surface.*`, `Tokens.Palette.*`, `Tokens.Typography.*`, `Tokens.Radius.*`, `.card()`, `SectionHeader`, `IconButton`, `HoverBox`.

---

### Task 1: Sessions card, Timeline card, "App usage"

**Files:**
- Create: `Sources/Surfaces/Dashboard/DashboardSessions.swift`
- Modify: `Sources/Surfaces/Dashboard/DashboardView.swift`, `Sources/Surfaces/Dashboard/PeriodViews.swift` (`SessionLogList` header title)

**Interfaces:**
- Produces: `SessionsCard(entries: [DayEntry], selected: DaySession?, onHover: (DaySession?) -> Void, onSelect: (DaySession) -> Void)`.
- Consumes: `store.daySessions`, `store.selectedSession`, `store.hoverSession(_:)`, `store.selectSession(_:)`.

- [ ] **Step 1: Create `DashboardSessions.swift`**

```swift
import SwiftUI

/// The selected day's focus sessions as rows, with the rests between them
/// inline — the card the dashboard was missing. Hover a row to frame it on
/// the timeline; click to narrow the page to it.
struct SessionsCard: View {
    let entries: [DayEntry]
    var selected: DaySession?
    let onHover: (DaySession?) -> Void
    let onSelect: (DaySession) -> Void
    @StateObject private var hover = HoverBox()

    private var sessions: [DaySession] {
        entries.compactMap { if case .session(let s) = $0 { return s } else { return nil } }
    }
    private var rests: Int { entries.filter { if case .rest = $0 { return true } else { return false } }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: "Sessions", trailing: trailing)
                .padding(.bottom, Tokens.Space.xs)
            if entries.isEmpty {
                Text("No focus sessions this day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Tokens.Space.s)
            }
            ForEach(entries) { entry in
                switch entry {
                case .session(let session): row(session)
                case .rest(let rest): restRow(rest)
                }
            }
        }
    }

    private var trailing: String? {
        guard !sessions.isEmpty else { return nil }
        var parts = [sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"]
        if rests > 0 { parts.append(rests == 1 ? "1 break" : "\(rests) breaks") }
        return parts.joined(separator: " · ")
    }

    private func row(_ session: DaySession) -> some View {
        let isSelected = selected?.id == session.id
        let dimmed = selected != nil && !isSelected
        let hovered = hover.id == session.id.uuidString
        return Button { onSelect(session) } label: {
            HStack(alignment: .center, spacing: Tokens.Space.m) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Tokens.Palette.workType(session.workType))
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tokens.timeRange(session.start, session.end))
                        .font(Tokens.Typography.row.weight(.medium).monospacedDigit())
                    Text(stretchLine(session))
                        .font(Tokens.Typography.detail)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 150, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Tokens.Space.xs) {
                        Text(session.name.isEmpty ? session.workType.displayName : session.name)
                            .font(Tokens.Typography.row.weight(.medium))
                            .lineLimit(1)
                        if session.isRunning {
                            Text("running")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(session.workType.displayName)
                        .font(Tokens.Typography.detail)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Tokens.preciseDuration(session.worked))
                    .font(Tokens.Typography.row.weight(.medium).monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, Tokens.Space.s)
            .background(hovered && !isSelected ? Tokens.Surface.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5))
            .opacity(dimmed ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hover.id = inside ? session.id.uuidString : nil
            onHover(inside ? session : nil)
        }
        .help(isSelected ? "Click again to show the whole day" : "Click to narrow the page to this session")
        .accessibilityLabel("\(Tokens.timeRange(session.start, session.end)), "
                            + "\(session.name.isEmpty ? session.workType.displayName : session.name), "
                            + Tokens.spent(session.worked))
    }

    private func stretchLine(_ session: DaySession) -> String {
        let stretches = session.stretches == 1 ? "1 stretch" : "\(session.stretches) stretches"
        let breaksInside = max(0, session.stretches - 1)
        return breaksInside == 0 ? stretches
            : "\(stretches) · \(breaksInside == 1 ? "1 break" : "\(breaksInside) breaks")"
    }

    /// A rest between sessions, drawn as a labelled rule so the day's shape
    /// reads top to bottom without a second column.
    private func restRow(_ rest: RestEntry) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Text(Tokens.timeRange(rest.start, rest.end))
                .font(Tokens.Typography.detail.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 150, alignment: .leading)
            Rectangle().fill(Tokens.Surface.hairline).frame(height: 1)
            Text("\(rest.name) · \(Tokens.preciseDuration(rest.length))")
                .font(Tokens.Typography.detail)
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle().fill(Tokens.Surface.hairline).frame(height: 1)
        }
        .padding(.horizontal, Tokens.Space.s)
        .padding(.vertical, 2)
        .accessibilityLabel("\(rest.name), \(Tokens.spent(rest.length))")
    }
}
```

- [ ] **Step 2: Lay it into the dashboard.** In `DashboardView.column`, replace the line `chartRow` … through `sessionLogSection` with:

```swift
            chartRow
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                SessionsCard(entries: store.daySessions, selected: store.selectedSession,
                             onHover: { store.hoverSession($0) },
                             onSelect: { store.selectSession($0) })
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .card(padding: Tokens.Space.m)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1.3)
                if store.period == .day {
                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        SectionHeader(title: "Timeline",
                                      trailing: store.framedSession == nil ? "hover a session to light it up" : nil)
                        DayTimelineView(store: store)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .card()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                appShareCard
                workTypeCard
                insightsCard
            }
            .fixedSize(horizontal: false, vertical: true)
            sessionLogSection
```

and in `chartRow` remove the `DayTimelineView` from the Day branch's old place: the Day branch keeps the Rhythm chart only (it already does). In `SessionLogList` (`PeriodViews.swift`) change `SectionHeader(title: "Session log",` to `SectionHeader(title: "App usage",`.

- [ ] **Step 3: Build, test, snapshot** — `Build succeeded`, `92/92`; open `dashboard-running-dark.png`: a Sessions card with rows and an inline break beside a Timeline card; the log card reads APP USAGE.
- [ ] **Step 4: Commit** *(recorded, skipped)*

---

### Task 2: Now strip on past days; title band for the selected day

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DashboardHero.swift`, `Sources/Surfaces/Dashboard/DashboardView.swift`

- [ ] **Step 1:** In `DashboardHero.body`, wrap the existing `HStack … .card(padding: Tokens.Space.l)` as the `else` of:

```swift
        if !store.isToday {
            nowStrip
        } else {
            <existing HStack>
        }
```

and add:

```swift
    /// On any day but today the hero folds to one line: a small ring, the
    /// stretch clock, what is running, today's goal — and the way back. A past
    /// day can then never be mistaken for now.
    private var nowStrip: some View {
        HStack(spacing: Tokens.Space.m) {
            GoalRing(progress: store.goal.share, diameter: 28, lineWidth: 4, isMet: store.goal.isMet)
            SectionHeader(title: "Now").fixedSize()
            if store.isIdle {
                Text("No session running")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(Tokens.clock(store.elapsed))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(store.threadSummaryLine.map { "\(store.activeIntent) · \($0)" } ?? store.activeIntent)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.s)
            Text("Today: \(Tokens.duration(store.goal.achieved)) of \(Tokens.duration(store.goal.goal))")
                .font(Tokens.Typography.detail)
                .foregroundStyle(.secondary)
            Button("Back to today") { store.goToToday() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, Tokens.Space.m)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .card(padding: Tokens.Space.m)
    }
```

- [ ] **Step 2:** In `DashboardView.subtitle`, return `store.selectedDaySummary` when `!store.isToday` (keep the today branch). Remove the `store.isToday ? … : nil` goal ring from `chartRow`? No — keep: the goal card already hides on past days.
- [ ] **Step 3:** Build, test, snapshot `dashboard-idleWithHistory-dark.png` (today) unchanged; relaunch and step back a day: a one-line Now strip and the title reads the day. Commit *(skipped)*.

---

### Task 3: Timeline framing, app highlight, session chip, Esc

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DayTimelineView.swift`, `Sources/Surfaces/Dashboard/DashboardSections.swift` (`TopAppsList`), `Sources/Surfaces/Dashboard/DashboardView.swift`

- [ ] **Step 1: Timeline frames and highlights.** In `DayTimelineView.band`'s `Canvas`, before the segment loop add:

```swift
                let framed = layoutOverride == nil ? store.framedSession : nil
                let highlight = layoutOverride == nil ? store.highlightedBundleID : nil
```

Change the segment fill opacity expression to:

```swift
                    let insideFrame = framed.map { s in s.spans.contains { $0.start < segment.end && $0.end > segment.start } } ?? true
                    let matchesApp = highlight.map { $0 == segment.bundleID } ?? true
                    let emphasis: Double = (insideFrame && matchesApp) ? (isFocused ? 1 : 0.92) : 0.22
                    context.fill(Path(roundedRect: rect, cornerRadius: Tokens.Radius.swatch),
                                 with: .color(TimelinePalette.color(segment.colorIndex).opacity(emphasis)))
```

After the segment loop, draw the frame:

```swift
                if let framed {
                    for span in framed.spans {
                        guard let startX = layout.fraction(for: span.start),
                              let endX = layout.fraction(for: span.end) else { continue }
                        let rect = CGRect(x: startX * size.width - 3, y: -3,
                                          width: max(6, (endX - startX) * size.width + 6),
                                          height: bandHeight + 6)
                        context.stroke(Path(roundedRect: rect, cornerRadius: 7),
                                       with: .color(.accentColor.opacity(store.selectedSession != nil ? 1 : 0.6)),
                                       lineWidth: 1.5)
                    }
                }
```

Keep `.opacity(isFocused ? 1 : 0.92)` usage removed (replaced above).

- [ ] **Step 2: App rows highlight the timeline.** In `TopAppsList.expandableRow`, change `.onHover { hover.id = $0 ? app.bundleID : nil }` to `.onHover { inside in hover.id = inside ? app.bundleID : nil; store?.highlightApp(inside ? app.bundleID : nil) }`.

- [ ] **Step 3: Session chip and Esc.** In `DashboardView.appShareCard`, when `store.selectedSession != nil` pass `trailingOverride: nil` and add a header chip: wrap the `TopAppsList` in a `VStack` whose first row is

```swift
                    if let session = store.selectedSession {
                        HStack {
                            Spacer()
                            Button { store.clearSession() } label: {
                                HStack(spacing: Tokens.Space.xs) {
                                    Text("Session · \(Tokens.timeRange(session.start, session.end))")
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, Tokens.Space.s).padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            .help("Show the whole day again (Esc)")
                        }
                    }
```

and on `column` add `.onExitCommand { store.clearSession() }`.

- [ ] **Step 4:** Build, test; relaunch; hover a session → timeline frames; click → App share narrows and the chip appears; Esc clears. Commit *(skipped)*.

---

### Task 4: Rhythm click, period chart hover and click

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DashboardCharts.swift` (`RhythmChart`), `Sources/Surfaces/Dashboard/PeriodViews.swift` (`PeriodChart`), `Sources/Surfaces/Dashboard/DashboardView.swift`

- [ ] **Step 1: Rhythm.** `RhythmChart` gains `var onHourTap: ((Date) -> Void)?`; each bar gets `.contentShape(Rectangle()).onTapGesture { onHourTap?(hour.hour) }`. In `DashboardView.chartRow` pass `onHourTap: { store.selectHour($0) }`.

- [ ] **Step 2: Period chart hover + click.** `PeriodChart` gains `var onPickDay: ((Date) -> Void)?` and a hovered-day box:

```swift
private final class DayBox: ObservableObject { @Published var day: Date? }
```

Inside `Chart { … }` add, after the RuleMark, a `.chartOverlay { proxy in GeometryReader { geo in Rectangle().fill(.clear).contentShape(Rectangle())
    .onContinuousHover { phase in switch phase { case .active(let p): hovered.day = dayAt(p, proxy, geo); case .ended: hovered.day = nil } }
    .onTapGesture { location in if let day = dayAt(location, proxy, geo) { onPickDay?(day) } } } }`
with

```swift
    private func dayAt(_ point: CGPoint, _ proxy: ChartProxy, _ geo: GeometryProxy) -> Date? {
        let x = point.x - geo[proxy.plotAreaFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return days.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.date
    }
```

and an overlay label at the top-leading: `if let day = hovered.day, let entry = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) { Text("\(Tokens.dayLabel(day)) · \(Tokens.duration(entry.tracked)) tracked").font(Tokens.Typography.detail).padding(6).background(.regularMaterial, in: Capsule()) }`. In `DashboardView.chartRow` pass `onPickDay: { store.selectDate($0); store.period = .day }`.

- [ ] **Step 3:** Build, test; relaunch; Week view: hover a bar → label; click → Day on that date. Commit *(skipped)*.

---

### Task 5: Cross-fade, harness, spec note, checks

- [ ] **Step 1:** In `DashboardView.column` add `.animation(.easeInOut(duration: 0.25), value: store.dayOffset)` and `.animation(.easeInOut(duration: 0.2), value: store.selectedSession?.id)`.
- [ ] **Step 2:** Gallery strip: add `SessionsCard(entries: …fixture…, selected: nil, onHover: { _ in }, onSelect: { _ in }).frame(width: 520).card(padding: 12)` with two sessions and one rest built from `Date()`.
- [ ] **Step 3:** Append to `docs/superpowers/specs/2026-08-22-premium-design-design.md` an addendum "Day context (2026-08-22, later)" summarising §1–4 of the canvas and naming the new store members and views.
- [ ] **Step 4:** Build, `92/92`, snapshots opened; relaunch; live: pick a past day (Now strip), hover/click sessions, Esc, rhythm click, week chart hover/click. Files under 500.
