import Foundation

/// Where a rest on record came from. Breaks the person started are told apart
/// from rests the app wrote down about an absence, so a later view can say
/// which was a decision and which was an observation.
enum BreakOrigin: String, Codable, Equatable {
    /// A break begun with Start break or Take a break, including pressing
    /// Start on a break prompt.
    case started
    /// A rest taken by leaving after a break prompt, without pressing Start.
    case prompted
    /// An absence the person answered "It was a break".
    case answered
    /// A declared away that lasted past the break threshold.
    case away
    /// A stretch behind a film or video.
    case watching
}
