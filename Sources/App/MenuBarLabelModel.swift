import Combine
import Foundation

/// Everything the status item shows, reduced to what a person can see. The
/// store publishes every second while anything is in front; the menu bar only
/// changes when a minute ticks over or the ring moves by a visible amount.
struct MenuBarDisplay: Equatable {
    let isIdle: Bool
    let isPaused: Bool
    let needsAttention: Bool
    /// Goal share, rounded to steps far below a pixel of the 16pt ring.
    let progress: Double
    let isMet: Bool
    /// The elapsed minutes beside the ring, or nil when none are shown.
    let time: String?
    /// A break is under way, with a session or without one.
    let isOnBreak: Bool
    /// The break's time left beside the cup, or nil when the setting hides it
    /// (or no break is running). It changes once a minute until the last.
    let breakText: String?
    let accessibilityLabel: String

    static let progressSteps = 1_000.0

    /// `breakRemaining` is nil unless a break is under way. The break takes
    /// the place of the session's time: a paused session's frozen minutes
    /// beside a cup would read as the break's.
    init(state: SessionState, elapsed: TimeInterval, needsAttention: Bool,
         goal: GoalProgress, showsTime: Bool,
         breakRemaining: TimeInterval? = nil, showsBreakCountdown: Bool = true) {
        isIdle = state == .idle
        isPaused = state.isPaused
        self.needsAttention = needsAttention
        progress = (min(1, max(0, goal.share)) * Self.progressSteps).rounded() / Self.progressSteps
        isMet = goal.isMet
        isOnBreak = breakRemaining != nil
        time = !isIdle && showsTime && breakRemaining == nil ? Tokens.duration(elapsed) : nil
        breakText = breakRemaining.flatMap { showsBreakCountdown ? Self.breakText(remaining: $0) : nil }
        // Says what the glyph shows: the waiting dot, the pause mark and a
        // met goal were drawn but never spoken.
        var spoken = ["Daybook"]
        if needsAttention { spoken.append("Away question waiting") }
        if let breakRemaining {
            let left = BreakCountdown.spoken(remaining: breakRemaining)
            spoken.append(breakRemaining > 0 ? "On a break, \(left)" : left)
        } else if isIdle {
            spoken.append("\(DurationText.percent(goal.share, spoken: true)) "
                          + "of today's goal, no session running")
        } else {
            let elapsedText = Tokens.spokenElapsed(elapsed)
            switch state {
            case .running: spoken.append("Running, \(elapsedText)")
            case .paused: spoken.append("Paused, \(elapsedText)")
            default: spoken.append("\(elapsedText) so far")
            }
            if isMet { spoken.append("Daily goal met") }
        }
        accessibilityLabel = spoken.joined(separator: ". ")
    }

    init(_ store: SessionStore) {
        self.init(state: store.state,
                  elapsed: store.elapsed,
                  needsAttention: store.pendingAway != nil,
                  goal: store.goal,
                  showsTime: store.menuBarShowsTime,
                  breakRemaining: store.isOnBreak ? store.breakRemaining : nil,
                  showsBreakCountdown: store.menuBarShowsBreakCountdown)
    }

    /// "5m" while more than a minute is left, "45s" in the last, "Over", then
    /// "+3m". The rules are `BreakCountdown`'s, shared with the break card.
    static func breakText(remaining: TimeInterval) -> String {
        BreakCountdown.text(remaining: remaining)
    }
}

extension Tokens {
    /// Elapsed time as VoiceOver says it: whole minutes, and "under a
    /// minute" before the first. Read to the second, a live clock changes
    /// while it is being spoken, and in the first minute it changed every
    /// second.
    static func spokenElapsed(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "under a minute" : spent(seconds)
    }
}

/// The status item's own observable. It follows the store but republishes
/// only a changed `MenuBarDisplay`, so an unchanged second does not rebuild
/// the item's image and title on every menu bar replica.
final class MenuBarLabelModel: ObservableObject {
    @Published private(set) var display: MenuBarDisplay
    private var subscription: AnyCancellable?
    private var updateScheduled = false

    init(store: SessionStore) {
        display = MenuBarDisplay(store)
        // `objectWillChange` fires before the new value lands; one hop on the
        // main queue reads it after, and coalesces a burst of writes into one.
        subscription = store.objectWillChange.sink { [weak self, weak store] _ in
            guard let self, !self.updateScheduled else { return }
            self.updateScheduled = true
            DispatchQueue.main.async { [weak self, weak store] in
                guard let self else { return }
                self.updateScheduled = false
                guard let store else { return }
                let next = MenuBarDisplay(store)
                if next != self.display { self.display = next }
            }
        }
    }
}
