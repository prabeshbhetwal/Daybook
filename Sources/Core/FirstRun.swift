import Foundation

/// The welcome's chapters, in order. Each is a short run of cards; three of
/// the cards, early on, ask the reader to do something and wait. The rest
/// explain one part of the app each, pointing at it where it is on screen.
enum FirstRunChapter: String, CaseIterable, Identifiable {
    case welcome
    case firstSession
    case macSaw
    case readingDay
    case rail
    case steppingAway
    case automation
    case lookingBack
    case awards
    case menuBar
    case settings
    case finish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .firstSession: return "Your first session"
        case .macSaw: return "What your Mac saw"
        case .readingDay: return "Reading your day"
        case .rail: return "The rail"
        case .steppingAway: return "Stepping away"
        case .automation: return "Automatic sessions"
        case .lookingBack: return "Looking back"
        case .awards: return "Streaks and awards"
        case .menuBar: return "The menu bar"
        case .settings: return "Settings"
        case .finish: return "That's the app"
        }
    }

    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    var next: FirstRunChapter? {
        guard let index = Self.allCases.firstIndex(of: self),
              index + 1 < Self.allCases.count else { return nil }
        return Self.allCases[index + 1]
    }

    var previous: FirstRunChapter? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else { return nil }
        return Self.allCases[index - 1]
    }
}

/// What a card waits for. The welcome never simulates any of these: each is
/// satisfied by the same state the rest of the app reads, so what the reader
/// is shown afterwards is the real consequence of what they did.
enum FirstRunTask: String, CaseIterable {
    case openControls
    case startSession
    case useAnotherApp
}

/// Something the app does for a card while it is showing, and undoes when the
/// card goes. The coach reports the position; the application applies these.
enum FirstRunEffect: String, Equatable {
    /// Reveal the session strip, so the card can point into it.
    case openSessionControls
    /// Show the real away card with sample figures. Answers dismiss it and
    /// record nothing: there is no absence behind it.
    case previewAwayCard
    /// Show History, so its controls are there to be pointed at.
    case showHistory
}

/// The part of the window a card points at. A card whose anchor is not on
/// screen — a tile the day has nothing for yet — simply shows no ring; the
/// words are written to be true either way.
enum CoachAnchor: String, CaseIterable, Hashable {
    case sessionControl
    case activityField
    case storyColumn
    case measured
    case rail
    case focusTile
    case macTile
    case appsTile
    case rhythmTile
    case streakTile
    case awards
    case periodNav
    case search
    case journal
    case settings
}

/// The window state a card can be waiting on. Gathered by the view and handed
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
    /// Asking, and waiting for the reader to do it.
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
/// the whole tour can be driven and asserted without rendering anything.
struct FirstRunProgress: Equatable {
    private(set) var chapter: FirstRunChapter = .welcome
    private(set) var card = 0
    private(set) var phase: FirstRunPhase = .asking
    private(set) var isFinished = false
    /// Tasks the reader actually did, as against stepped past. The marks the
    /// card draws come from here, so a step they skipped is never ticked.
    private(set) var performed: Set<FirstRunTask> = []
    /// Chapters the reader has been in. The chapter list marks them.
    private(set) var visited: Set<FirstRunChapter> = [.welcome]

    init() {}

    var current: FirstRunScript.Card { FirstRunScript.card(chapter, card) }
    var task: FirstRunTask? { current.task }

    /// The card is waiting on the reader right now.
    var isWaiting: Bool { !isFinished && phase == .asking && task != nil }

    var isFirstCard: Bool { chapter == .welcome && card == 0 }

    /// A satisfied task moves the card to its result note and stops there. It
    /// never advances on its own: the point of the note is that the reader
    /// reads what just changed, and a card that vanished the instant they
    /// acted would take the explanation with it.
    mutating func observe(_ signals: FirstRunSignals) {
        guard !isFinished, phase == .asking,
              let task, signals.satisfies(task) else { return }
        performed.insert(task)
        phase = .done
    }

    /// The single forward control: "Next" once a task is done, "Not now" while
    /// it still waits. Both move on — nobody is held at a step they could not
    /// manage. The last card of the last chapter ends the welcome.
    mutating func advance() {
        guard !isFinished else { return }
        if card + 1 < FirstRunScript.chapter(chapter).cards.count {
            move(to: chapter, card: card + 1)
        } else if let next = chapter.next {
            move(to: next, card: 0)
        } else {
            isFinished = true
        }
    }

    /// The previous card, across a chapter boundary if need be. Reading back
    /// is part of reading; a tour this long cannot be one-way.
    mutating func back() {
        guard !isFinished else { return }
        if card > 0 {
            move(to: chapter, card: card - 1)
        } else if let previous = chapter.previous {
            move(to: previous, card: FirstRunScript.chapter(previous).cards.count - 1)
        }
    }

    /// The chapter list: straight to the start of any chapter.
    mutating func jump(to target: FirstRunChapter) {
        guard !isFinished else { return }
        move(to: target, card: 0)
    }

    /// Skip is an answer, not a postponement: it ends the welcome for good.
    mutating func skip() {
        isFinished = true
    }

    private mutating func move(to target: FirstRunChapter, card index: Int) {
        chapter = target
        card = index
        phase = .asking
        visited.insert(target)
    }
}

/// The words.
///
/// Copy lives as data so the whole welcome can be read — and rewritten — in
/// one place, and so the machine above can be exercised without a view. It is
/// written for somebody who has never used a time tracker: no jargon, nothing
/// defined in terms of something else they have not met yet, and nothing the
/// app cannot back.
enum FirstRunScript {

    struct Card: Equatable {
        let sentence: String
        let body: String
        /// A second paragraph, where one is needed.
        var note: String? = nil
        /// What the card rings while it shows.
        var anchor: CoachAnchor? = nil
        /// What the card waits for, or nil when it is only read.
        var task: FirstRunTask? = nil
        /// Said once the task is done, naming the thing that just changed.
        var result: String? = nil
        /// The forward control once a task is done, or on a card with none.
        var forward: String = "Next"
        /// The forward control while the card is still waiting. Visible from
        /// the first second, so a step nobody can manage is never a dead end.
        var waiting: String? = nil
        /// What the app does while this card shows.
        var effect: FirstRunEffect? = nil
    }

    struct Chapter: Equatable {
        let id: FirstRunChapter
        let cards: [Card]
    }

    static let chapters: [Chapter] = [
        Chapter(id: .welcome, cards: [
            Card(sentence: "FocusContinuity keeps two records of your day.",
                 body: "One is what you decided to work on. The other is what your Mac "
                     + "actually did. Reading them side by side is the whole idea.",
                 note: "This tour walks through every part of the app, about seven minutes "
                     + "if you do all of it. Chapters, in the corner of this card, lets you "
                     + "skip any of it or come back to any of it. Skip tour ends it for good; "
                     + "Settings can start it again.",
                 forward: "Show me")
        ]),

        Chapter(id: .firstSession, cards: [
            Card(sentence: "Open your session controls.",
                 body: "Press Start focus in the bar above. It does not begin anything "
                     + "yet — it opens the controls, so you can say what you are about "
                     + "to do first.",
                 anchor: .sessionControl,
                 task: .openControls,
                 result: "There they are. Everything that begins, pauses or ends a "
                     + "session lives in that strip.",
                 waiting: "Not now"),
            Card(sentence: "Say what you are working on, then start.",
                 body: "Type anything — emails, that report, admin. Then press Start "
                     + "focus in the strip. You can rename it later; nothing here is "
                     + "set in stone.",
                 anchor: .activityField,
                 task: .startSession,
                 result: "Look at the sentence at the top of the page. That is your "
                     + "day, and it just changed because you decided something.",
                 waiting: "Not now",
                 effect: .openSessionControls),
            Card(sentence: "That is a session.",
                 body: "A session is you saying: I am working now, on this. It runs "
                     + "until you stop it, and the clock in the bar is its time so far. "
                     + "Nothing counts as work until you say so.",
                 anchor: .sessionControl)
        ]),

        Chapter(id: .macSaw, cards: [
            Card(sentence: "Now go and use another app.",
                 body: "Your browser, your mail, anything at all. Come back whenever "
                     + "you like — the session keeps running while you are away from "
                     + "this window.",
                 anchor: .rail,
                 task: .useAnotherApp,
                 result: "Your apps appeared on the right, on their own. You never told "
                     + "FocusContinuity about them: that half is observed, not decided.",
                 waiting: "Not now"),
            Card(sentence: "Observed is not the same as decided.",
                 body: "The Apps tile is what your Mac saw: which app was in front, and "
                     + "for how long. Only apps you are actually using count — after "
                     + "three minutes with no keyboard or mouse, the clock on that app "
                     + "stops.",
                 note: "On this Mac adds it up: time inside a session, time outside "
                     + "one, and time nothing recorded. The three always sum to the "
                     + "whole, so you can see exactly where an afternoon went.",
                 anchor: .appsTile)
        ]),

        Chapter(id: .readingDay, cards: [
            Card(sentence: "This column is your day, told in order.",
                 body: "One sentence at the top says what the day amounts to. Below it, "
                     + "every session and every stretch of app use, in the order they "
                     + "happened. Click an entry to open it; there is an Expand all at "
                     + "the top when you want the lot.",
                 anchor: .storyColumn),
            Card(sentence: "The evidence sits beside the figures.",
                 body: "How this day was measured opens to say how each measure is "
                     + "counted: logged focus, recorded app use and breaks, and how many "
                     + "separate stretches the sessions ran as. What was not recorded "
                     + "shows in the day itself. Nothing here is presented as more "
                     + "certain than it is.",
                 anchor: .measured),
            Card(sentence: "You can correct anything, and undo any correction.",
                 body: "Open an entry and you can rename it, change its category, or "
                     + "continue it as the same piece of work. A correction changes the "
                     + "whole thread, not one stretch of it, and the original app "
                     + "record underneath is never touched.",
                 anchor: .storyColumn)
        ]),

        Chapter(id: .rail, cards: [
            Card(sentence: "Daily goal: how far today has come.",
                 body: "The figure is the focus that counts towards today's goal, and the "
                     + "ring its share of it. Only declared focus counts — sessions, not app use — "
                     + "and only while you were actually at the keyboard. The day's total "
                     + "focus is the column's headline. The goal is yours to set, in "
                     + "Settings under Sessions.",
                 anchor: .focusTile),
            Card(sentence: "On this Mac: the whole day, in three parts.",
                 body: "Time in a session, time at the Mac outside one, and time "
                     + "nothing recorded. They always add up to the whole, which is what "
                     + "lets you trust any one of them.",
                 anchor: .macTile),
            Card(sentence: "Apps: what was in front.",
                 body: "Your most-used apps, by time. Click one for its stretches "
                     + "through the day. How many are listed is a setting.",
                 anchor: .appsTile),
            Card(sentence: "Rhythm: the hours you actually work.",
                 body: "Where in the day your focus lands. It appears once there is a "
                     + "day's worth to draw, and it is the thing to look at when you "
                     + "wonder whether mornings or afternoons are your time.",
                 anchor: .rhythmTile),
            Card(sentence: "Streak: days that counted.",
                 body: "A day joins the streak once its focus reaches a threshold you "
                     + "choose. This tile appears after your first counted day. The "
                     + "tiles can be dragged into any order you like.",
                 anchor: .streakTile)
        ]),

        Chapter(id: .steppingAway, cards: [
            Card(sentence: "Step away, and it will ask.",
                 body: "Leave your Mac during a session and, when you come back, this "
                     + "card asks what that gap was. The one on screen now is a "
                     + "rehearsal with made-up figures — press any answer and nothing "
                     + "is recorded.",
                 note: "It was a break is written down as rest. I was working adds the "
                     + "gap to the session. I was away leaves it out, silently. Start "
                     + "fresh ends the session where you left and begins a new one.",
                 effect: .previewAwayCard),
            Card(sentence: "Answer it honestly. You can change it later.",
                 body: "The card takes one press and then gets out of the way. Every "
                     + "answer can be revised from the day's story afterwards, so there "
                     + "is nothing to get wrong. Short gaps of a few minutes are folded "
                     + "in without asking.",
                 note: "How long an absence has to be before it asks, and when it "
                     + "gives you the full card rather than the quick one, are both in "
                     + "Settings under Away & Breaks.")
        ]),

        Chapter(id: .automation, cards: [
            Card(sentence: "It can start sessions for you.",
                 body: "An activity rule says: when this app has been in front for a "
                     + "few minutes, start a session under this category. Coding when "
                     + "your editor comes up; Browsing for your browser. You are told "
                     + "when it happens, and the notice carries an Undo.",
                 anchor: .settings),
            Card(sentence: "Rules never touch a session you started yourself.",
                 body: "If a different rule's app takes over, the automatic session "
                     + "closes at that moment and the next one begins there — one at "
                     + "a time, no overlap, no gap. Quick switches between apps do "
                     + "nothing; a rule waits for a few settled minutes.",
                 note: "Rules live in Settings under Activities. Turn them off there "
                     + "and the app records app use only, and starts nothing.")
        ]),

        Chapter(id: .lookingBack, cards: [
            Card(sentence: "The story is today. History is one timeline that unfolds.",
                 body: "Years open into months, months into weeks, weeks into days, and a "
                     + "day into its sessions, each one step in from its parent. Click a "
                     + "row to open it, or press Return; Escape folds the deepest open row.",
                 anchor: .journal,
                 effect: .showHistory),
            Card(sentence: "History goes back to the day you installed the app.",
                 body: "Nothing is drawn from before the app was here, because nothing "
                     + "was recorded. Jump to date opens any recorded day straight away.",
                 anchor: .periodNav,
                 effect: .showHistory),
            Card(sentence: "Find any session by name.",
                 body: "The search at the top of History finds sessions by what you "
                     + "called them, what you noted, the app, the category or the date. "
                     + "⌘F takes you there from anywhere in the window.",
                 anchor: .search,
                 effect: .showHistory)
        ]),

        Chapter(id: .awards, cards: [
            Card(sentence: "Streaks and awards.",
                 body: "Awards mark milestones — a first counted week, a long streak, "
                     + "a strong month. They are earned from the record, never given "
                     + "for opening the app. The Awards link on the Streak tile opens "
                     + "them once you have a streak; ⌘6 opens them any time.",
                 anchor: .awards)
        ]),

        Chapter(id: .menuBar, cards: [
            Card(sentence: "The app lives in your menu bar.",
                 body: "You can close this window and keep working. The ring in the "
                     + "menu bar is today's goal, filling as you go, and clicking it "
                     + "gives you Start, Pause and Stop, your recent activities, and "
                     + "the way back to this window.",
                 note: "Look for the ring beside the clock. It shows the session time "
                     + "next to it while one runs; that is a setting."),
            Card(sentence: "A few keys.",
                 body: "Control-Option-Space, from inside any app, starts a session, "
                     + "ends the running one, or brings up an away card "
                     + "that is waiting for you. In this window: ⌘1 for the day's story, "
                     + "⌘2 for History, ⌘6 for Awards, ⌘7 for the session controls and "
                     + "⌘, for Settings.",
                 note: "⌥⌘N starts a session, ⌥⌘P pauses or resumes it, ⌥⌘A steps away "
                     + "and ⌥⌘S stops it. While VoiceOver is on, Control-Option-Space "
                     + "stays VoiceOver's own.",
                 anchor: .sessionControl)
        ]),

        Chapter(id: .settings, cards: [
            Card(sentence: "Everything adjustable is behind the gear.",
                 body: "General for login and the menu bar. Sessions for your "
                     + "daily goal, categories and thresholds. Activities for the rules. "
                     + "Away & Breaks for when it asks. Recording for what is watched "
                     + "and which apps count as work.",
                 anchor: .settings),
            Card(sentence: "Everything stays on this Mac.",
                 body: "Your record is a handful of files in your own Library folder. "
                     + "Nothing is sent anywhere, there is no account, and Privacy in "
                     + "Settings shows you the folder and lets you turn recording off "
                     + "entirely.",
                 anchor: .settings)
        ]),

        Chapter(id: .finish, cards: [
            Card(sentence: "That's the whole app.",
                 body: "Two records, read side by side: what you decided, and what "
                     + "your Mac saw. Everything else is just that, over more days. "
                     + "Your session is still running.",
                 note: "This tour is in Settings under General whenever you want it "
                     + "again.",
                 forward: "Start my day")
        ])
    ]

    static func chapter(_ id: FirstRunChapter) -> Chapter {
        // Every chapter has an entry; the lookup is total by construction and
        // a self-test holds it that way.
        chapters.first { $0.id == id } ?? chapters[0]
    }

    static func card(_ chapterID: FirstRunChapter, _ index: Int) -> Card {
        let cards = chapter(chapterID).cards
        return cards[min(max(0, index), cards.count - 1)]
    }

    /// The cards that wait on the reader, in order — what "step 2 of 3" counts.
    static var taskCards: [(chapter: FirstRunChapter, card: Int, task: FirstRunTask)] {
        chapters.flatMap { chapter in
            chapter.cards.enumerated().compactMap { index, card in
                card.task.map { (chapter.id, index, $0) }
            }
        }
    }

    static func stepNumber(chapter: FirstRunChapter, card: Int) -> Int? {
        taskCards.firstIndex { $0.chapter == chapter && $0.card == card }.map { $0 + 1 }
    }

    /// Derived, never written into a card, so adding or reordering anything
    /// cannot leave a card counting to the wrong total.
    static func eyebrow(chapter: FirstRunChapter, card: Int) -> String {
        if let step = stepNumber(chapter: chapter, card: card) {
            return "Step \(step) of \(taskCards.count) · \(chapter.title)"
        }
        return "Chapter \(chapter.number) of \(FirstRunChapter.allCases.count) · \(chapter.title)"
    }

    static var cardCount: Int { chapters.reduce(0) { $0 + $1.cards.count } }
}
