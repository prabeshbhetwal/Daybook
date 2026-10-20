import AppKit

/// What the coordinator decides about a break reminder, apart from the
/// panels, so each decision is checked without a screen.
extension AppCoordinator {
    /// Whether a reminder shown now would be seen by the person: the three
    /// states of the machine, and the store's own word on whether they are
    /// away or have yet to show they are back after a wake.
    static func breakReminderReachesScreen(store: SessionStore,
                                           screenLocked: Bool,
                                           displayAsleep: Bool,
                                           machineSleeping: Bool) -> Bool {
        breakReminderReachesScreen(screenLocked: screenLocked, displayAsleep: displayAsleep,
                                   machineSleeping: machineSleeping, away: store.isAway,
                                   awaitingPresence: store.isAwaitingPresence)
    }

    /// The HUD for a reminder that answers with buttons (every tier but
    /// Eyes). Start is on it only where the store would begin a break, and
    /// VoiceOver is told of the menu bar's Take a break only then. A reminder
    /// left with no button at all is shown without a row, and going away
    /// unanswered is what the log records.
    static func breakReminderContent(_ prompt: BreakPrompt, store: SessionStore,
                                     answer: @escaping (BreakHUDAction) -> Void) -> BreakHUDContent {
        let canStart = store.canTakeBreak
        let copy = BreakHUDCopy.reminder(prompt, canStart: canStart)
        let buttons = copy.buttons.enumerated().map { index, choice in
            BreakHUDButton(title: choice.title, isPrimary: index == 0) { answer(choice.action) }
        }
        return BreakHUDContent(
            title: copy.title, detail: copy.detail, symbolName: prompt.tier.symbolName,
            buttons: buttons, duration: FocusConstants.breakHUDSeconds,
            onTimeout: { [weak store] in store?.breakPromptUnanswered(prompt) },
            mentionsMenuBar: canStart)
    }
}
