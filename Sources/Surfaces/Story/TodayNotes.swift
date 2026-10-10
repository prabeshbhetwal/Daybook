import SwiftUI

/// The notes Today's rail offers: Yesterday's, and today's wrap-up.
///
/// Working out either reads day projections, and the rail redraws every
/// second with the store, so the rail holds the answer in `@State` and builds
/// it again only when its `cause` changes. Nothing is worked out while the
/// model is unusable.
struct TodayNoteOffers: Equatable {
    var yesterday: HistoryPlace?
    var yesterdayFigures = ""
    var wrapUp: HistoryPlace?

    init() {}

    @MainActor init(store: SessionStore, writer: NoteWriter?) {
        guard writer?.isUsable == true else { return }
        if let place = store.yesterdayNotePlace() {
            yesterday = place
            yesterdayFigures = store.noteFiguresLine(for: place)
        }
        if store.wrapUpOffered { wrapUp = store.notePlace(forDayContaining: store.now()) }
    }

    /// What can change an offer: the day turning over, a session starting,
    /// stopping or pausing (the state), a session added or removed (the
    /// count), and the model becoming usable or not. Cheap to read.
    struct Cause: Equatable {
        let today: HistoryPlace
        let state: SessionState
        let sessions: Int
        let usable: Bool
    }

    @MainActor static func cause(store: SessionStore, writer: NoteWriter?) -> Cause {
        Cause(today: store.notePlace(forDayContaining: store.now()), state: store.state,
              sessions: store.sessionsToday, usable: writer?.isUsable == true)
    }
}

/// Places the offered notes at the top of the rail. Draws nothing, and takes
/// no space, when there is nothing to offer.
struct TodayNotes: View {
    let store: SessionStore
    let writer: NoteWriter?
    let offers: TodayNoteOffers

    var body: some View {
        if let writer {
            if let place = offers.yesterday {
                YesterdayNotice(store: store, writer: writer, place: place, figures: offers.yesterdayFigures)
                    .id(place.id)
            }
            if let place = offers.wrapUp {
                PeriodNote(writer: writer, place: place, trigger: .onRequest(label: "Wrap up today"),
                           tipLabel: "For tomorrow:")
                    .noteCard()
                    .id(place.id)
            }
        }
    }
}
