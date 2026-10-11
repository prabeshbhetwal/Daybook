import Foundation

/// Where Ask Daybook opens, and what following one of its sources does.
extension MainWindowModel {
    /// The saved choice, read each time Ask opens so a change in Settings is
    /// used by the next ⌘K with nothing to wire.
    var askPlacement: AskPlacement { store?.engine.store.askPlacement ?? .sheet }

    /// Where Ask opens now: the saved choice, but the sheet where the window's
    /// screen cannot hold the side panel at this zoom. The saved choice itself
    /// is not changed, so the panel returns where there is room again.
    private var askOpensAs: AskPlacement {
        askPlacement == .panel && askPanelHasRoom ? .panel : .sheet
    }

    /// The window says whether its screen can hold the side panel at the
    /// current zoom (`AskLayout.panelHasRoom`), when it learns its screen and
    /// whenever the zoom or the screen changes. Room lost with the panel open
    /// closes it and opens the sheet on the same chat, unless another sheet is
    /// over the window, which stays; room regained changes nothing until the
    /// next ⌘K.
    func updateAskPanelRoom(_ hasRoom: Bool) {
        guard hasRoom != askPanelHasRoom else { return }
        askPanelHasRoom = hasRoom
        guard !hasRoom, askPanelOpen else { return }
        askPanelOpen = false
        if sheet == nil { openSheet(.ask) }
    }

    /// ⌘K, the bar's Ask button and Settings' Open Ask. Builds Ask's model on
    /// first use and keeps it, so reopening shows the last answer. The sheet
    /// opens over the window; the side panel toggles. A sheet already over the
    /// window (Settings, Awards) closes first, and the panel then opens rather
    /// than toggles, since it cannot be seen under that sheet.
    func openAsk() {
        if askModel == nil, let store { askModel = AskModel(store: store) }
        switch askOpensAs {
        case .sheet:
            askPanelOpen = false
            openSheet(.ask)
        case .panel:
            askPanelOpen = sheet != nil || !askPanelOpen
            dismissSheet()
        }
    }

    func closeAskPanel() {
        askPanelOpen = false
    }

    /// A source clicked in an answer: History at that day, session or period.
    /// The sheet closes first (⌘K brings the chat back); the side panel stays,
    /// so the source opens beside the chat. Every source opens History,
    /// today's included: one rule.
    func follow(_ link: AskLink) {
        open(tab: .review)
        switch link.target {
        case .day(let day):
            openHistory(day: day)
        case .session(let thread, let day):
            if store?.journalThreads(on: day, only: nil).contains(thread) == true {
                selectHistory(session: thread, on: day)
            } else {
                openHistory(day: day)
            }
        case .period(let place):
            openHistory(place: place)
        case .history:
            navigateHistory(to: nil)
        }
    }
}
