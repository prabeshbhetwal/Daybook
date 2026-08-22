import Foundation

/// One app's record of how the user answered the app's guesses about it.
struct LearnedSignal: Codable, Equatable {
    var kept = 0
    var undone = 0

    var observations: Int { kept + undone }
}

/// Learns how eagerly to start a session for a given app, from whether the user
/// keeps or undoes the sessions it starts.
///
/// This is the idea worth taking from the AgentDB plugins — store observations,
/// score them, let corrections move the answer — implemented natively. It is
/// counter arithmetic, not machine learning, and is not described as such. A
/// model would be 1–3 GB resident against an app that idles at 17 MB, to answer
/// a question that is one ratio.
///
/// It moves only the *threshold*, never the recorded facts. No amount of
/// learning can change what the archive says happened.
struct PurposeLearner {

    /// Below this many answers about an app there is nothing to learn from, and
    /// the shared default stands. Adapting to a single undo would make the app
    /// erratic in exactly the way an automatic mode must not be.
    static let minimumObservations = 3

    /// How far a unanimous history may move the threshold. Bounded so a run of
    /// undos can make the app cautious but never mute — and so a run of keeps
    /// can make it eager without letting it start on noise.
    static let maximumShift = 0.15

    private let signals: [String: LearnedSignal]

    init(signals: [String: LearnedSignal]) {
        self.signals = signals
    }

    /// The score this app must reach before a session starts automatically.
    /// Higher means more evidence demanded.
    func startThreshold(for bundleID: String?) -> Double {
        let base = FocusConstants.autoStartThreshold
        guard let bundleID, let signal = signals[bundleID],
              signal.observations >= PurposeLearner.minimumObservations else {
            return base
        }
        // -1 when every session was kept, +1 when every one was undone.
        let leaning = (Double(signal.undone) - Double(signal.kept))
            / Double(signal.observations)
        let shifted = base + leaning * PurposeLearner.maximumShift
        // Never past the stop threshold, or starting and stopping would fight.
        return min(0.9, max(FocusConstants.autoStopThreshold + 0.1, shifted))
    }

    /// The user let an automatic session stand.
    func recordingKept(_ bundleID: String?) -> [String: LearnedSignal] {
        recording(bundleID) { $0.kept += 1 }
    }

    /// The user rejected one.
    func recordingUndone(_ bundleID: String?) -> [String: LearnedSignal] {
        recording(bundleID) { $0.undone += 1 }
    }

    /// What the app has actually learned about this bundle, for the settings
    /// screen. Nil when it has not earned an opinion yet — the same rule the
    /// rewards and insights follow: no data, no claim.
    func summary(for bundleID: String?) -> String? {
        guard let bundleID, let signal = signals[bundleID],
              signal.observations >= PurposeLearner.minimumObservations else { return nil }
        let threshold = startThreshold(for: bundleID)
        if threshold > FocusConstants.autoStartThreshold {
            return "Slower to start — you undid \(signal.undone) of \(signal.observations)"
        }
        if threshold < FocusConstants.autoStartThreshold {
            return "Quicker to start — you kept \(signal.kept) of \(signal.observations)"
        }
        return nil
    }

    private func recording(_ bundleID: String?,
                           _ change: (inout LearnedSignal) -> Void) -> [String: LearnedSignal] {
        guard let bundleID, !bundleID.isEmpty else { return signals }
        var updated = signals
        var signal = updated[bundleID] ?? LearnedSignal()
        change(&signal)
        updated[bundleID] = signal
        return updated
    }
}
