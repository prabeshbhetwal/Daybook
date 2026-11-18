import Foundation

/// Every number the activity-aware rules rest on, in one place. `Core` only.
///
/// Changing a rule or a constant here changes what a session's evidence is
/// read to mean, so `algorithmVersion` moves with it: stored evidence names
/// the version that read it, and a check pins `signature` to the version.
enum ActivityConstants {
    static let algorithmVersion = 1
    /// One beat: the span the sampler summarises into a single record.
    static let beatLength: TimeInterval = 30
    /// A stay in an app shorter than this folds into the stretch around it.
    static let flickFold: TimeInterval = 5
    /// Clicks and scrolls in one beat that make it engaged without a key.
    static let engagedClickScrollPerBeat = 3
    /// How long a watched window (its app, or a browser's helper, holds the screen awake) earns credit
    /// with no input.
    static let watchGrace: TimeInterval = 120
    /// A stretch credited for less than this is not worth naming.
    static let minCreditedSeconds: TimeInterval = 60
    static let minPhase: TimeInterval = 180
    /// How long away a return to the same work still continues it.
    static let returnWindow: TimeInterval = 900
    static let deepMinRun: TimeInterval = 1_500
    static let deepInsideShare = 0.70
    static let deepOutsideShare = 0.15
    /// How long beats are kept, in days. A setting, not a rule: it stays out of `signature`.
    static let defaultBeatRetentionDays = 90

    /// Every rule-bearing value above, joined with "|"; a check pins it to `algorithmVersion`.
    static var signature: String {
        [text(beatLength), text(flickFold), "\(engagedClickScrollPerBeat)", text(watchGrace),
         text(minCreditedSeconds), text(minPhase), text(returnWindow), text(deepMinRun),
         text(deepInsideShare), text(deepOutsideShare)].joined(separator: "|")
    }

    /// Shortest form that keeps a fraction ("%g"), so a changed 0.7 or 12.5 moves `signature`.
    private static func text(_ value: Double) -> String { String(format: "%g", value) }
}
