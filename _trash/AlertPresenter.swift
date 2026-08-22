import Cocoa

/// Builds and presents the two modal alerts. Enforces single-alert-at-a-time
/// (D10) and the activation-policy dance that forces focus after a wake (D11).
final class AlertPresenter {

    private(set) var isPresentingAlert = false

    /// Extended-break resolution. `completion` runs on the main thread once the
    /// alert is dismissed; it is never called if an alert is already up.
    func presentExtendedBreak(away: TimeInterval,
                              lastApp: String,
                              afterDelay delay: TimeInterval,
                              completion: @escaping (UserDecision) -> Void) {
        guard !isPresentingAlert else {
            Diagnostics.log("suppressed a second extended-break alert")
            return
        }
        isPresentingAlert = true

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "You were away for \(Self.humanDuration(away))."
            alert.informativeText = "Last active app: \(lastApp).\n\n"
                + "Merge Time counts the break as work. "
                + "Continue Session discards it. "
                + "Reset Timer archives this session and starts a new one."
            alert.addButton(withTitle: "Merge Time")
            alert.addButton(withTitle: "Continue Session")
            alert.addButton(withTitle: "Reset Timer")

            let response = self.runFocused(alert)
            self.isPresentingAlert = false

            switch response {
            case .alertFirstButtonReturn: completion(.mergeTime)
            case .alertSecondButtonReturn: completion(.continueSession)
            case .alertThirdButtonReturn: completion(.resetTimer)
            default: completion(.continueSession)
            }
        }
    }

    /// Session rename prompt (⌘N).
    func presentRename(currentName: String, completion: @escaping (String) -> Void) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Name this session"
        alert.informativeText = "Shown in the menu bar next to the elapsed time."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = currentName
        field.placeholderString = "Refactor"
        alert.accessoryView = field

        let response = runFocused(alert) { field.window?.makeFirstResponder(field) }
        isPresentingAlert = false

        if response == .alertFirstButtonReturn {
            completion(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Focus forcing (D11)

    private func runFocused(_ alert: NSAlert,
                            beforeRun: (() -> Void)? = nil) -> NSApplication.ModalResponse {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        alert.window.center()
        beforeRun?()
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        return response
    }

    static func humanDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}
