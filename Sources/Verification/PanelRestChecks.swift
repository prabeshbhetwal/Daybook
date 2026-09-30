import AppKit
import SwiftUI

/// The menu bar panel rests inside SwiftUI (`PanelRest`). Lifting its hosting
/// view out of the window, as `WindowDormancy` does, left the panel stuck at
/// an old height with the rest of its content behind a scroll bar.
enum PanelRestChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A closed menu bar panel rests, and reopens measuring what it now shows", restsAndFollowsContent),
    ]

    private final class Beat: ObservableObject {
        @Published var height: CGFloat = 100
        var evaluations = 0
    }

    private struct BeatView: View {
        @ObservedObject var beat: Beat
        var body: some View {
            beat.evaluations += 1
            return Color.clear.frame(width: 120, height: beat.height)
        }
    }

    private static func restsAndFollowsContent() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let beat = Beat()
            let panel = NSPanel(contentRect: NSRect(x: -4_000, y: -4_000, width: 120, height: 100),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: PanelRest { BeatView(beat: beat) })
            panel.contentView = host
            func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }

            // Built while hidden and ordered in before the next turn of the
            // run loop, as the menu bar panel is on its first click: a stale
            // "hidden" from building must not blank the open panel.
            host.layoutSubtreeIfNeeded()
            panel.orderFront(nil)
            spin()
            if beat.evaluations == 0 { problems.append("The shown panel never drew its content") }

            panel.orderOut(nil)
            spin()
            let resting = beat.evaluations
            beat.height = 300
            spin()
            if beat.evaluations != resting {
                problems.append("Closed, the content still ran \(beat.evaluations - resting) times")
            }
            if panel.contentView !== host { problems.append("Closing took the content out of the panel") }

            panel.orderFront(nil)
            spin()
            let measured = host.fittingSize.height
            if abs(measured - 300) > 0.5 {
                problems.append("Reopened, the panel measures \(Int(measured))pt for 300pt of content")
            }
            panel.orderOut(nil)
            return problems
        }
    }
}
