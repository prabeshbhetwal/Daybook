import Foundation

/// Every number the activity-aware rules rest on, in one place. `Core` only.
///
/// Changing a rule or a constant here changes what a session's evidence is
/// read to mean, so `algorithmVersion` moves with it: stored evidence names
/// the version that read it, and a check pins `signature` to the version.
enum ActivityConstants {
    static let algorithmVersion = 2
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
    /// How long a remembered category choice steers suggestions after it was last made, in days. Like the
    /// retention above it is no rule, so it stays out of `signature`.
    static let correctionExpiryDays = 90
    /// A label the person or a rule chose is held against the evidence (the report's contradiction line)
    /// when what it stands for holds strictly under the low share of the credited time and one other purpose
    /// strictly over the high one. They change what is said about a session, not how it is read, so they
    /// stay out of `signature` too.
    static let contradictionLow = 0.30
    static let contradictionHigh = 0.60

    /// Every rule-bearing value above, joined with "|"; a check pins it to `algorithmVersion`.
    static var signature: String {
        [text(beatLength), text(flickFold), "\(engagedClickScrollPerBeat)", text(watchGrace),
         text(minCreditedSeconds), text(minPhase), text(returnWindow), text(deepMinRun),
         text(deepInsideShare), text(deepOutsideShare)].joined(separator: "|")
    }

    /// Shortest form that keeps a fraction ("%g"), so a changed 0.7 or 12.5 moves `signature`.
    private static func text(_ value: Double) -> String { String(format: "%g", value) }
}
