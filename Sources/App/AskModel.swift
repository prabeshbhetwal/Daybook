import AppKit
import Combine
import FoundationModels

/// Why Ask has no answer to show, in a line the sheet can print. `opensSettings`
/// adds the button that opens the pane that fixes it.
struct AskNotice: Equatable {
    let text: String
    let opensSettings: Bool
}

/// Ask Daybook's state: the question, the answer as it streams in, the
/// lookups it rested on, and the on-device model's session. Nothing here
/// writes; the model reaches the history only through the store's lookups.
@MainActor final class AskModel: ObservableObject {
    @Published private(set) var question = ""
    @Published private(set) var answer = ""
    /// `Used: a · b`, one entry per lookup made for the current answer.
    @Published private(set) var used = ""
    @Published private(set) var notice: AskNotice?
    @Published private(set) var isAnswering = false

    private weak var store: SessionStore?
    /// A `LanguageModelSession`, held untyped so this class compiles below macOS 26.
    private var session: AnyObject?
    private var answering: Task<Void, Never>?
    /// Counts the sessions dropped so far. A session's tools carry the number
    /// it was built under, and their lookups reach `used` only while it is
    /// still current, so a late answer cannot write into the next one.
    private(set) var generation = 0
    /// The day the session was built under, as its "Today is …" says. A
    /// menu-bar app keeps the thread for days.
    private(set) var sessionDay: Date?
    /// Checks only: stands in for the model's session. It gets the question and
    /// a callback for the answer so far, may call `lookup` as a tool would, and
    /// may throw. Nothing in the app sets it.
    var responder: (@MainActor (String, (String) -> Void) async throws -> Void)?

    init(store: SessionStore) {
        self.store = store
    }

    var canAsk: Bool { ModelGate.modelAvailable }

    /// When the sheet appears: say what is missing, or start the model loading.
    func prepare() {
        retireStaleSession()
        guard #available(macOS 26, *) else { notice = Self.needsNewerMacOS; return }
        notice = Self.notice(for: SystemLanguageModel.default.availability)
        if notice == nil { liveSession().prewarm() }
    }

    func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnswering else { return }
        retireStaleSession()
        guard #available(macOS 26, *) else { notice = Self.needsNewerMacOS; return }
        if responder == nil, let missing = Self.notice(for: SystemLanguageModel.default.availability) {
            notice = missing
            return
        }
        // A failed answer puts these back: the answer on screen and the
        // lookups it rested on go together.
        let before = (answer: answer, used: used)
        question = trimmed
        answer = ""
        used = ""
        notice = nil
        isAnswering = true
        sessionDay = sessionDay ?? dayStart()
        answering = Task { await respond(to: trimmed, restoring: before) }
    }

    func newQuestion() {
        answering?.cancel()
        answering = nil
        dropSession()
        isAnswering = false
        question = ""
        answer = ""
        used = ""
        notice = nil
    }

    /// What a tool asks for. The synchronous lookup rebuilds History's day
    /// index when it is behind, so this is called only when a tool runs. A
    /// tool from a dropped session still gets its figure, but it is not
    /// listed under an answer it took no part in.
    func lookup(_ request: AskRequest, generation: Int) -> String {
        let text = store?.askLookup(request) ?? ""
        if generation == self.generation { used += (used.isEmpty ? "Used: " : " · ") + request.provenance }
        return text
    }

    /// The period a tool's text names, read in the store's calendar and clock,
    /// so "monday" is the Monday the lookups mean; nil when it names none.
    func range(_ raw: String) -> AskRange? {
        AskRange.resolving(raw, now: store?.now() ?? Date(), calendar: store?.periodCalendar ?? Calendar.current.forPeriods)
    }

    /// The thread's session carries the date it was built under, so one kept
    /// across midnight is dropped when the sheet opens and when a question is
    /// asked, unless an answer is being worked out. A sheet left open past
    /// midnight is not opened again. What the sheet shows stays; the next ask
    /// builds a session under today's date.
    func retireStaleSession() {
        guard !isAnswering, let built = sessionDay, built != dayStart() else { return }
        dropSession()
    }

    private func dropSession() {
        session = nil
        sessionDay = nil
        generation += 1
    }

    func openIntelligenceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// For snapshots and fixtures only: shows an answer without asking the model.
    func present(answer: String, used: String) {
        self.answer = answer
        self.used = used
    }

    // MARK: - The model

    @available(macOS 26, *)
    private func respond(to text: String, restoring before: (answer: String, used: String)) async {
        var failure: Error?
        let show: (String) -> Void = { [weak self] partial in
            if !Task.isCancelled { self?.answer = partial }
        }
        do {
            if let responder {
                try await responder(text, show)
            } else {
                for try await snapshot in liveSession().streamResponse(to: text, options: Self.options) {
                    if Task.isCancelled { break }
                    show(snapshot.content)
                }
            }
        } catch {
            failure = error
        }
        // A new question has already reset everything this answer would touch.
        guard !Task.isCancelled else { return }
        if let failure {
            answer = before.answer
            used = before.used
            notice = Self.notice(for: failure)
            if notice == Self.threadFull { dropSession() }
        }
        isAnswering = false
        answering = nil
    }

    /// Greedy: the same question over the same history gets the same tools
    /// and the same answer. Sampled, one question picked a different tool
    /// from run to run, sometimes the wrong one (probe, 2026-10-10). The
    /// macOS 27 SDK renames the argument and deprecates the old name.
    @available(macOS 26, *)
    private static var options: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }

    @available(macOS 26, *)
    private func liveSession() -> LanguageModelSession {
        if let existing = session as? LanguageModelSession { return existing }
        let fresh = LanguageModelSession(tools: [FocusTotalsTool(model: self, generation: generation),
                                                 CompareFocusTool(model: self, generation: generation),
                                                 BestHoursTool(model: self, generation: generation),
                                                 FindSessionsTool(model: self, generation: generation),
                                                 AppTimeTool(model: self, generation: generation)],
                                         instructions: Self.instructions(today: today()))
        session = fresh
        sessionDay = dayStart()
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
    /// taken for a habit.
    static func instructions(today: String) -> String {
        "You answer questions about the user's own focus history in Daybook. Today is \(today). "
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
    }

    // MARK: - Notices

    nonisolated static let needsNewerMacOS = AskNotice(text: "Ask needs macOS 26 or later.", opensSettings: false)
    private nonisolated static let threadFull = AskNotice(text: "Started a new thread — the last one was full.",
                                                          opensSettings: false)
    private nonisolated static let cannotAnswer = AskNotice(text: "Can't answer that one.", opensSettings: false)
    private nonisolated static let unsupportedLanguage = AskNotice(text: "Ask doesn't understand this language yet.",
                                                       opensSettings: false)

    @available(macOS 26, *)
    nonisolated static func notice(for availability: SystemLanguageModel.Availability) -> AskNotice? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return AskNotice(text: "This Mac can't run Apple's on-device model.", opensSettings: false)
        case .unavailable(.appleIntelligenceNotEnabled):
            return AskNotice(text: "Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri.",
                             opensSettings: true)
        case .unavailable(.modelNotReady):
            return AskNotice(text: "The on-device model is still downloading. Try again shortly.", opensSettings: false)
        case .unavailable:
            return AskNotice(text: "Ask isn't available on this Mac right now.", opensSettings: false)
        }
    }

    /// macOS 26 throws `GenerationError`; macOS 27 throws `LanguageModelError`
    /// to an app built with its SDK (probed 2026-10-09), and only that SDK
    /// has the type. Anything not listed is worded from the error itself.
    @available(macOS 26, *)
    nonisolated static func notice(for error: Error) -> AskNotice {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize: return threadFull
            case .guardrailViolation, .refusal: return cannotAnswer
            case .unsupportedLanguageOrLocale: return unsupportedLanguage
            default: break
            }
        }
        #if compiler(>=6.4)
        if #available(macOS 27, *), let model = error as? LanguageModelError {
            switch model {
            case .contextSizeExceeded: return threadFull
            case .guardrailViolation, .refusal: return cannotAnswer
            case .unsupportedLanguageOrLocale: return unsupportedLanguage
            default: break
            }
        }
        #endif
        return AskNotice(text: "Couldn't answer: \(error.localizedDescription)", opensSettings: false)
    }
}
