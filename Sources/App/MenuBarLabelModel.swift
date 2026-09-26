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
        accessibilityLabel = isIdle
            ? "FocusContinuity, \(Int((goal.share * 100).rounded())) "
              + "percent of today's goal, no session running"
            : "Current session \(Tokens.spent(elapsed))"
    }

    init(_ store: SessionStore) {
        self.init(state: store.state,
                  elapsed: store.elapsed,
                  needsAttention: store.pendingAway != nil,
                  goal: store.goal,
                  showsTime: store.menuBarShowsTime)
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
