import Foundation
import SwiftUI
import AppKit

/// The break's own controls: their size and what VoiceOver calls them.
extension BreakSeamChecks {
    static func lengthChevronMeetsTargetSize() -> [String] {
        MainActor.assumeIsolated {
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            let host = NSHostingView(rootView: FocusTakeBreakMenu(store: f.store))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            var controls: [NSRect] = []
            func walk(_ view: NSView) {
                let rect = view.convert(view.bounds, to: host)
                // Only the platform-backed controls are visible to an
                // in-process walk; SwiftUI-drawn text never appears.
                if rect.width > 0, rect.height > 0,
                   String(describing: type(of: view)).contains("_FocusRingView") {
                    controls.append(rect)
                }
                view.subviews.forEach(walk)
            }
            withExtendedLifetime(window) { walk(host) }
            // Take a break, then the arrow beside it: the arrow is the last.
            guard controls.count == 2, let chevron = controls.max(by: { $0.minX < $1.minX }) else {
                return ["expected the button and the length menu, found \(controls)"]
            }
            let floor = AccessibilityMetrics.minimumTargetSize
            guard chevron.width >= floor, chevron.height >= floor else {
                return ["the length chevron is \(Int(chevron.width))x\(Int(chevron.height)) pt, "
                        + "under the \(Int(floor)) pt target"]
            }
            return []
        }
    }

    static func spokenNamesContainVisibleText() -> [String] {
        var problems: [String] = []
        // WCAG 2.5.3: the name VoiceOver says contains the words on the control.
        for option in BreakChoice.options {
            expect(option.spoken.lowercased().contains(option.title.lowercased()),
                   "\"\(option.spoken)\" does not contain the visible \"\(option.title)\"", &problems)
        }
        return problems
    }

    static func extendNameContainsVisibleText() -> [String] {
        var problems: [String] = []
        let extend = BreakChoice.extend
        expect(extend.title == "+5 min", "the button reads +5 min, got \(extend.title)", &problems)
        expect(extend.spoken.lowercased().contains(extend.title.lowercased()),
               "\"\(extend.spoken)\" does not contain the visible \"\(extend.title)\"", &problems)
        expect(extend.spoken.contains("5 minutes"), "and it still says how much, got \(extend.spoken)", &problems)
        return problems
    }
}
