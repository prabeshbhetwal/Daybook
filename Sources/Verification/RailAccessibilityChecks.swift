import AppKit
import SwiftUI

/// What VoiceOver hears from the away answers. The answers are native buttons
/// over SwiftUI cards, so their spoken words can be read back in process.
enum RailAccessibilityChecks {
    static let tests: [(String, () -> [String])] = [
        ("The recommended away answer says so, and no caption is heard twice", awayAnswersSpeakOnce)
    ]

    private static func awayAnswersSpeakOnce() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            // Compact hides the captions and carries them as tooltips instead;
            // both layouts must say each caption exactly once.
            for showsCaptions in [false, true] {
                let host = NSHostingView(rootView: AwayAnswerGrid(
                    away: 22 * 60,
                    range: (Date(timeIntervalSince1970: 1_800_000_000),
                            Date(timeIntervalSince1970: 1_800_001_320)),
                    showsCaptions: showsCaptions,
                    compact: !showsCaptions,
                    onAnswer: { _ in true },
                    onReason: { _ in true })
                    .frame(width: 520))
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000,
                                                          width: 560, height: 620),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.frame = window.contentView?.bounds ?? .zero
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                host.layoutSubtreeIfNeeded()
                let buttons = descendants(in: host, of: AwayAnswerNSButton.self)
                let layout = showsCaptions ? "captioned" : "compact"
                if buttons.count != 4 {
                    failures.append("The \(layout) grid exposed \(buttons.count) answers, not 4")
                }
                let labels = buttons.map { $0.accessibilityLabel() ?? "" }
                let recommended = labels.filter { $0.contains(", recommended.") }
                if recommended.count != 1 || recommended.first?.hasPrefix("It was a break") != true {
                    failures.append("The \(layout) grid did not name one recommended answer: \(labels)")
                }
                for button in buttons {
                    let label = button.accessibilityLabel() ?? ""
                    guard let caption = label.components(separatedBy: ". ").last,
                          !caption.isEmpty else {
                        failures.append("An answer lost its caption: \(label)")
                        continue
                    }
                    if let help = button.accessibilityHelp(), help.contains(caption) {
                        failures.append("\"\(caption)\" is heard twice in the \(layout) grid")
                    }
                }
                window.contentView = nil
            }
            return failures
        }
    }

    @MainActor private static func descendants<T: NSView>(in view: NSView,
                                                           of type: T.Type) -> [T] {
        var found = view as? T != nil ? [view as! T] : []
        for child in view.subviews { found.append(contentsOf: descendants(in: child, of: type)) }
        return found
    }
}
