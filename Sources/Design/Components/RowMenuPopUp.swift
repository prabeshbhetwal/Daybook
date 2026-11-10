import AppKit
import SwiftUI

/// Opens a `RowMenu`'s choices as a native menu over the control, the current
/// choice checked and placed over the label, as a pop-up button does. Used
/// before macOS 27, where a SwiftUI menu button ignores the shared width.
@MainActor final class RowMenuAnchor {
    fileprivate weak var view: NSView?
    private var handler: RowMenuHandler?

    func popUp<Value: Hashable>(_ items: [RowMenuItem<Value>], selected: Value,
                                choose: @escaping (Value) -> Void) {
        guard let view else { return }
        let handler = RowMenuHandler()
        self.handler = handler
        let menu = NSMenu()
        menu.font = .systemFont(ofSize: Tokens.Typography.pointSize(of: .control))
        menu.minimumWidth = view.bounds.width
        var current: NSMenuItem?
        for item in items {
            switch item {
            case .divider:
                menu.addItem(.separator())
            case let .option(value, text, systemImage):
                let entry = NSMenuItem(title: text, action: #selector(RowMenuHandler.choose(_:)),
                                       keyEquivalent: "")
                entry.target = handler
                entry.representedObject = { choose(value) }
                if let systemImage {
                    entry.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                }
                if value == selected {
                    entry.state = .on
                    current = entry
                }
                menu.addItem(entry)
            }
        }
        // The positioned item's top-left goes at this point: the control's.
        let topLeft = NSPoint(x: view.bounds.minX, y: view.isFlipped ? view.bounds.minY : view.bounds.maxY)
        menu.popUp(positioning: current, at: topLeft, in: view)
        self.handler = nil
    }
}

private final class RowMenuHandler: NSObject {
    @objc func choose(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}

/// The plain view a `RowMenuAnchor` opens its menu from, laid behind the button.
struct RowMenuAnchorView: NSViewRepresentable {
    let anchor: RowMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
