import Foundation

/// Where a rest on record came from. Breaks the person started are told apart
/// from rests the app wrote down about an absence, so a later view can say
/// which was a decision and which was an observation.
enum BreakOrigin: String, Codable, Equatable {
    /// Begun on purpose, from the menu bar or a break prompt's Take.
    case started
    /// Begun from a break prompt the app raised.
    case prompted
    /// An absence the person answered "It was a break".
    case answered
    /// A declared away that lasted past the break threshold.
    case away
    /// A stretch behind a film or video.
    case watching
}
