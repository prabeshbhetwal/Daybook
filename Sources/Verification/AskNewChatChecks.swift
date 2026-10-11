import SwiftUI

/// Where New chat stands: in the header beside Close, in the sheet as in the
/// side panel, once the chat has a turn, and nowhere in the footer.
/// `AskPanelChecks` lists these.
enum AskNewChatChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("New chat stands in the sheet's header once the chat has a turn, and not before", sheetHeaderHasNewChat),
        ("New chat stands in the side panel's header once the chat has a turn, and not before", panelHeaderHasNewChat),
        ("The chat's footer carries no New chat, so one stands in each place", footerHasNoNewChat),
    ]

    private static let answered = AskTurn(question: "When did I focus most?", answer: "On Tue 15 Sep.", state: .answered)

    /// The window drawn offscreen with Ask open as `placement` and `turns` in the chat.
    @MainActor private static func window(placement: AskPlacement, turns: [AskTurn]) -> Set<StoryRenderEvidence> {
        let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
        defer { FixtureFactory.cleanUp() }
        let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.askPlacement = placement
        let navigation = MainWindowModel(store: store)
        navigation.openAsk()
        navigation.askModel?.present(turns: turns)
        return StoryWorkspaceChecks.renderFrame(
            MainWindowView(store: store, settings: settings, navigation: navigation, presentsNativeSheets: false),
            width: 1_340, height: 760).evidence
    }

    private static func sheetHeaderHasNewChat() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let with = window(placement: .sheet, turns: [answered])
            expect(with.contains(.askNewChat), "the sheet with an answer drew \(with.map(\.rawValue).sorted())", &problems)
            let without = window(placement: .sheet, turns: [])
            expect(!without.contains(.askNewChat), "the sheet of an empty chat drew New chat", &problems)
        }
        return problems
    }

    private static func panelHeaderHasNewChat() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let with = window(placement: .panel, turns: [answered])
            expect(with.contains(.askPanel) && with.contains(.askNewChat),
                   "the panel with an answer drew \(with.map(\.rawValue).sorted())", &problems)
            let without = window(placement: .panel, turns: [])
            expect(without.contains(.askPanel) && !without.contains(.askNewChat),
                   "the panel of an empty chat drew \(without.map(\.rawValue).sorted())", &problems)
        }
        return problems
    }

    private static func footerHasNoNewChat() -> [String] {
        AskThreadChecks.withModel { _, model, problems in
            model.present(turns: [answered])
            let chat = StoryWorkspaceChecks.renderFrame(AskChatView(model: model, onFollow: { _ in }),
                                                        width: 640, height: 600).evidence
            expect(chat.contains(.askTranscript) && !chat.contains(.askNewChat),
                   "the chat alone drew \(chat.map(\.rawValue).sorted())", &problems)
        }
    }
}
