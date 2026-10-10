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

    @MainActor init(store: SessionStore, usable: Bool) {
        guard usable else { return }
        if let place = store.yesterdayNotePlace() {
            yesterday = place
            yesterdayFigures = store.noteFiguresLine(for: place)
        }
        if store.wrapUpOffered { wrapUp = store.notePlace(forDayContaining: store.now()) }
    }

    /// What can change an offer: the day turning over, a session starting,
    /// stopping or pausing (the state), a session added or removed (the
    /// count), and the model becoming usable or not. The rail reads the model's
    /// availability once per redraw (about 215 µs of CPU) and passes it in.
    struct Cause: Equatable {
        let today: HistoryPlace
        let state: SessionState
        let sessions: Int
        let usable: Bool
    }

    @MainActor static func cause(store: SessionStore, usable: Bool) -> Cause {
        Cause(today: store.notePlace(forDayContaining: store.now()), state: store.state,
              sessions: store.sessionsToday, usable: usable)
    }
}

/// Places the offered notes at the top of the rail. Draws nothing, and takes
/// no space, when there is nothing to offer. Dismissing Yesterday's notice
/// clears it from the offers as well as recording the day, so it is not
/// offered again when the rail redraws or is shown again.
struct TodayNotes: View {
    let store: SessionStore
    let writer: NoteWriter?
    @Binding var offers: TodayNoteOffers
    /// Read once by the rail when it builds this view, and passed to the
    /// notes below; see `PeriodNote.usable`.
    private let usable: Bool
    /// Read when the rail builds this view; see `PeriodNote.evidence`.
    private let evidence: SessionStore.NoteEvidence

    init(store: SessionStore, writer: NoteWriter?, usable: Bool, offers: Binding<TodayNoteOffers>) {
        self.store = store
        self.writer = writer
        self.usable = usable
        _offers = offers
        evidence = store.noteEvidence
    }

    var body: some View {
        if let writer, usable {
            if let place = offers.yesterday {
                YesterdayNotice(writer: writer, place: place, figures: offers.yesterdayFigures,
                                evidence: evidence) {
                    store.dismissYesterdayNote(place)
                    offers.yesterday = nil
                }
                .id(place.id)
            }
            if let place = offers.wrapUp {
                PeriodNote(writer: writer, place: place, evidence: evidence,
                           trigger: .onRequest(label: "Wrap up today"), tipLabel: "For tomorrow:")
                    .noteCard()
                    .id(place.id)
            }
        }
    }
}
