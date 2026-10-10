import Foundation

/// Where Ask Daybook opens, and what following one of its sources does.
extension MainWindowModel {
    /// The saved choice, read each time Ask opens so a change in Settings is
    /// used by the next ⌘K with nothing to wire.
    var askPlacement: AskPlacement { store?.engine.store.askPlacement ?? .sheet }

    /// ⌘K, the bar's Ask button and Settings' Open Ask. Builds Ask's model on
    /// first use and keeps it, so reopening shows the last answer. The sheet
    /// opens over the window; the side panel toggles. A sheet already over the
    /// window (Settings, Awards) closes first, and the panel then opens rather
    /// than toggles, since it cannot be seen under that sheet.
    func openAsk() {
        if askModel == nil, let store { askModel = AskModel(store: store) }
        switch askPlacement {
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
