import Foundation
import SwiftUI
import AppKit

/// Focused contracts for the compact-control presentation batch. Expectations
/// are derived from the supported 980pt and 1,160pt window widths and from the
/// actual usable display passed to the menu-bar sizing boundary.
enum CompactControlsChecks {
    static let tests: [(String, () -> [String])] = [
        ("Focus routes reveal controls without changing reading context", focusRoute),
        ("Pill toggles while command routes always reveal through one action boundary",
         sessionControlActionRouting),
        ("Pinned controls survive relaunch without mutating the session", pinPersistence),
        ("Menu-bar controls remain a clamped single column", popoverBounds),
        ("Popover owns one real overflow region and excludes current continuations", popoverComposition),
        ("Settings keeps one bounded frame across pages and search", settingsFrame),
        ("Settings fixtures retain a real editable search field", settingsSearchField),
        ("Month remains compact when the Story column grows wider", monthHeight),
        ("Month duration consumers keep short and invalid evidence factual", monthDurationText),
        ("Rail ordering is gated, one-step and deliberately dismissible", railArrangement),
        ("Scope keyboard commands move one coherent selection", scopeKeyboard),
        ("Native scope adapter owns focus, pointer and key selection", nativeScopeAdapter),
        ("Every scope row presents one native keyboard target", scopeRowsShareOneKeyboardTarget),
        ("One session control is offered at a time", oneSessionControlAtATime),
        ("The session strip is one row whose chrome sits with its controls",
         sessionStripIsOneRow),
        ("The type scale stays a scale", typeScaleHoldsItsShape),
        ("Compact Focus consumers retain general save failures and exact Retry", generalFailurePresentation),
        ("Away Return routing is scoped to its own focused controls", awayReturnScope),
        ("Away answers keep their size on a window a manager resized",
         awayAnswersIgnoreWindowHeight),
        ("Compact goal copy stays quiet at the 340pt menu width", compactGoalLine)
    ]

    private static func focusRoute() -> [String] {
        MainActor.assumeIsolated {
            let navigation = MainWindowModel(storyScope: .month)
            let workspace = navigation.workspace
            let scope = navigation.storyScope

            navigation.openSheet(.focus)

            var failures: [String] = []
            if navigation.sheet != nil {
                failures.append("Opening session controls still presents a Focus sheet")
            }
            if navigation.workspace != workspace || navigation.storyScope != scope {
                failures.append("Opening session controls changed the Month reading context")
            }
            navigation.dismissSessionControls()
            if navigation.focusRestorationRequest != .sessionControls {
                failures.append("Dismissing the strip did not request focus for its timer pill")
            }
            navigation.consumeFocusRestorationRequest()
            navigation.openSettings()
            navigation.closeSheet()
            if navigation.focusRestorationRequest != .settings {
                failures.append("Closing Settings did not request focus for its invoking control")
            }
            return failures
        }
    }

    private static func sessionControlActionRouting() -> [String] {
        MainActor.assumeIsolated {
            let navigation = MainWindowModel()
            var failures: [String] = []
            navigation.performSessionControlsAction(.timerPill)
            if !navigation.sessionControlsExpanded {
                failures.append("First timer-pill activation did not reveal the strip")
            }
            navigation.performSessionControlsAction(.timerPill)
            if navigation.sessionControlsExpanded {
                failures.append("Second timer-pill activation did not collapse the unpinned strip")
            }
            navigation.performSessionControlsAction(.commandOrMenu)
            if !navigation.sessionControlsExpanded {
                failures.append("Command route did not reveal a hidden strip")
            }
            navigation.performSessionControlsAction(.commandOrMenu)
            if !navigation.sessionControlsExpanded {
                failures.append("Repeated command route toggled an already-visible strip closed")
            }
            return failures
        }
    }

    private static func pinPersistence() -> [String] {
        MainActor.assumeIsolated {
            let suite = "com.prabesh.focuscontinuity.compact-pin.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                return ["Could not create isolated pin defaults"]
            }
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let stateBefore = store.engine.state
            let settings = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            settings.sessionControlsPinned = true

            let reloaded = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let navigation = MainWindowModel(storyScope: .week, store: store)
            var failures: [String] = []
            if !reloaded.sessionControlsPinned
                || !SessionControlsVisibility.isVisible(
                    expanded: navigation.sessionControlsExpanded,
                    pinned: reloaded.sessionControlsPinned) {
                failures.append("A persisted pin did not reveal controls after model relaunch")
            }
            if navigation.sessionControlsExpanded {
                failures.append("Ordinary launch expanded the transient session-controls state")
            }
            if store.engine.state != stateBefore {
                failures.append("Writing or reading the pin changed the running session")
            }
            return failures
        }
    }

    private static func popoverBounds() -> [String] {
        var failures: [String] = []
        let large = PopoverMetrics.fitting(CGSize(width: 1_440, height: 900))
        if large.width != 340 || large.twoColumn {
            failures.append("A large display produced a \(Int(large.width))pt, "
                            + "\(large.twoColumn ? "two-column" : "single-column") panel")
        }

        let smallSize = CGSize(width: 312, height: 420)
        let small = PopoverMetrics.fitting(smallSize)
        if small.width > smallSize.width || small.maxHeight > smallSize.height {
            failures.append("Small-display metrics escaped the supplied usable geometry")
        }
        if small.twoColumn {
            failures.append("Small-display metrics enabled a second column")
        }
        return failures
    }

    private static func popoverComposition() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refresh()
            let settings = SettingsModel(store: store.engine.store,
                                         isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let metrics = PopoverMetrics.fitting(CGSize(width: 1_000, height: 680))
            let host = NSHostingView(rootView: PopoverView(store: store,
                                                          settings: settings,
                                                          metricsOverride: metrics,
                                                          scrolls: true))
            host.frame = NSRect(x: 0, y: 0, width: metrics.width, height: metrics.maxHeight)
            host.layoutSubtreeIfNeeded()
            let scrollRegions = descendantCount(in: host) { $0 is NSScrollView }
            var failures: [String] = []
            if scrollRegions != 1 {
                failures.append("The compact popover rendered \(scrollRegions) overflow regions instead of one")
            }
            let active = store.engine.activeThreadID
            let rows = FocusContinuationSource.rows(threads: store.continuableThreads,
                                                     quickStarts: store.quickStarts,
                                                     limit: 3)
            if rows.contains(where: { row in
                if case .thread(let thread) = row { return thread.id == active || thread.isRunning }
                return false
            }) {
                failures.append("Continue duplicated the current running session")
            }
            // Running, a quick start for the very activity in progress is not
            // something to switch to.
            let current = (name: store.activeIntent, workType: store.workType)
            let running = FocusContinuationSource.rows(
                threads: [], quickStarts: [QuickStart(id: "same", name: current.name, workType: current.workType),
                                           QuickStart(id: "other", name: "Other", workType: current.workType)],
                limit: 3, excluding: current)
            if running.contains(where: { row in
                if case .quickStart(let quick) = row {
                    return quick.name.caseInsensitiveCompare(current.name) == .orderedSame
                }
                return false
            }) || running.count != 1 {
                failures.append("The switch list offered the activity already running")
            }
            return failures
        }
    }

    @MainActor private static func descendantCount(in view: NSView,
                                                    matching: (NSView) -> Bool) -> Int {
        (matching(view) ? 1 : 0)
            + view.subviews.reduce(0) { $0 + descendantCount(in: $1, matching: matching) }
    }

    private static func settingsFrame() -> [String] {
        var failures: [String] = []
        let normal = SettingsSection.allCases.map {
            SettingsLayout.sheetHeight(section: $0, query: "")
        }
        let searched = SettingsSection.allCases.map {
            SettingsLayout.sheetHeight(section: $0, query: "privacy")
        }
        let all = normal + searched
        if Set(all).count != 1 {
            failures.append("Settings still changes height between category or search states: \(all)")
        }
        if let height = all.first, height > SettingsLayout.sheetMaximumHeight {
            failures.append("Settings exceeds its \(Int(SettingsLayout.sheetMaximumHeight))pt title-inclusive height bound")
        }
        return failures
    }

    private static func settingsSearchField() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let navigation = MainWindowModel(store: store)
            let settings = SettingsModel(store: store.engine.store,
                                         isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let host = NSHostingView(rootView: SettingsView(model: settings,
                                                            navigation: navigation,
                                                            scrolls: false)
                .frame(width: SettingsLayout.sheetWidth, height: 600))
            host.frame = NSRect(x: 0, y: 0, width: SettingsLayout.sheetWidth, height: 600)
            host.layoutSubtreeIfNeeded()
            return containsTextInput(host) ? []
                : ["The non-scrolling Settings fixture replaced Search with static text"]
        }
    }

    @MainActor private static func containsTextInput(_ view: NSView) -> Bool {
        if view is NSTextField { return true }
        return view.subviews.contains(where: containsTextInput)
    }

    private static func monthHeight() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview(period: .month)
            let navigation = MainWindowModel(storyScope: .month, store: store)

            @MainActor func renderedHeight(width: CGFloat) -> CGFloat {
                let view = MonthStoryGrid(store: store, navigation: navigation)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                return renderer.nsImage?.size.height ?? .infinity
            }

            let minimum = renderedHeight(width: 600)
            let comfortable = renderedHeight(width: 780)
            var failures: [String] = []
            if !minimum.isFinite || !comfortable.isFinite {
                failures.append("Month could not be rendered at both supported Story widths")
            } else if comfortable > minimum + 8 {
                failures.append("Widening Month increased its height from "
                                + "\(Int(minimum))pt to \(Int(comfortable))pt")
            }
            if max(minimum, comfortable) > 500 {
                failures.append("Six-row Month leaves too little room for its inline story")
            }
            return failures
        }
    }

    private static func monthDurationText() -> [String] {
        var failures: [String] = []
        if MonthStoryLayout.durationLabel(for: 31) != "31s" {
            failures.append("A 31-second Month cell was rounded to a whole-minute label")
        }
        for value in [TimeInterval.nan, .infinity, -.infinity, -1] {
            if MonthStoryLayout.durationLabel(for: value) != "—" {
                failures.append("An invalid Month-cell duration was presented as ordinary time")
                break
            }
        }
        return failures
    }

    private static func railArrangement() -> [String] {
        let original = StoryTileKind.allCases
        let arrangement = StoryRailArrangement(order: original)
        var failures: [String] = []
        if arrangement.allowsDrag || arrangement.move(.apps, by: -1)
            || arrangement.order != original {
            failures.append("Ordinary reading mode accepted a tile reorder")
        }
        arrangement.begin()
        if !arrangement.allowsDrag || !arrangement.move(.apps, by: -1)
            || arrangement.order != [.focus, .apps, .mac, .rhythm, .streak] {
            failures.append("Arranging mode did not move Apps exactly one position")
        }
        arrangement.finish()
        if arrangement.isArranging || arrangement.move(.apps, by: -1) {
            failures.append("Finish arranging did not gate subsequent movement")
        }
        arrangement.begin()
        arrangement.escape()
        if arrangement.isArranging {
            failures.append("Escape did not finish arranging")
        }
        arrangement.begin()
        arrangement.reset()
        if arrangement.order != StoryTileKind.allCases {
            failures.append("Reset did not restore the shipped tile order")
        }
        let suite = "com.prabesh.focuscontinuity.rail-order.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suite) {
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            let settings = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            arrangement.finish()
            arrangement.begin()
            _ = arrangement.move(.apps, by: -1)
            settings.storyTileOrder = arrangement.order
            let reloaded = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            if reloaded.storyTileOrder != arrangement.order {
                failures.append("The production Settings boundary did not persist arranged order")
            }
        } else {
            failures.append("Could not create isolated rail-order defaults")
        }
        return failures
    }

    /// A scale earns its steps. Nineteen ad-hoc sizes, with four doing one
    /// job and five more sitting a point apart, is a list rather than a
    /// hierarchy: sizes that close together do no perceptual work, so the
    /// reader cannot tell what outranks what.
    private static func typeScaleHoldsItsShape() -> [String] {
        var failures: [String] = []
        let steps = Tokens.Typography.Size.all
        if steps != steps.sorted() {
            failures.append("The type scale is not declared in ascending order")
        }
        if Set(steps).count != steps.count {
            failures.append("The type scale repeats a step")
        }
        if steps.count > 12 {
            failures.append("The type scale has grown to \(steps.count) steps")
        }
        // Adjacent steps must differ enough to be seen as different. One point
        // at reading size is not a hierarchy, it is noise.
        for (small, large) in zip(steps, steps.dropFirst()) {
            let ratio = large / small
            if ratio < 1.08 {
                failures.append("Steps \(small) and \(large) are too close to tell apart")
            }
        }
        if steps.first ?? 0 < 9 {
            failures.append("The smallest step fell below legible micro-text")
        }
        return failures
    }

    /// Two buttons reading "Start focus" — one revealing the strip, one
    /// starting the session — is the same words for two different acts.
    /// The strip is the window's toolbar. Stacked, it stood 225pt tall in a
    /// 680pt window and pushed Pin and Close 468pt from the controls they
    /// govern — 1,088pt at 1,600. This pins the row: bounded height that does
    /// not grow with width, chrome on the same band as the content, and every
    /// control at or above the target floor the rest of the app holds to.
    private static func sessionStripIsOneRow() -> [String] {
        MainActor.assumeIsolated {
            struct Measured {
                var height: CGFloat = 0
                var controls: [(name: String, rect: NSRect)] = []
            }

            @MainActor func measure(_ state: FixtureState, width: CGFloat) -> Measured {
                let store = FixtureFactory.store(for: state)
                let suite = "com.prabesh.focuscontinuity.strip-row.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return Measured() }
                defer { defaults.removePersistentDomain(forName: suite) }
                let settings = SettingsModel(store: PersistenceStore(defaults: defaults),
                                             isTrackingEnabled: true,
                                             onChange: {}, onTrackingChanged: { _ in })
                let navigation = MainWindowModel(store: store)
                let host = NSHostingView(rootView:
                    SessionControlStrip(store: store, settings: settings, navigation: navigation)
                        .frame(width: width))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                var found = Measured(height: host.fittingSize.height)
                func walk(_ view: NSView) {
                    let name = String(describing: type(of: view))
                    let rect = view.convert(view.bounds, to: host)
                    // Only the platform-backed controls are visible to an
                    // in-process walk; SwiftUI-drawn text never appears.
                    if rect.width > 0, rect.height > 0,
                       name.contains("_FocusRingView") || name.contains("SwiftUIPopupButton") {
                        found.controls.append((name, rect))
                    }
                    view.subviews.forEach(walk)
                }
                walk(host)
                return found
            }

            var failures: [String] = []
            defer { FixtureFactory.cleanUp() }
            // Two supported widths and both operational shapes. The strip must
            // not grow taller because the window grew wider.
            for state in [FixtureState.idleWithHistory, .running] {
                let narrow = measure(state, width: 980)
                let wide = measure(state, width: 1_600)
                if narrow.height > sessionStripRowHeightLimit {
                    failures.append("The \(state.rawValue) strip stood \(Int(narrow.height))pt tall "
                                    + "at 980pt, over the \(Int(sessionStripRowHeightLimit))pt row limit")
                }
                if abs(narrow.height - wide.height) > 1 {
                    failures.append("The \(state.rawValue) strip changed height with window width: "
                                    + "\(Int(narrow.height))pt at 980pt, \(Int(wide.height))pt at 1,600pt")
                }
                guard narrow.controls.count >= 2 else {
                    failures.append("The \(state.rawValue) strip presented no measurable controls")
                    continue
                }
                for control in narrow.controls
                where control.rect.height < AccessibilityMetrics.minimumTargetSize {
                    failures.append("A \(state.rawValue) strip control was "
                                    + "\(Int(control.rect.height))pt tall, under the "
                                    + "\(Int(AccessibilityMetrics.minimumTargetSize))pt floor")
                }
                // Pin and Close are the last two controls in reading order.
                // They must share the row band with the first one, not sit in
                // a header of their own.
                let centres = narrow.controls.map(\.rect.midY)
                if let lowest = centres.min(), let highest = centres.max(), highest - lowest > 8 {
                    failures.append("The \(state.rawValue) strip spread its controls over "
                                    + "\(Int(highest - lowest))pt of vertical band, so its chrome "
                                    + "is not on the row it governs")
                }
            }
            return failures
        }
    }

    /// Chrome plus one row of 28–30pt controls, with the strip's own 12pt
    /// vertical padding. Anything taller is a stack wearing a strip's name.
    private static let sessionStripRowHeightLimit: CGFloat = 72

    private static func oneSessionControlAtATime() -> [String] {
        var failures: [String] = []
        if !ChromeSessionControl.isShown(stripVisible: false) {
            failures.append("The chrome offered no session control when the strip was closed")
        }
        if ChromeSessionControl.isShown(stripVisible: true) {
            failures.append("The chrome and the strip both presented the session at once")
        }
        return failures
    }

    private final class IndexBox { var value = 0; var writes = 0 }

    /// Every scope row — Story, Insights, Review — must present exactly one
    /// native keyboard target. A row of SwiftUI pills would be one tab stop
    /// per pill, which is the defect the native control exists to prevent.
    private static func scopeRowsShareOneKeyboardTarget() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let rows: [(String, [String])] = [
                ("Story scope", StoryScope.allCases.map(\.title)),
                ("Insights range", InsightRange.allCases.map(\.title)),
                ("Review section", ReviewSection.allCases.map(\.title))
            ]
            for (label, titles) in rows {
                let box = IndexBox()
                let host = NSHostingView(rootView: ScopePillRow(
                    titles: titles,
                    selectedIndex: Binding(get: { box.value },
                                           set: { box.value = $0; box.writes += 1 }),
                    controlLabel: label))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = host
                host.frame = window.contentView?.bounds ?? .zero
                host.layoutSubtreeIfNeeded()
                let controls = descendants(in: host, of: ScopeNSSegmentedControl.self)
                guard controls.count == 1, let control = controls.first else {
                    failures.append("\(label) exposed \(controls.count) keyboard targets, not one")
                    window.contentView = nil
                    continue
                }
                if !window.makeFirstResponder(control) || window.firstResponder !== control {
                    failures.append("\(label) could not become the single first responder")
                }
                box.writes = 0
                control.keyDown(with: keyEvent(keyCode: 124, modifiers: .numericPad,
                                               windowNumber: window.windowNumber))
                if box.value != 1 || box.writes != 1 {
                    failures.append("\(label) Right key did not advance the selection exactly once")
                }
                box.writes = 0
                control.keyDown(with: keyEvent(keyCode: 119, modifiers: .function,
                                               windowNumber: window.windowNumber))
                if box.value != titles.count - 1 || box.writes != 1 {
                    failures.append("\(label) End did not select the last scope exactly once")
                }
                if control.accessibilityValue() as? String != "\(titles[titles.count - 1]), selected" {
                    failures.append("\(label) did not expose its selected value")
                }
                window.contentView = nil
            }

            // The component having one target is not enough: the real chrome
            // must actually use it. Story and Insights each show a scope row;
            // History, which finds rather than reads a period, shows none.
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            for (tab, expected) in [(AppTab.story, 1), (.insights, 1), (.review, 0)] {
                let navigation = MainWindowModel(store: store)
                navigation.open(tab: tab)
                let host = NSHostingView(rootView: StoryChromeBar(store: store,
                                                                  navigation: navigation)
                    .frame(width: 1_000))
                host.frame = NSRect(x: 0, y: 0, width: 1_000, height: 60)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                      backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                let found = descendants(in: host, of: ScopeNSSegmentedControl.self).count
                if found != expected {
                    failures.append("The \(tab.rawValue) chrome presented \(found) native scope "
                                    + "targets, expected \(expected)")
                }
                window.contentView = nil
            }

            // The Insights page must not carry a second copy of the scope the
            // chrome already owns.
            let insightsNavigation = MainWindowModel(store: store)
            insightsNavigation.open(tab: .insights)
            let page = NSHostingView(rootView: InsightsView(store: store,
                                                            navigation: insightsNavigation,
                                                            scrolls: false)
                .frame(width: 1_000, height: 700))
            page.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
            let pageWindow = NSWindow(contentRect: page.frame, styleMask: .borderless,
                                      backing: .buffered, defer: false)
            pageWindow.contentView = page
            page.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            page.layoutSubtreeIfNeeded()
            let onPage = descendants(in: page, of: ScopeNSSegmentedControl.self).count
            if onPage != 0 {
                failures.append("The Insights page duplicated the chrome's scope control "
                                + "(\(onPage) found)")
            }
            pageWindow.contentView = nil
            return failures
        }
    }

    private static func scopeKeyboard() -> [String] {
        var failures: [String] = []
        if StoryScopeKeyboardSelection.apply(.right, to: .day) != .week
            || StoryScopeKeyboardSelection.apply(.right, to: .month) != .month
            || StoryScopeKeyboardSelection.apply(.left, to: .week) != .day
            || StoryScopeKeyboardSelection.apply(.home, to: .month) != .day
            || StoryScopeKeyboardSelection.apply(.end, to: .day) != .month {
            failures.append("Left, Right, Home or End produced the wrong selected scope")
        }
        if StoryScopeKeyboardSelection.accessibilityValue(for: .week) != "Week, selected" {
            failures.append("The coherent scope target did not expose its selected value")
        }
        return failures
    }

    private final class ScopeSelectionBox {
        var value: StoryScope = .day
        var writes = 0
    }

    private static func nativeScopeAdapter() -> [String] {
        MainActor.assumeIsolated {
            let box = ScopeSelectionBox()
            let selection = Binding<StoryScope>(
                get: { box.value },
                set: { box.value = $0; box.writes += 1 })
            let host = NSHostingView(rootView: NativeStoryScopeControl(selection: selection)
                .frame(width: 190, height: AccessibilityMetrics.minimumTargetSize))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = window.contentView?.bounds ?? .zero
            host.layoutSubtreeIfNeeded()
            guard let control = embeddedScopeControl(in: host) else {
                window.contentView = nil
                return ["Could not locate the native Story scope control"]
            }
            var failures: [String] = []
            if !window.makeFirstResponder(control) || window.firstResponder !== control {
                failures.append("The native scope control could not become the coherent first responder")
            }
            control.updateIntegratedFocusCue()
            if control.focusRingType != .none || control.layer?.borderWidth != 2 {
                failures.append("The native outer ring was not replaced by the integrated focus cue")
            }
            // A click focuses the control, because it accepts first responder
            // so that Tab can reach it; the cue is for the keyboard alone.
            control.noteFocus(from: .pointer)
            if control.layer?.borderWidth != 0 {
                failures.append("Pointer-arrived focus drew the keyboard focus cue")
            }
            control.keyDown(with: keyEvent(keyCode: 123, modifiers: .numericPad,
                                           windowNumber: window.windowNumber))
            if control.layer?.borderWidth != 2 {
                failures.append("A key press after a click did not restore the focus cue")
            }
            _ = window.makeFirstResponder(nil)
            control.noteFocus(from: .pointer)
            _ = window.makeFirstResponder(control)
            if control.layer?.borderWidth != 0 {
                failures.append("Resigning focus did not reset the origin for the next arrival")
            }
            control.updateIntegratedFocusCue()
            _ = window.makeFirstResponder(nil)
            _ = window.makeFirstResponder(control)
            if control.layer?.borderWidth != 2 {
                failures.append("Keyboard-arrived focus after a resign lost its cue")
            }

            box.writes = 0
            control.keyDown(with: keyEvent(keyCode: 124, modifiers: .numericPad,
                                           windowNumber: window.windowNumber))
            if box.value != .week || box.writes != 1 || control.selectedSegment != 1 {
                failures.append("The real Right-key adapter path did not select Week exactly once")
            }

            for modifiers: NSEvent.ModifierFlags in [.command, .option, .control, .shift,
                                                       [.command, .numericPad], [.option, .function]] {
                box.writes = 0
                let selected = box.value
                control.keyDown(with: keyEvent(keyCode: 123, modifiers: modifiers,
                                               windowNumber: window.windowNumber))
                if box.value != selected || box.writes != 0 {
                    failures.append("Modified Left with \(modifiers.rawValue) changed Story scope")
                }
            }

            box.writes = 0
            control.keyDown(with: keyEvent(keyCode: 115, modifiers: .function,
                                           windowNumber: window.windowNumber))
            if box.value != .day || box.writes != 1 {
                failures.append("Function-flagged Home did not select Day exactly once")
            }

            box.writes = 0
            control.selectedSegment = 2
            control.sendAction(control.action, to: control.target)
            if box.value != .month || box.writes != 1 {
                failures.append("The real pointer/action path did not select Month exactly once")
            }
            if control.accessibilityValue() as? String != "Month, selected" {
                failures.append("The native target did not expose its current selected value")
            }
            window.contentView = nil
            return failures
        }
    }

    private static func keyEvent(keyCode: UInt16,
                                 modifiers: NSEvent.ModifierFlags,
                                 windowNumber: Int) -> NSEvent {
        let functionKey: Int
        switch keyCode {
        case 123: functionKey = NSLeftArrowFunctionKey
        case 124: functionKey = NSRightArrowFunctionKey
        case 115: functionKey = NSHomeFunctionKey
        case 119: functionKey = NSEndFunctionKey
        default: functionKey = 0
        }
        let characters = functionKey > 0
            ? String(UnicodeScalar(functionKey)!) : "x"
        return NSEvent.keyEvent(with: .keyDown, location: .zero,
                        modifierFlags: modifiers, timestamp: 0,
                        windowNumber: windowNumber, context: nil,
                        characters: characters, charactersIgnoringModifiers: characters,
                        isARepeat: false, keyCode: keyCode)!
    }

    @MainActor private static func embeddedScopeControl(in view: NSView)
        -> StoryScopeNSSegmentedControl? {
        if let control = view as? StoryScopeNSSegmentedControl { return control }
        for child in view.subviews {
            if let control = embeddedScopeControl(in: child) { return control }
        }
        return nil
    }

    private final class AwayKeyboardRecorder: ObservableObject {
        @Published var search = ""
        var decisions: [UserDecision] = []
        var reasons: [String] = []
    }

    private struct AwayKeyboardHarness: View {
        @ObservedObject var recorder: AwayKeyboardRecorder

        var body: some View {
            VStack {
                TextField("History search", text: $recorder.search)
                AwayAnswerGrid(away: 22 * 60,
                               range: (Date(timeIntervalSince1970: 1_800_000_000),
                                       Date(timeIntervalSince1970: 1_800_001_320)),
                               compact: true,
                               onAnswer: { recorder.decisions.append($0); return false },
                               onReason: { recorder.reasons.append($0); return false })
            }
            .frame(width: 340)
            .padding()
        }
    }

    /// A tiling or window manager can resize the borderless prompt through the
    /// accessibility API. The answers must stay cards when it does — a card
    /// that absorbs offered height spreads the grid down the whole display.
    private static func awayAnswersIgnoreWindowHeight() -> [String] {
        MainActor.assumeIsolated {
            @MainActor func answerHeights(windowHeight: CGFloat) -> [CGFloat] {
                let host = NSHostingView(rootView: AwayAnswerGrid(
                    away: 3_120,
                    range: (start: Date(timeIntervalSince1970: 1_788_598_000),
                            end: Date(timeIntervalSince1970: 1_788_601_120)),
                    showsCaptions: true,
                    onAnswer: { _ in true },
                    onReason: { _ in true })
                    .frame(width: 520))
                let frame = NSRect(x: 0, y: 0, width: 560, height: windowHeight)
                let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.contentView = host
                host.frame = window.contentView?.bounds ?? .zero
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                let heights = descendants(in: host, of: AwayAnswerNSButton.self)
                    .map { $0.frame.height }.sorted()
                window.contentView = nil
                return heights
            }

            var failures: [String] = []
            let short = answerHeights(windowHeight: 620)
            let tall = answerHeights(windowHeight: 1_600)
            guard short.count == 4, tall.count == 4 else {
                return ["The hosted away grid did not expose its four native answers"]
            }
            if short != tall {
                failures.append("Answer heights followed the window: \(short) then \(tall)")
            }
            if let tallest = tall.max(), tallest > 200 {
                failures.append("An answer grew to \(tallest)pt, which is a panel not a card")
            }
            return failures
        }
    }

    private static func awayReturnScope() -> [String] {
        MainActor.assumeIsolated {
            let recorder = AwayKeyboardRecorder()
            let host = NSHostingView(rootView: AwayKeyboardHarness(recorder: recorder))
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000,
                                                      width: 380, height: 520),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = window.contentView?.bounds ?? .zero
            window.makeKeyAndOrderFront(nil)

            func settle() {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
            func dispatch(_ keyCode: UInt16, characters: String) {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: keyCode == 49 ? [] : [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil,
                    characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: keyCode)!
                if let responder = window.firstResponder {
                    responder.keyDown(with: event)
                } else {
                    host.keyDown(with: event)
                }
                settle()
            }
            var failures: [String] = []
            settle()
            let textFields = descendants(in: host, of: NSTextField.self)
            let answerButtons = descendants(in: host, of: AwayAnswerNSButton.self)
            guard textFields.count >= 2, answerButtons.count == 4 else {
                window.orderOut(nil)
                window.contentView = nil
                return ["Hosted Away grid did not expose its two editors and four native answers"]
            }
            let search = textFields.first { $0.placeholderString == "History search" } ?? textFields[0]
            let reason = textFields.first { $0.placeholderString?.contains("Name it") == true }
                ?? textFields[1]
            window.makeFirstResponder(search)
            dispatch(36, characters: "\r")
            if !recorder.decisions.isEmpty || !recorder.reasons.isEmpty {
                failures.append("Return in unrelated History search answered the away question")
            }

            window.makeFirstResponder(reason)
            if let editor = window.firstResponder as? NSTextView {
                editor.insertText("walk", replacementRange: editor.selectedRange())
            } else {
                failures.append("Reason editor did not expose its hosted field editor")
            }
            dispatch(36, characters: "\r")
            if recorder.reasons != ["walk"] || !recorder.decisions.isEmpty {
                failures.append("Reason-editor Return did not submit only its own reason")
            }

            for decision in [UserDecision.tookBreak, .mergeTime, .continueSession, .resetTimer] {
                guard let button = answerButtons.first(where: {
                    $0.accessibilityLabel()?.hasPrefix(answerTitle(decision)) == true
                }) else {
                    failures.append("Could not find native answer for \(decision.rawValue)")
                    continue
                }
                if !button.acceptsFirstResponder || button.focusRingType == .none
                    || button.accessibilityRole() != .button {
                    failures.append("Native \(decision.rawValue) answer lost focus ring or Button semantics")
                }
                if button.frame.width < 130 || button.frame.height < AccessibilityMetrics.minimumTargetSize {
                    failures.append("Native \(decision.rawValue) hit target does not cover its answer card")
                }
                let pointerBefore = recorder.decisions.count
                button.performClick(nil)
                if recorder.decisions.count != pointerBefore + 1
                    || recorder.decisions.last != decision {
                    failures.append("Native pointer action for \(decision.rawValue) did not fire exactly once")
                }
                for (keyCode, characters) in [(UInt16(36), "\r"), (UInt16(49), " ")] {
                    let before = recorder.decisions.count
                    if !window.makeFirstResponder(button) || window.firstResponder !== button {
                        failures.append("Native \(decision.rawValue) answer could not become first responder")
                    }
                    dispatch(keyCode, characters: characters)
                    if recorder.decisions.count != before + 1
                        || recorder.decisions.last != decision {
                        failures.append("Focused \(decision.rawValue) did not activate exactly once with key \(keyCode)")
                    }
                }
            }
            window.orderOut(nil)
            window.contentView = nil
            return failures
        }
    }

    @MainActor private static func descendants<T: NSView>(in view: NSView,
                                                           of type: T.Type) -> [T] {
        var found = view as? T != nil ? [view as! T] : []
        for child in view.subviews { found.append(contentsOf: descendants(in: child, of: type)) }
        return found
    }

    private static func answerTitle(_ decision: UserDecision) -> String {
        switch decision {
        case .tookBreak: return "It was a break"
        case .mergeTime: return "I was working"
        case .continueSession: return "I was away"
        case .resetTimer: return "Start fresh"
        }
    }

    private static func generalFailurePresentation() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let origin = (store.engine.activeThreadID, store.engine.sessionStartDate)
            store.publishCorrectionError("The original Stop could not be saved.")
            store.correctionRetry = .ending(threadID: origin.0, sessionStart: origin.1)
            guard let failure = store.focusOperationFailure else {
                return ["A general finalisation failure disappeared from compact Focus consumers"]
            }
            var failures: [String] = []
            if failure.message != "The original Stop could not be saved."
                || !failure.hasOriginBoundRetry {
                failures.append("Compact Focus did not retain the error and its origin-bound Retry")
            }
            let pending = FixtureFactory.store(for: .needsResolution)
            if let id = pending.engine.pendingDecisionID {
                pending.publishCorrectionError("The answer was not saved.")
                pending.correctionRetry = .awayDecision(.tookBreak, label: "walk",
                                                        reviewing: false, expectedID: id)
            }
            if pending.pendingAwaySaveError == nil || pending.focusOperationFailure != nil {
                failures.append("A pending-away question duplicated its save error as a general failure")
            }
            return failures
        }
    }

    private static func compactGoalLine() -> [String] {
        let unavailable = CompactGoalPresentation(
            GoalProgress(goal: 4 * 3_600, achieved: 31, typical: nil))
        let behind = CompactGoalPresentation(
            GoalProgress(goal: 4 * 3_600, achieved: 31, typical: 4 * 3_600))
        var failures: [String] = []
        // With nothing to compare against, the line states the goal and stops.
        // "Pace unavailable" announced an absence the reader cannot act on,
        // while the explanation stays available to assistive technology.
        if unavailable.visible != "Today · 31s / 4h"
            || unavailable.visible.contains("unavailable")
            || !unavailable.accessibility.contains("Pace comparison appears after enough comparable history") {
            failures.append("An uncomparable pace did not fall silent while keeping its explanation")
        }
        if behind.visible != "Today · 31s / 4h · 3h 59m behind"
            || !behind.accessibility.contains("3h 59m behind your usual pace") {
            failures.append("Behind pace did not keep short visible copy and complete accessibility detail")
        }
        let width = (behind.visible as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ]).width
        if width > 292 {
            failures.append("Longest compact goal copy needs \(Int(width))pt at a 292pt content measure")
        }
        return failures
    }
}
