import SwiftUI
import Combine

/// Decides how the away question is put — quick from the menu bar or full on a
/// blurred screen — and keeps both in step with the one pending question the
/// store publishes. Answering anywhere resolves everywhere; dismissing leaves
/// the popover card standing.
@MainActor
final class AwayPrompter {
    private let store: SessionStore
    private let fullPromptAfter: () -> TimeInterval?
    private lazy var quick = AwayQuickPanel(onAnswer: { [weak self] in self?.answer($0) },
                                            onReason: { [weak self] in self?.reason($0) })
    private lazy var full = AwayFullPrompt(onAnswer: { [weak self] in self?.answer($0) },
                                           onReason: { [weak self] in self?.reason($0) },
                                           onLater: { [weak self] in self?.dismiss() })
    private var subscription: AnyCancellable?
    private var wasPending = false

    init(store: SessionStore, fullPromptAfter: @escaping () -> TimeInterval?) {
        self.store = store
        self.fullPromptAfter = fullPromptAfter
    }

    /// Follows the store from now on. A question already pending — including
    /// one restored at launch — is presented by the same rule as any other:
    /// the user asked for a long absence to be put to them on a blurred screen,
    /// and a relaunch in the middle of one does not make it shorter.
    func start() {
        subscription = store.$pendingAway
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                guard let self else { return }
                if let away = pending {
                    if !self.wasPending { self.present(away: away) }
                    self.wasPending = true
                } else {
                    self.wasPending = false
                    self.dismiss()
                }
            }
    }

    private func present(away: TimeInterval) {
        let range = store.pendingAwayRange
        let note = store.continuationNote
        switch AwayPromptTier.tier(forAbsence: away, fullPromptAfter: fullPromptAfter()) {
        case .quick: quick.show(away: away, range: range, note: note)
        case .full: full.show(away: away, range: range, note: note)
        }
    }

    /// Re-opens the already-published question using its ordinary quick/full
    /// policy. The global hotkey calls this after the shared action boundary
    /// returns `.showAwayDecision`; it never manufactures or resolves evidence.
    @discardableResult
    func presentPendingDecision() -> Bool {
        guard let away = store.pendingAway else { return false }
        present(away: away)
        wasPending = true
        return true
    }

    private func answer(_ decision: UserDecision) {
        dismiss()
        store.resolve(decision)
    }

    /// "Dinner": a break, written down under that name.
    private func reason(_ label: String) {
        dismiss()
        store.resolve(.tookBreak, label: label)
    }

    func dismiss() {
        quick.dismiss()
        full.dismiss()
    }

    /// `--preview-away quick|full`: shows the prompt with sample figures so its
    /// layout can be checked on a real screen without staging an absence.
    /// Answers resolve nothing — there is no pending question — and only
    /// dismiss.
    func preview(_ tier: AwayPromptTier) {
        let now = Date()
        let range = (start: now.addingTimeInterval(-6 * 60), end: now)
        let note = "Not counted. Focus session continues — 5h 59m so far."
        switch tier {
        case .quick: quick.show(away: 6 * 60, range: range, note: note)
        case .full: full.show(away: 72 * 60, range: range, note: note)
        }
    }
}
