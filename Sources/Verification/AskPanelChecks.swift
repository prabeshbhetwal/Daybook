import SwiftUI

/// Where Ask opens, sheet or side panel: the saved choice, its place in
/// Settings, what changing it does to a panel that is open, and the panel
/// itself in the window. The chat both places show is checked in
/// `AskChatSurfaceChecks`, the panel's place in a squeezed window in
/// `AskPanelLayoutChecks` and whether its supporting text can be read in
/// `AskLegibilityChecks`; all are listed here.
enum AskPanelChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = ownTests + AskChatSurfaceChecks.tests + AskPanelLayoutChecks.tests
        + AskLegibilityChecks.tests

    private static let ownTests: [(String, () -> [String])] = [
        ("Ask opens as a sheet until the side panel is chosen, and the choice is saved", placementSavedDefaultSheet),
        ("A panel left open when the choice becomes the sheet closes as Settings closes", placementChangeClosesPanelWhenSettingsClose),
        ("A panel left open when the choice becomes the sheet is not brought back by choosing the panel again",
         staleOpenFlagDoesNotReturn),
        ("The side panel adds its own width to the window's minimum", panelWidensMinimum),
        ("A panel's minimum is held to a small screen at a high zoom", panelMinimumHeldToScreen),
        ("A window grows to hold a minimum that grows, and stays on its screen", anchorGrowsWindowWhenBaseGrows),
        ("The side panel stands beside Story and History while it is open and still the choice", panelBesideStoryAndHistory),
        ("The bar's Ask button looks pressed while the side panel is open", buttonShowsOpenPanel),
    ]

    private static func placementSavedDefaultSheet() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-askpanel-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not make a preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let store = PersistenceStore(defaults: defaults)
        expect(store.askPlacement == .sheet, "a new install opens Ask as \(store.askPlacement)", &problems)
        MainActor.assumeIsolated {
            let model = SettingsModel(store: store, isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in })
            model.askPlacement = .panel
            expect(PersistenceStore(defaults: defaults).askPlacement == .panel,
                   "choosing the side panel was not saved", &problems)
            model.askPlacement = .sheet
            expect(PersistenceStore(defaults: defaults).askPlacement == .sheet,
                   "choosing the sheet again was not saved", &problems)
            expect(SettingsControlKey.askPlacement.modelKeyPath == \SettingsModel.askPlacement,
                   "the Settings control does not name the placement", &problems)
        }
        for unreadable: Any in ["sideways", "", 7, true] {
            defaults.set(unreadable, forKey: "fc.askPlacement")
            expect(PersistenceStore(defaults: defaults).askPlacement == .sheet,
                   "the stored value \(unreadable) opened Ask as \(PersistenceStore(defaults: defaults).askPlacement)",
                   &problems)
        }
        store.askPlacement = .panel
        store.removeAll()
        expect(store.askPlacement == .sheet, "resetting every setting kept the side panel", &problems)
        let found = SettingsSection.matching("Side panel").map(\.title)
        expect(found.contains("General"), "searching “Side panel” finds \(found), not General", &problems)
        for words in ["Open Ask in", "Inspector", "Sidebar"] {
            let found = SettingsSection.matching(words).map(\.title)
            expect(found.contains("General"), "searching “\(words)” finds \(found), not General", &problems)
        }
        return problems
    }

    private static func placementChangeClosesPanelWhenSettingsClose() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated { panelFollowsPlacement(f, &problems) }
        }
    }

    @MainActor private static func panelFollowsPlacement(_ f: AskLookupChecks.Fixture, _ problems: inout [String]) {
        let navigation = MainWindowModel(store: f.store)
        let settings = SettingsModel(store: f.engine.store, isTrackingEnabled: true, onChange: {},
                                     onTrackingChanged: { _ in })
        settings.askPlacement = .panel
        navigation.openAsk()
        expect(navigation.askPanelOpen, "the panel did not open", &problems)

        navigation.openSheet(.settings)
        expect(navigation.askPanelOpen, "Settings opening closed the panel", &problems)
        settings.askPlacement = .sheet
        expect(navigation.askPanelOpen, "the panel closed before Settings did", &problems)
        navigation.closeSheet()
        expect(!navigation.askPanelOpen && navigation.sheet == nil,
               "the panel is \(navigation.askPanelOpen ? "still open" : "closed") after Settings closed", &problems)
        navigation.openAsk()
        expect(navigation.sheet == .ask && !navigation.askPanelOpen,
               "the next ⌘K gave sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)", &problems)
        navigation.closeSheet()

        // Keeping the side panel keeps it open.
        settings.askPlacement = .panel
        navigation.openAsk()
        navigation.openSheet(.settings)
        navigation.closeSheet()
        expect(navigation.askPanelOpen, "closing Settings closed a panel that is still the choice", &problems)

        // Closing a sheet that has nothing to do with Ask never touches a closed panel.
        navigation.closeAskPanel()
        navigation.openSheet(.awards)
        navigation.closeSheet()
        expect(!navigation.askPanelOpen, "closing Awards opened the panel", &problems)
    }

    /// Settings left some other way than its close button (a command opens the
    /// story, or Awards): the panel the choice no longer allows must not wait
    /// to come back when the panel is chosen again.
    private static func staleOpenFlagDoesNotReturn() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated {
                let navigation = MainWindowModel(store: f.store)
                let settings = SettingsModel(store: f.engine.store, isTrackingEnabled: true, onChange: {},
                                             onTrackingChanged: { _ in })
                for (way, leave) in [("opening the story", { navigation.open(tab: .story) }),
                                     ("opening Awards", { navigation.open(tab: .awards) })] {
                    settings.askPlacement = .panel
                    navigation.openAsk()
                    navigation.openSheet(.settings)
                    settings.askPlacement = .sheet
                    leave()
                    settings.askPlacement = .panel
                    expect(!navigation.askPanelOpen, "after \(way) and choosing the side panel again it opened unasked",
                           &problems)
                    navigation.closeSheet()
                }
            }
        }
    }

    // MARK: - The panel in the window

    private static func panelWidensMinimum() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let closed = MainWindowView.contentBase(askPanelOpen: false)
            let open = MainWindowView.contentBase(askPanelOpen: true)
            expect(closed == CGSize(width: 980, height: 680), "with no panel the minimum is \(closed), not 980 × 680", &problems)
            expect(open == CGSize(width: 1_340, height: 680), "with the panel the minimum is \(open), not 1340 × 680", &problems)
            expect(AskLayout.panelBaseWidth == 360, "the panel is \(AskLayout.panelBaseWidth) wide at 100%, not 360", &problems)
            let wide = InterfaceZoomChecks.withZoom(140) { AskLayout.panelWidth }
            expect(abs(wide - 504) < 0.001, "at 140% the panel is \(wide) wide, not 504", &problems)
        }
        return problems
    }

    /// A 1280 × 800 screen cannot hold 1340 × 680 at 140%; the minimum stops
    /// at the screen's margin and the reading column gives way.
    private static func panelMinimumHeldToScreen() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let visible = CGSize(width: 1_280, height: 800)
            let minimum = InterfaceZoom.windowMinimum(base: MainWindowView.contentBase(askPanelOpen: true),
                                                      scale: 1.4, visible: visible)
            let room = CGSize(width: visible.width - InterfaceZoom.screenMargin,
                              height: visible.height - InterfaceZoom.screenMargin)
            expect(minimum.width <= room.width && minimum.height <= room.height,
                   "at 140% the panel's minimum is \(minimum), more than the \(room) a 1280 × 800 screen leaves", &problems)
            expect(minimum == room, "the minimum is \(minimum), not held at the screen's \(room)", &problems)
        }
        return problems
    }

    /// Opening the panel raises the window's minimum. AppKit may grow the
    /// window first, or not at all, so the anchor grows it and keeps it on its
    /// screen, from the minimum it was at, near the screen's right edge.
    private static func anchorGrowsWindowWhenBaseGrows() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            guard let screen = NSScreen.main else { return }
            InterfaceZoomChecks.withZoom(100) {
                let visible = screen.visibleFrame
                // Written out, so this holds the anchor to account apart from `contentBase`.
                let closed = CGSize(width: 980, height: 680)
                let open = CGSize(width: 1_340, height: 680)
                let before = InterfaceZoom.windowMinimum(base: closed, scale: 1, visible: visible.size)
                let expected = InterfaceZoom.windowMinimum(base: open, scale: 1, visible: visible.size)
                let start = CGRect(x: visible.maxX - before.width - 20, y: visible.maxY - before.height - 20,
                                   width: before.width, height: before.height)
                let anchor = ZoomWindowFitAnchor()
                anchor.base = closed
                let window = NSWindow(contentRect: start, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.alphaValue = 0
                window.ignoresMouseEvents = true
                window.contentView = anchor
                window.setFrame(start, display: false)
                window.orderFront(nil)
                defer { window.orderOut(nil); window.close() }
                guard window.isVisible, window.screen != nil else { return }

                anchor.base = open
                let deadline = Date().addingTimeInterval(2)
                while window.contentRect(forFrameRect: window.frame).width < expected.width - 0.5, Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                let content = window.contentRect(forFrameRect: window.frame).size
                expect(content.width >= expected.width - 0.5 && content.height >= before.height - 0.5,
                       "after the minimum grew to \(expected) the window holds \(content)", &problems)
                let screenFrame = window.screen?.visibleFrame ?? visible
                expect(screenFrame.insetBy(dx: -0.5, dy: -0.5).contains(window.frame),
                       "the grown window \(window.frame) is not on its screen \(screenFrame)", &problems)
            }
        }
        return problems
    }

    private static func panelBesideStoryAndHistory() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.setDashboardVisible(true)
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            settings.askPlacement = .panel
            let navigation = MainWindowModel(store: store)
            func drawn() -> Set<StoryRenderEvidence> {
                StoryWorkspaceChecks.renderFrame(
                    MainWindowView(store: store, settings: settings, navigation: navigation,
                                   presentsNativeSheets: false),
                    width: 1_340, height: 760).evidence
            }
            func names(_ evidence: Set<StoryRenderEvidence>) -> [String] { evidence.map(\.rawValue).sorted() }
            let closed = drawn()
            expect(closed.contains(.dayStory) && !closed.contains(.askPanel), "a closed panel drew \(names(closed))", &problems)

            navigation.openAsk()
            let story = drawn()
            expect(story.contains(.askPanel) && story.contains(.dayStory),
                   "the panel beside Story drew \(names(story))", &problems)

            navigation.open(tab: .review)
            let history = drawn()
            expect(history.contains(.askPanel) && history.contains(.historyTree),
                   "the panel beside History drew \(names(history))", &problems)

            // A sheet closed another way than Settings can leave the flag set after
            // the choice became the sheet; the window must not draw a panel then.
            settings.askPlacement = .sheet
            let changed = drawn()
            expect(!changed.contains(.askPanel),
                   "a panel drew although the choice is the sheet: \(names(changed))", &problems)

            settings.askPlacement = .panel
            navigation.closeAskPanel()
            let closedAgain = drawn()
            expect(!closedAgain.contains(.askPanel),
                   "a panel closed by its button still drew: \(names(closedAgain))", &problems)
        }
        return problems
    }

    private static func buttonShowsOpenPanel() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            settings.askPlacement = .panel
            let navigation = MainWindowModel(store: store)
            func bar() -> Set<StoryRenderEvidence> {
                StoryWorkspaceChecks.renderFrame(
                    StoryChromeBar(store: store, navigation: navigation, showsAsk: true), width: 1_160, height: 60).evidence
            }
            func names(_ evidence: Set<StoryRenderEvidence>) -> [String] { evidence.map(\.rawValue).sorted() }
            let idle = bar()
            expect(!idle.contains(.askButtonActive) && idle.contains(.askButtonWithWord),
                   "a bar with the panel closed drew \(names(idle))", &problems)
            navigation.openAsk()
            let pressed = bar()
            expect(pressed.contains(.askButtonActive) && pressed.contains(.askButtonWithWord),
                   "a bar with the panel open drew \(names(pressed))", &problems)
            settings.askPlacement = .sheet
            let stale = bar()
            expect(!stale.contains(.askButtonActive),
                   "the button looks pressed for a panel that is no longer the choice: \(names(stale))", &problems)
            settings.askPlacement = .panel
            navigation.closeAskPanel()
            expect(!bar().contains(.askButtonActive), "the button looks pressed after the panel closed", &problems)
        }
        return problems
    }
}
