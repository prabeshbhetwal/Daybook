import AppKit
import Combine
import FoundationModels

/// Ask Daybook's state: the chat so far, one turn for each question, and the
/// on-device model's session. Nothing here writes; the model reaches the
/// history only through the store's lookups, one `AskGate` for each answer.
/// Answering, Stop and the retry after a full context are in `AskModel+Answer`.
@MainActor final class AskModel: ObservableObject {
    /// The chat, oldest first. Only the last turn can be in progress, and the
    /// turns before it never change.
    @Published private(set) var turns: [AskTurn] = []
    /// Why Ask cannot answer at all, such as no model on this Mac. An answer
    /// that fails shows its notice on its own turn.
    @Published private(set) var notice: AskNotice?
    /// Whether the on-device model can be asked now (`ModelGate.modelAvailable`),
    /// as of the last time Ask checked: `prepare()`, `ask(_:)` and `newChat()`.
    /// Read from here by the views, since asking Apple's model costs more than a view should.
    @Published private(set) var canAsk: Bool

    private(set) weak var store: SessionStore?
    /// A `LanguageModelSession`, held untyped so this class compiles below macOS 26.
    private var session: AnyObject?
    /// The answer in progress: its gate, and the task that works it out. Both
    /// are nil between answers. Only `AskModel+Answer` sets them.
    var gate: AskGate?
    var answering: Task<Void, Never>?
    /// Counts the sessions dropped so far. A session's tools carry the number
    /// it was built under, and their lookups reach an answer only while it is
    /// still current, so a late lookup cannot write into the next answer.
    private(set) var generation = 0
    /// The day the session was built under, as its "Today is …" says. A
    /// menu-bar app keeps the chat for days.
    private(set) var sessionDay: Date?
    /// The last two finished turns of a session that was dropped, for the next
    /// session to be told. Nothing is carried past midnight or a new chat.
    private(set) var carried: [AskTurn] = []
    /// The day those turns were asked on, while no session dates them.
    private var carriedDay: Date?
    /// Where today's turns begin in `turns`: the first one asked since a session
    /// was dropped for a new day. Earlier turns stay on screen, but they are never
    /// carried, because their "today" and "yesterday" mean other days now.
    private var firstTurnToday = 0
    /// Checks only: stands in for the model's session. It gets the question and
    /// a callback for the answer so far, may call `lookup` as a tool would, and
    /// may throw. Nothing in the app sets it.
    var responder: (@MainActor (String, (String) -> Void) async throws -> Void)?

    init(store: SessionStore) {
        self.store = store
        canAsk = ModelGate.modelAvailable
    }

    var isAnswering: Bool { turns.last?.state.isInProgress == true }

    /// Reads the check Ask shares with the written notes again. It can change
    /// while the app runs, so it is read when Ask opens and when a chat starts
    /// or a question is asked, not each time a view is drawn.
    func refreshAvailability() {
        let available = ModelGate.modelAvailable
        if canAsk != available { canAsk = available }
    }

    /// When the sheet appears: say what is missing, or start the model loading.
    func prepare() {
        refreshAvailability()
        retireStaleSession()
        guard #available(macOS 26, *) else { notice = Self.needsNewerMacOS; return }
        notice = Self.notice(for: SystemLanguageModel.default.availability)
        if notice == nil { liveSession().prewarm() }
    }

    func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnswering else { return }
        refreshAvailability()
        retireStaleSession()
        guard #available(macOS 26, *) else { notice = Self.needsNewerMacOS; return }
        if responder == nil, let missing = Self.notice(for: SystemLanguageModel.default.availability) {
            notice = missing
            return
        }
        notice = nil
        let turn = AskTurn(question: trimmed)
        turns.append(turn)
        begin(turn.id, question: trimmed, retrying: false)
    }

    /// Cancels any answer, empties the chat and drops the session.
    func newChat() {
        closeRun()
        dropSession(carrying: false)
        turns = []
        firstTurnToday = 0
        notice = nil
        refreshAvailability()
    }

    /// Changes one turn, for the answer working it out; a turn no longer there is left alone.
    func update(_ id: UUID, _ change: (inout AskTurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    /// What a tool asks for. An answer in progress, asked in the session it began
    /// under, goes through its gate. Any other lookup, such as a tool of a session
    /// that was dropped, still gets its figure but is recorded nowhere.
    /// The synchronous lookup rebuilds History's day index when it is behind, so
    /// this is called only when a tool runs.
    func lookup(name: String, arguments: [String: String], generation: Int) -> String {
        if generation == self.generation, isAnswering, let gate, gate.isOpen {
            return gate.lookup(name: name, arguments: arguments)
        }
        let closed = makeGate()
        closed.isOpen = false
        return closed.lookup(name: name, arguments: arguments)
    }

    /// The period a tool's text names, read in the store's calendar and clock,
    /// so "monday" is the Monday the lookups mean; nil when it names none.
    func range(_ raw: String) -> AskRange? {
        AskRange.resolving(raw, now: store?.now() ?? Date(), calendar: store?.periodCalendar ?? Calendar.current.forPeriods)
    }

    /// The session carries the date it was built under, so one kept across
    /// midnight is dropped when the sheet opens and when a question is asked,
    /// unless an answer is being worked out, and nothing it said is carried
    /// into the next. A sheet left open past midnight is not opened again. What
    /// the sheet shows stays; the next ask builds a session under today's date.
    func retireStaleSession() {
        guard !isAnswering, let built = sessionDay ?? carriedDay, built != dayStart() else { return }
        dropSession(carrying: false)
        firstTurnToday = turns.count
    }

    /// Forgets the model's session, so a tool still running for it is stale.
    /// `carrying` keeps the last two finished turns of today, for the next
    /// session to be told what was said; without it nothing is carried.
    func dropSession(carrying: Bool) {
        carried = carrying ? Array(turns.dropFirst(firstTurnToday).filter { $0.state == .answered }.suffix(2)) : []
        carriedDay = carrying ? sessionDay ?? dayStart() : nil
        session = nil
        sessionDay = nil
        generation += 1
    }

    /// An answer started under today's date dates the session it belongs to.
    func stampSessionDay() {
        sessionDay = sessionDay ?? dayStart()
    }

    func openIntelligenceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// For snapshots and fixtures only: shows a chat without asking the model.
    func present(turns: [AskTurn]) {
        closeRun()
        self.turns = turns
        firstTurnToday = 0
    }

    // MARK: - The model

    @available(macOS 26, *)
    func liveSession() -> LanguageModelSession {
        if let existing = session as? LanguageModelSession { return existing }
        let tools = AskLookups.all.compactMap { try? AskOnDeviceTool($0, model: self, generation: generation) }
        let instructions = Self.instructions(today: today(), carrying: carried)
        let fresh = LanguageModelSession(tools: tools, instructions: instructions)
        session = fresh
        sessionDay = dayStart()
        carried = []
        carriedDay = nil
        return fresh
    }

    /// Today in the calendar the periods are worked out in, so "this week"
    /// means the same day to the model as to the lookups.
    private func today() -> String {
        let calendar = store?.periodCalendar ?? Calendar.current.forPeriods
        let format = DateFormats.australian("EEEE d MMMM yyyy", in: calendar.timeZone)
        return format.string(from: store?.now() ?? Date())
    }

    private func dayStart() -> Date {
        (store?.periodCalendar ?? Calendar.current.forPeriods).startOfDay(for: store?.now() ?? Date())
    }

    /// Each rule answers a way the on-device model went wrong in a probe of
    /// twenty questions (2026-10-10): a month given as the best day, a past
    /// period in the present tense, September's figures given for August,
    /// sums and averages of its own that were wrong, and today's figures
    /// taken for a habit. A session built after Stop or a full context is
    /// told the turns it replaces, as plain text with no lookup output.
    static func instructions(today: String, carrying: [AskTurn] = []) -> String {
        let said = carrying.map {
            " Earlier in this chat the user asked “\($0.question)” and you answered “\($0.answer)”."
        }
        return "You answer questions about the user's own focus history in Daybook. Today is \(today). "
            + "Look figures up with the tools and answer only from what they return. "
            + "Give the tools the period as the question says it, such as this week, monday, august, "
            + "3 october or 2025, and let the tools work out the dates. "
            + "When the question names no period, use all time; questions about habits, such as "
            + "when do I focus best, cover all time. "
            + "To compare two periods, use compareFocus with each period as the question says it. "
            + "If a tool says a date does not exist, tell the user so. "
            + "Answer what was asked: a question about a day is answered with a day, not a week or a month. "
            + "Copy durations, dates, times and names exactly as the tools give them. "
            + "Never add, subtract, average or compare numbers yourself; the tools give totals, averages, "
            + "the longest session and the difference between two periods. "
            + "Speak of days and periods that are over in the past tense. "
            + "If the tools find nothing, say so plainly. Answer in one to three sentences."
            + said.joined()
    }
}
