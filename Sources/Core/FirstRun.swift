import Foundation

/// The welcome's steps, in order. Three of them ask the user to do something
/// and wait; the rest are read and stepped past.
enum FirstRunBeat: String, CaseIterable, Identifiable {
    case welcome
    case controls
    case start
    case apps
    case spans
    case finish

    var id: String { rawValue }

    var next: FirstRunBeat? {
        guard let index = Self.allCases.firstIndex(of: self),
              index + 1 < Self.allCases.count else { return nil }
        return Self.allCases[index + 1]
    }
}

/// What a beat waits for. The welcome never simulates any of these: each one
/// is satisfied by the same state the rest of the app reads, so what the user
/// is shown afterwards is the real consequence of what they did.
enum FirstRunTask: String, CaseIterable {
    case openControls
    case startSession
    case useAnotherApp
}

/// The part of the window a card points at.
enum CoachAnchor: String, CaseIterable, Hashable {
    /// The chrome's "Start focus", which reveals the session strip.
    case sessionControl
    /// The strip's activity field and its real Start.
    case activityField
    /// The rail of tiles down the right.
    case rail
    /// Day · Week · Month.
    case scopePills
    /// The gear.
    case settings
}

/// The window state a beat can be waiting on. Gathered by the view and handed
/// in; nothing in this file knows about SwiftUI.
struct FirstRunSignals: Equatable {
    var sessionControlsVisible = false
    var sessionRunning = false
    var otherAppRecorded = false

    func satisfies(_ task: FirstRunTask) -> Bool {
        switch task {
        case .openControls: return sessionControlsVisible
        case .startSession: return sessionRunning
        case .useAnotherApp: return otherAppRecorded
        }
    }
}

enum FirstRunPhase: String, Equatable {
    /// Asking, and waiting for the user to do it.
    case asking
    /// They did it, and the card is naming what changed.
    case done
}

/// Whether this Mac has met the app before.
///
/// Emptiness is checked as well as the flag so that the build which first
/// ships a welcome does not ambush everyone already using the app: a machine
/// with history has plainly been onboarded, whatever the flag says.
enum FirstRunGate {
    static func shouldWelcome(onboarded: Bool,
                              hasSessionHistory: Bool,
                              hasUsageHistory: Bool,
                              forced: Bool) -> Bool {
        if forced { return true }
        return !onboarded && !hasSessionHistory && !hasUsageHistory
    }
}

/// Where the reader is in the welcome. A value type with no dependencies, so
/// the whole flow can be driven and asserted without rendering anything.
struct FirstRunProgress: Equatable {
    private(set) var beat: FirstRunBeat = .welcome
    private(set) var phase: FirstRunPhase = .asking
    private(set) var isFinished = false
    /// Tasks the user actually did, as against stepped past. Kept so the
    /// closing card can stay honest about what they have really seen.
    private(set) var performed: Set<FirstRunTask> = []

    init() {}

    var task: FirstRunTask? { FirstRunScript.card(for: beat).task }

    /// The card is waiting on the user right now.
    var isWaiting: Bool { !isFinished && phase == .asking && task != nil }

    /// A satisfied task moves the card to its result note and stops there. It
    /// never advances on its own: the point of the note is that the user reads
    /// what just changed, and a card that vanished the instant they acted
    /// would take the explanation with it.
    mutating func observe(_ signals: FirstRunSignals) {
        guard !isFinished, phase == .asking,
              let task, signals.satisfies(task) else { return }
        performed.insert(task)
        phase = .done
    }

    /// The single forward control: "Next" once a task is done, "Not now" while
    /// it is still waiting. Both move on — nobody is held at a step they could
    /// not manage.
    mutating func advance() {
        guard !isFinished else { return }
        guard let next = beat.next else { isFinished = true; return }
        beat = next
        phase = .asking
    }

    /// Skip is an answer, not a postponement: it ends the welcome for good.
    mutating func skip() {
        isFinished = true
    }
}

/// The words.
///
/// Copy lives as data so the whole welcome can be read — and rewritten — in
/// one place, and so the machine above can be exercised without a view. It is
/// written for somebody who has never used a time tracker: no jargon, nothing
/// defined in terms of something else they have not met yet.
enum FirstRunScript {

    struct Card: Equatable {
        let beat: FirstRunBeat
        /// Nil on a card that waits, where the step count is the eyebrow.
        let eyebrow: String?
        let sentence: String
        let body: String
        /// A second paragraph, on the card that has two things to say.
        let note: String?
        /// What the card rings while it waits, or points at while it talks.
        let anchor: CoachAnchor?
        /// What the beat waits for, or nil when it is only read.
        let task: FirstRunTask?
        /// Said once the task is done, naming the thing that just changed.
        let result: String?
        /// The forward control once a task is done, or on a card with none.
        let forward: String
        /// The forward control while the card is still waiting. Visible from
        /// the first second, so a step nobody can manage is never a dead end.
        let waiting: String?
    }

    static let cards: [Card] = [
        Card(beat: .welcome,
             eyebrow: "Welcome",
             sentence: "FocusContinuity keeps two records of your day.",
             body: "One is what you decided to work on. The other is what your Mac "
                 + "actually did. Reading them side by side is the whole idea — and "
                 + "it takes about a minute to learn.",
             note: nil,
             anchor: nil,
             task: nil,
             result: nil,
             forward: "Show me",
             waiting: nil),

        Card(beat: .controls,
             eyebrow: nil,
             sentence: "Open your session controls.",
             body: "Press Start focus in the bar above. It does not begin anything "
                 + "yet — it opens the controls, so you can say what you are about "
                 + "to do first.",
             note: nil,
             anchor: .sessionControl,
             task: .openControls,
             result: "There they are. Everything that begins, pauses or ends a "
                 + "session lives in that strip.",
             forward: "Next",
             waiting: "Not now"),

        Card(beat: .start,
             eyebrow: nil,
             sentence: "Say what you are working on, then start.",
             body: "Type anything — emails, that report, admin. Then press Start "
                 + "focus in the strip. You can rename it later; nothing here is "
                 + "set in stone.",
             note: nil,
             anchor: .activityField,
             task: .startSession,
             result: "Look at the sentence at the top of the page. That is your "
                 + "day, and it just changed because you decided something.",
             forward: "Next",
             waiting: "Not now"),

        Card(beat: .apps,
             eyebrow: nil,
             sentence: "Now go and use another app.",
             body: "Your browser, your mail, anything at all. Come back whenever "
                 + "you like — the session keeps running while you are away from "
                 + "this window.",
             note: nil,
             anchor: .rail,
             task: .useAnotherApp,
             result: "Your apps appeared on the right, on their own. You never told "
                 + "FocusContinuity about them: that half is observed, not decided.",
             forward: "Next",
             waiting: "Not now"),

        Card(beat: .spans,
             eyebrow: "Looking back",
             sentence: "Day, Week, Month.",
             body: "The same story over a longer stretch. Day is where you work. "
                 + "The other two are where you find out what your weeks actually "
                 + "look like.",
             note: nil,
             anchor: .scopePills,
             task: nil,
             result: nil,
             forward: "Next",
             waiting: nil),

        Card(beat: .finish,
             eyebrow: "One last thing",
             sentence: "Step away and it will ask.",
             body: "Leave your Mac for a while and FocusContinuity will ask what "
                 + "that gap was — a break, or work somewhere else. Answer it "
                 + "honestly. You can always change your answer afterwards.",
             note: "It lives in your menu bar, so you can close this window and "
                 + "keep working. Settings are behind the gear, and you can open "
                 + "this welcome again from there.",
             anchor: .settings,
             task: nil,
             result: nil,
             forward: "Start my day",
             waiting: nil)
    ]

    static func card(for beat: FirstRunBeat) -> Card {
        // Every beat has a card; the lookup is total by construction and a
        // self-test holds it that way.
        cards.first { $0.beat == beat } ?? cards[0]
    }

    /// The beats that wait on the user, in order — what "step 2 of 3" counts.
    static var actionBeats: [FirstRunBeat] {
        cards.filter { $0.task != nil }.map(\.beat)
    }

    static func stepNumber(for beat: FirstRunBeat) -> Int? {
        actionBeats.firstIndex(of: beat).map { $0 + 1 }
    }

    /// Derived rather than written into each card, so adding or reordering a
    /// step cannot leave a card counting to the wrong total.
    static func eyebrow(for beat: FirstRunBeat) -> String {
        if let step = stepNumber(for: beat) {
            return "Step \(step) of \(actionBeats.count)"
        }
        return card(for: beat).eyebrow ?? ""
    }
}
