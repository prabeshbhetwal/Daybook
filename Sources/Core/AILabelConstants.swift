import Foundation

/// The numbers the model's category pick and AI-made labels rest on (Phase C, ruling C28). Apart from
/// `ActivityConstants` on purpose: none of these changes how a session's evidence is read, so none may
/// move `algorithmVersion` or `ActivityConstants.signature`. `Core` only.
enum AILabelConstants {
    /// The top activity's share of credited seconds below which the model is asked, and the lead of the top
    /// over the next below which it is asked. Shares, 0 to 1.
    static let modelShare = 0.60
    static let modelMargin = 0.15
    /// Counted seconds under which an ended session is not asked about (spec: under 10 minutes).
    static let modelMinCounted: TimeInterval = 600
    /// New unkept labels allowed in any rolling `labelWindow`, and unkept labels alive at once.
    static let newLabelsPerDay = 1
    static let labelWindow: TimeInterval = 86_400
    static let maxUnkeptLabels = 3
    /// The most kinds of session one label is kept for; the oldest go first.
    static let maxLabelFingerprints = 50
    /// Whole seconds, so no time zone or clock change moves an edge. An unkept label unused this long is
    /// archived; a cached answer unused this long is dropped.
    static let labelArchiveAfter: TimeInterval = 30 * 86_400
    static let answerExpiry: TimeInterval = 90 * 86_400
    /// The most categories offered to the model, which bounds the answer it may give.
    static let maxOffered = 20
    /// Comparisons kept, and how many of the newest that hold a choice the tally reads.
    static let tallyKeep = 50
    static let tallyWindow = 20
}
