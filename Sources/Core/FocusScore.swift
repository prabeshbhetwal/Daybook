import Foundation

/// The measured inputs behind one `FocusScore`. Kept separate from the score
/// itself so a caller — or a test — can inspect exactly what was observed
/// without re-deriving it from the raw segments.
struct FocusSignals: Equatable {
    let focusedShare: Double
    let mediaShare: Double
    let activity: InputActivity
    let switchesPerMinute: Double
    let attended: TimeInterval
    let dominantPurpose: AppPurpose
    let dominantApp: String?
    let dominantAppName: String
}

/// How focused a window of app usage was, on 0...1, with the numbers that
/// produced it. Every field here must trace back to a measurement — nothing
/// in `FocusScorer` is allowed to guess.
struct FocusScore: Equatable {
    let value: Double
    let signals: FocusSignals
    var explanation: String

    static let zero = FocusScore(
        value: 0,
        signals: FocusSignals(focusedShare: 0, mediaShare: 0, activity: .absent,
                              switchesPerMinute: 0, attended: 0,
                              dominantPurpose: .utility, dominantApp: nil,
                              dominantAppName: ""),
        explanation: "No activity")
}

/// Turns a window of `AppUsageSession`s into a `FocusScore`. Stateless per
/// call — the window and activity are supplied fresh each time, the same
/// shape as `PurposeMap.purpose(for:activity:overrides:)`.
struct FocusScorer {

    private let purposeOverrides: [String: String]

    init(purposeOverrides: [String: String] = [:]) {
        self.purposeOverrides = purposeOverrides
    }

    func score(segments: [AppUsageSession], activity: InputActivity,
               window: (start: Date, end: Date)) -> FocusScore {
        // Clip each segment to the window; a session that only partially
        // overlaps must not contribute time it did not spend inside it.
        struct Clipped {
            let bundleID: String
            let appName: String
            let seconds: TimeInterval
        }
        // Walked newest-first and stopped at the window's edge. The archive
        // holds weeks of history and this runs on every app switch; scanning
        // all of it to find the last fifteen minutes is work for nothing.
        var clipped: [Clipped] = []
        for segment in segments.reversed() {
            if segment.end < window.start { break }
            let start = max(segment.start, window.start)
            let end = min(segment.end, window.end)
            guard end > start else { continue }
            clipped.append(Clipped(bundleID: segment.bundleID, appName: segment.appName,
                                   seconds: end.timeIntervalSince(start)))
        }

        var secondsByApp: [String: TimeInterval] = [:]
        var nameByApp: [String: String] = [:]
        for entry in clipped {
            secondsByApp[entry.bundleID, default: 0] += entry.seconds
            nameByApp[entry.bundleID] = entry.appName
        }
        let attended = secondsByApp.values.reduce(0, +)
        guard attended > 0 else { return .zero }

        var focusedSeconds: TimeInterval = 0
        var mediaSeconds: TimeInterval = 0
        var purposeByApp: [String: AppPurpose] = [:]
        for (bundleID, seconds) in secondsByApp {
            let purpose = PurposeMap.purpose(for: bundleID, activity: activity,
                                             overrides: purposeOverrides)
            purposeByApp[bundleID] = purpose
            if purpose.isFocused { focusedSeconds += seconds }
            if purpose == .media { mediaSeconds += seconds }
        }
        let focusedShare = focusedSeconds / attended
        let mediaShare = mediaSeconds / attended

        // Dictionary order is unspecified, so a tie must break on something
        // stable: two apps with equal time would otherwise name a different
        // "dominant" app between runs, and that name reaches the user as the
        // reason a session started.
        let dominantID = secondsByApp
            .max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        let dominantApp = dominantID
        let dominantAppName = dominantID.flatMap { nameByApp[$0] } ?? ""
        let dominantPurpose = dominantID.flatMap { purposeByApp[$0] } ?? .utility
        let dominantMinutes = dominantID.flatMap { secondsByApp[$0] }.map { $0 / 60 } ?? 0

        // A switch is a change of app between neighbouring segments. Segments of
        // one app are checkpoint splits of a single stretch, not churn: thirty
        // Warp segments are zero switches.
        let switches = zip(clipped, clipped.dropFirst())
            .filter { $0.bundleID != $1.bundleID }
            .count
        let windowMinutes = window.end.timeIntervalSince(window.start) / 60
        let switchesPerMinute = windowMinutes > 0 ? Double(switches) / windowMinutes : 0

        let signals = FocusSignals(focusedShare: focusedShare, mediaShare: mediaShare,
                                   activity: activity, switchesPerMinute: switchesPerMinute,
                                   attended: attended, dominantPurpose: dominantPurpose,
                                   dominantApp: dominantApp, dominantAppName: dominantAppName)

        // A film playing is not deep work however much typing accompanies it.
        if mediaShare > FocusConstants.mediaVetoShare {
            let explanation = dominantAppName.isEmpty
                ? "Media \(Int(dominantMinutes))m"
                : "\(dominantAppName) \(Int(dominantMinutes))m · media"
            return FocusScore(value: 0, signals: signals, explanation: explanation)
        }

        let activityWeight: Double
        switch activity {
        case .active: activityWeight = 1.0
        case .passive: activityWeight = 0.4
        case .absent: activityWeight = 0.0
        }

        let churnPenalty = max(0, switchesPerMinute - FocusConstants.calmSwitchRate)
            * FocusConstants.switchPenaltyWeight
        let value = min(1, max(0, focusedShare * activityWeight - churnPenalty))

        let explanation = dominantAppName.isEmpty
            ? String(format: "%.1f switches/min", switchesPerMinute)
            : "\(dominantAppName) \(Int(dominantMinutes))m · " +
              String(format: "%.1f switches/min", switchesPerMinute)

        return FocusScore(value: value, signals: signals, explanation: explanation)
    }
}
