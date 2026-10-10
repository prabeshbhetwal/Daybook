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
    private let playHaptic: (HapticMoment) -> Void
    private lazy var quick = AwayQuickPanel(onAnswer: { [weak self] in self?.answer($0) ?? false },
                                            onReason: { [weak self] in self?.answer(.tookBreak, label: $0) ?? false },
                                            onRetry: { [weak self] in self?.retry() })
    private lazy var full = AwayFullPrompt(onAnswer: { [weak self] in self?.answer($0) ?? false },
                                           onReason: { [weak self] in self?.answer(.tookBreak, label: $0) ?? false },
                                           onRetry: { [weak self] in self?.retry() },
                                           onLater: { [weak self] in self?.dismiss() })
    private var subscription: AnyCancellable?
    private var wasPending = false
    private var presentedID: UUID?
    private var presentedTier: AwayPromptTier?
    private var isPreview = false

    init(store: SessionStore, fullPromptAfter: @escaping () -> TimeInterval?,
         playHaptic: @escaping (HapticMoment) -> Void = { _ in }) {
        self.store = store
        self.fullPromptAfter = fullPromptAfter
        self.playHaptic = playHaptic
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
                    // A question you did not ask for pulses; one you
                    // reopened with the hotkey (`presentPendingDecision`) does not.
                    if !self.wasPending {
                        self.present(away: away)
                        self.playHaptic(.awayQuestion)
                    }
                    self.wasPending = true
                } else {
                    self.wasPending = false
                    self.dismiss()
                }
            }
    }

    /// `takesFocus` when the person asked for the question; the full prompt
    /// always takes the keyboard, the quick one only then.
    private func present(away: TimeInterval, takesFocus: Bool = false) {
        let range = store.pendingAwayRange
        let note = store.continuationNote
        let tier = AwayPromptTier.tier(forAbsence: away, fullPromptAfter: fullPromptAfter())
        isPreview = false
        presentedID = store.engine.pendingDecisionID
        presentedTier = tier
        switch tier {
        case .quick: quick.show(away: away, range: range, note: note, takesFocus: takesFocus)
        case .full: full.show(away: away, range: range, note: note)
        }
        if let error = store.pendingAwaySaveError {
            switch tier {
            case .quick: quick.showError(error)
            case .full: full.showError(error)
            }
        }
    }

    /// Re-opens the already-published question using its ordinary quick/full
    /// policy. The global hotkey calls this after the shared action boundary
    /// returns `.showAwayDecision`; it never manufactures or resolves evidence.
    /// The quick card takes the keyboard here: a keyboard user who pressed the
    /// hotkey had no other way to reach it.
    @discardableResult
    func presentPendingDecision() -> Bool {
        guard let away = store.pendingAway else { return false }
        present(away: away, takesFocus: true)
        wasPending = true
        return true
    }

    private func answer(_ decision: UserDecision, label: String? = nil) -> Bool {
        if isPreview { dismiss(); return true }
        guard let presentedID else { return false }
        return finish(store.resolve(decision, label: label, expectedID: presentedID))
    }

    private func retry() {
        guard let presentedID, presentedID == store.engine.pendingDecisionID else { return }
        guard store.pendingAwaySaveError != nil else {
            showError("Choose an answer again. The previous retry no longer belongs to this question.")
            return
        }
        _ = finish(store.retryPendingAwayDecision(expectedID: presentedID))
    }

    /// Failure is not dismissal. Keep the user's answer surface and reason
    /// draft visible, and stop the quick prompt's automatic fade while retrying.
    private func finish(_ saved: Bool) -> Bool {
        if saved { dismiss(); return true }
        let error = store.correctionError ?? "This interval changed. Reopen its question from session controls."
        showError(error)
        return false
    }

    private func showError(_ error: String) {
        switch presentedTier {
        case .quick: quick.showError(error)
        case .full: full.showError(error)
        case nil: break
        }
    }

    func dismiss() {
        quick.dismiss()
        full.dismiss()
        presentedID = nil
        presentedTier = nil
        isPreview = false
    }

    /// `--preview-away quick|full`: shows the prompt with sample figures so its
    /// layout can be checked on a real screen without staging an absence.
    /// Answers resolve nothing — there is no pending question — and only
    /// dismiss.
    func preview(_ tier: AwayPromptTier) {
        let now = Date()
        let range = (start: now.addingTimeInterval(-6 * 60), end: now)
        let note = "Not counted. Focus session continues — 5h 59m so far."
        isPreview = true
        presentedID = nil
        presentedTier = tier
        switch tier {
        case .quick: quick.show(away: 6 * 60, range: range, note: note)
        case .full: full.show(away: 72 * 60, range: range, note: note)
        }
    }
}
