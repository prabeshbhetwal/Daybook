import SwiftUI
import AppKit

/// Break countdown on the left; the three places to go on the right. Icons
/// with tooltips rather than words — the footer is reached for, not read.
struct PopoverFooter: View {
    @ObservedObject var store: SessionStore
    var onOpenDashboard: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Label(store.breakLabel,
                  systemImage: store.isBreakDue ? "figure.walk" : "eye")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.isBreakDue ? AnyShapeStyle(.tint)
                                                  : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .explains("break", "Next break", breakDetail)
            Spacer(minLength: Tokens.Space.s)
            IconButton(systemImage: "rectangle.grid.2x2", help: "Open Dashboard",
                       action: onOpenDashboard)
            settingsButton
            IconButton(systemImage: "power", help: "Quit FocusContinuity") {
                NSApp.terminate(nil)
            }
        }
    }

    /// The gear. On macOS 14 and later the `Settings` scene is opened through
    /// the `openSettings` environment action — the responder-chain selector
    /// the 13 build uses stopped reaching a SwiftUI settings scene from a
    /// menu-bar app, which is why the button did nothing. ⌘, works while the
    /// popover is open; an accessory app has no main menu to carry it.
    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsGearButton()
        } else {
            IconButton(systemImage: "gearshape", help: "Settings…") {
                SettingsModel.openWindow()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private var breakDetail: String {
        let base = "Counts unbroken use of the Mac, not focus sessions, so it runs "
            + "whether or not you pressed Start. When it reaches zero a panel appears "
            + "in the corner and a notification is posted; neither takes focus and "
            + "neither pauses anything.\n\nPause and Stop do not reset it — you are "
            + "still sitting at the screen. Away does, and so does actually stepping "
            + "away for a few minutes. "
        guard let tier = store.nextBreakTier else { return base + "Nothing is due." }
        return base + "Next: after \(Int(tier.workThreshold / 60)) minutes at the machine, "
            + "\(BreakPrompt.phrase(tier.breakLength)) away. \(tier.reason)"
    }
}

@available(macOS 14.0, *)
private struct SettingsGearButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        IconButton(systemImage: "gearshape", help: "Settings…") {
            // Frontmost first, or the window opens behind whatever was.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
