import SwiftUI

/// Where Ask's side panel stands when the window is held to a screen that
/// cannot hold the whole minimum. The panel's own width is fixed; what a
/// reading workspace with a minimum of its own can do is push the panel past
/// the window's edge, so this measures what is drawn.
enum AskPanelLayoutChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The panel keeps its width, whole inside the window, when the reading workspace cannot fit beside it", panelKeepsWidthWhenSqueezed),
        ("The panel and the sheet hold objects, not closures, so the window drawing again does not draw the chat again",
         panelsHoldNoClosures),
    ]

    /// SwiftUI skips a view's body when its inputs are equal to the last ones. A
    /// closure is never equal to another, so a view holding one is drawn again
    /// every time its parent is, which for the window is every second while a
    /// session runs.
    private static func panelsHoldNoClosures() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            let navigation = MainWindowModel(store: store)
            let ask = AskModel(store: store)
            func closures<V>(in view: V) -> [String] {
                Mirror(reflecting: view).children.filter { "\(type(of: $0.value))".contains("->") }.map { $0.label ?? "?" }
            }
            let panel = closures(in: AskPanel(model: ask, navigation: navigation))
            expect(panel.isEmpty, "the panel holds closures \(panel), so every redraw of the window redraws the chat", &problems)
            let sheet = closures(in: AskSheet(model: ask, navigation: navigation))
            expect(sheet.isEmpty, "the sheet holds closures \(sheet), so every redraw of the window redraws the chat", &problems)
        }
        return problems
    }

    /// A workspace whose own content minimum is wider than the room the panel
    /// leaves in a 1000 point window, drawn solid red so its extent is plain in
    /// the bitmap. `MainWindowView` cannot be drawn narrower than its own
    /// minimum on a roomy screen, so this is the view it puts the workspace in.
    private static func panelKeepsWidthWhenSqueezed() -> [String] {
        var problems: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            let navigation = MainWindowModel(store: store)
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            settings.askPlacement = .panel
            navigation.openAsk()
            guard let ask = navigation.askModel else { problems.append("Ask's model was not built"); return }

            InterfaceZoomChecks.withZoom(100) {
                let panel = AskLayout.panelWidth
                for (what, window) in [("roomy", CGFloat(1_200)), ("squeezed", CGFloat(1_000))] {
                    let frame = StoryWorkspaceChecks.renderFrame(
                        ReadingWithAskPanel(askModel: ask, navigation: navigation) {
                            Color(red: 1, green: 0, blue: 0).frame(minWidth: 700, maxWidth: .infinity, maxHeight: .infinity)
                        },
                        width: window, height: 400)
                    guard let bitmap = frame.bitmap else { problems.append("the \(what) window drew nothing"); continue }
                    let scale = CGFloat(bitmap.pixelsWide) / window
                    let row = bitmap.pixelsHigh / 2
                    func isWorkspace(_ x: Int) -> Bool {
                        // Pure red comes out of the bitmap colour-managed, about (0.94, 0.29, 0.18).
                        guard let colour = bitmap.colorAt(x: x, y: row)?.usingColorSpace(.sRGB) else { return false }
                        return colour.redComponent > 0.8 && colour.greenComponent < 0.45 && colour.blueComponent < 0.35
                    }
                    // From the window's right edge inwards, the panel and its divider are what is not the workspace.
                    var drawn = 0
                    while drawn < bitmap.pixelsWide, !isWorkspace(bitmap.pixelsWide - 1 - drawn) { drawn += 1 }
                    let drawnWidth = CGFloat(drawn) / scale
                    expect(abs(drawnWidth - (panel + 1)) <= 2,
                           "in a \(what) window of \(window) the panel and its divider draw \(drawnWidth) wide, not \(panel + 1)",
                           &problems)
                }
            }
        }
        return problems
    }
}
