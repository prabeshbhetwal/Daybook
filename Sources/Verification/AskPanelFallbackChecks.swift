import SwiftUI

/// The side panel gives way to the sheet on a screen too small to hold it:
/// the rule (`AskLayout.panelHasRoom`) and what the window model does with it.
/// `AskPanelChecks` lists these.
///
/// The window with the panel is 1,340 × 680 points at 100%, and a screen
/// leaves `InterfaceZoom.screenMargin` (40) free, so it has room when its
/// visible area is at least 1,380 × 720 at 100% and 1,916 × 992 at 140%.
enum AskPanelFallbackChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The side panel has room only where its window's minimum is not held to the screen", roomFollowsScreenAndZoom),
        ("A side panel the screen cannot hold opens Ask as the sheet, and the choice is kept", noRoomOpensSheet),
        ("A panel that loses its room becomes the sheet on the same chat", lostRoomBecomesSheet),
    ]

    private static func roomFollowsScreenAndZoom() -> [String] {
        var problems: [String] = []
        let cases: [(what: String, scale: CGFloat, visible: CGSize, room: Bool)] = [
            ("a 1280 × 800 screen at 140%", 1.4, CGSize(width: 1_280, height: 800), false),
            ("a 1512 × 944 screen at 100%", 1, CGSize(width: 1_512, height: 944), true),
            ("a 1728 × 1084 screen at 140%", 1.4, CGSize(width: 1_728, height: 1_084), false),
            ("a 2560 × 1415 screen at 140%", 1.4, CGSize(width: 2_560, height: 1_415), true),
            ("exactly the window plus the margin, 1380 × 720, at 100%", 1, CGSize(width: 1_380, height: 720), true),
            ("a point too narrow", 1, CGSize(width: 1_379, height: 720), false),
            ("a point too short", 1, CGSize(width: 1_380, height: 719), false),
            ("no limit (a screen not yet known)", 1.4, CGSize(width: CGFloat.infinity, height: CGFloat.infinity), true),
        ]
        for item in cases {
            let room = AskLayout.panelHasRoom(scale: item.scale, visible: item.visible)
            expect(room == item.room, "\(item.what) has room \(room), not \(item.room)", &problems)
        }
        return problems
    }

    private static func noRoomOpensSheet() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated {
                let navigation = MainWindowModel(store: f.store)
                let settings = SettingsModel(store: f.engine.store, isTrackingEnabled: true, onChange: {},
                                             onTrackingChanged: { _ in })
                settings.askPlacement = .panel
                navigation.updateAskPanelRoom(false)
                navigation.openAsk()
                expect(navigation.sheet == .ask && !navigation.askPanelOpen,
                       "with no room ⌘K gave sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)",
                       &problems)
                expect(navigation.askPlacement == .panel, "the saved choice became \(navigation.askPlacement)", &problems)

                // Settings' Open Ask closes Settings and lands in the same place.
                navigation.closeSheet()
                navigation.openSheet(.settings)
                navigation.openAsk()
                expect(navigation.sheet == .ask && !navigation.askPanelOpen,
                       "Open Ask over Settings gave sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)",
                       &problems)

                // Room back: the next ⌘K opens the panel.
                navigation.closeSheet()
                navigation.updateAskPanelRoom(true)
                navigation.openAsk()
                expect(navigation.askPanelOpen && navigation.sheet == nil,
                       "with room again ⌘K gave sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)",
                       &problems)
            }
        }
    }

    private static func lostRoomBecomesSheet() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated {
                let navigation = MainWindowModel(store: f.store)
                let settings = SettingsModel(store: f.engine.store, isTrackingEnabled: true, onChange: {},
                                             onTrackingChanged: { _ in })
                settings.askPlacement = .panel
                navigation.openAsk()
                let chat = navigation.askModel
                expect(navigation.askPanelOpen && chat != nil, "the panel did not open", &problems)

                navigation.updateAskPanelRoom(false)
                expect(!navigation.askPanelOpen && navigation.sheet == .ask,
                       "losing room left panel \(navigation.askPanelOpen), sheet \(String(describing: navigation.sheet))",
                       &problems)
                expect(navigation.askModel === chat, "the sheet is not on the chat the panel had", &problems)

                // Saying the same thing again changes nothing.
                navigation.updateAskPanelRoom(false)
                expect(navigation.sheet == .ask, "a repeated report moved the sheet", &problems)

                // Room back does not move a sheet that is on show; the next ⌘K opens the panel.
                navigation.updateAskPanelRoom(true)
                expect(navigation.sheet == .ask && !navigation.askPanelOpen,
                       "regaining room moved Ask: sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)",
                       &problems)
                navigation.closeSheet()
                navigation.openAsk()
                expect(navigation.askPanelOpen && navigation.sheet == nil, "the next ⌘K did not open the panel", &problems)

                // Another sheet over the window stays: only the panel closes.
                navigation.openSheet(.settings)
                navigation.updateAskPanelRoom(false)
                expect(!navigation.askPanelOpen && navigation.sheet == .settings,
                       "losing room under Settings left panel \(navigation.askPanelOpen), sheet \(String(describing: navigation.sheet))",
                       &problems)

                // The sheet choice never needs the report.
                navigation.closeSheet()
                settings.askPlacement = .sheet
                navigation.updateAskPanelRoom(true)
                navigation.openAsk()
                navigation.updateAskPanelRoom(false)
                expect(navigation.sheet == .ask && !navigation.askPanelOpen,
                       "with the sheet chosen, a report of no room left sheet \(String(describing: navigation.sheet))",
                       &problems)
            }
        }
    }
}
