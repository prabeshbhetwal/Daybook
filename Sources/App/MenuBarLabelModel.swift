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
    let accessibilityLabel: String

    static let progressSteps = 1_000.0

    init(state: SessionState, elapsed: TimeInterval, needsAttention: Bool,
         goal: GoalProgress, showsTime: Bool) {
        isIdle = state == .idle
        isPaused = state.isPaused
        self.needsAttention = needsAttention
        progress = (min(1, max(0, goal.share)) * Self.progressSteps).rounded() / Self.progressSteps
        isMet = goal.isMet
        time = !isIdle && showsTime ? Tokens.duration(elapsed) : nil
        // Says what the glyph shows: the waiting dot, the pause mark and a
        // met goal were drawn but never spoken.
        var spoken = ["FocusContinuity"]
        if needsAttention { spoken.append("Away question waiting") }
        if isIdle {
            spoken.append("\(Int((goal.share * 100).rounded())) "
                          + "per cent of today's goal, no session running")
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
                  showsTime: store.menuBarShowsTime)
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
