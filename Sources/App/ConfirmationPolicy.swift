import SwiftUI

/// Whether the app still asks before an action Undo can reverse, read at the
/// moment the action is chosen, and the way a "Don't ask again" tick turns
/// that off. Outside a window that sets it, every confirmation asks.
struct ConfirmationPolicy {
    var asks: (Confirmation) -> Bool = { _ in true }
    var stopAsking: (Confirmation) -> Void = { _ in }
}

private struct ConfirmationPolicyKey: EnvironmentKey {
    static let defaultValue = ConfirmationPolicy()
}

extension EnvironmentValues {
    var confirmationPolicy: ConfirmationPolicy {
        get { self[ConfirmationPolicyKey.self] }
        set { self[ConfirmationPolicyKey.self] = newValue }
    }
}

/// The "Don't ask again" tick of one showing of a confirmation. It counts
/// only with the confirming button, so a tick followed by Cancel keeps
/// asking. macOS may report the tick before or after that button runs, so
/// either order settles the same way.
final class DontAskAgain: ObservableObject {
    let confirmation: Confirmation
    private var ticked = false
    private var confirmed = false

    init(_ confirmation: Confirmation) {
        self.confirmation = confirmation
    }

    /// Clears the tick before the dialog shows again.
    func reset() {
        ticked = false
        confirmed = false
    }

    /// The binding for `dialogSuppressionToggle`.
    func tick(_ policy: ConfirmationPolicy) -> Binding<Bool> {
        Binding(get: { self.ticked }, set: { self.ticked = $0; self.settle(policy) })
    }

    /// Called by the confirming button, after its action.
    func confirm(_ policy: ConfirmationPolicy) {
        confirmed = true
        settle(policy)
    }

    private func settle(_ policy: ConfirmationPolicy) {
        if ticked && confirmed { policy.stopAsking(confirmation) }
    }
}
