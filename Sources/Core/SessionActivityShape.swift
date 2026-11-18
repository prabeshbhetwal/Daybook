import Foundation

/// What a phase was: a purpose, an ambiguous app with no input to read (older
/// sessions, or credited to nothing), or time away.
enum PhaseActivity: Hashable, Codable { case purpose(AppPurpose), browsing, away }
enum SessionDepth: String, Codable { case deep, light, passive }
enum ActivityLabel: Hashable, Codable { case activity(AppPurpose), mixed, unsorted }
/// `.beats` when derived from beats; `.appsOnly` for sessions recorded before beats.
enum ShapeFidelity: String, Codable { case beats, appsOnly }

struct SessionPhase: Codable, Equatable {
    let start: Date
    let end: Date
    let activity: PhaseActivity
    let counted: Bool
    let credited: [String: TimeInterval]    // AppPurpose raw value to credited seconds in this phase
}

struct ActivityFingerprint: Codable, Hashable {
    let shares: [Int]        // per AppPurpose.allCases: share of credited seconds, rounded down to 20% steps, 0...5
    let topApps: [String]    // two apps with most credited seconds, ties by bundle id, padded with ""
    let siteKind: String     // "none" in this phase
}

/// One session's derived view: the snapshot stored at its end and the row's read model.
struct SessionActivityShape: Codable, Equatable {
    let algorithmVersion: Int
    let fidelity: ShapeFidelity
    let bounds: DateInterval                // the record's start to end when derived
    let countedSeconds: TimeInterval        // total of the counted spans it was derived from
    let signals: [SignalKind]               // on while its beats were recorded, sorted
    let phases: [SessionPhase]
    /// nil for .appsOnly and for .unsorted, for a shape with any split candidate (the session held more
    /// than one piece of work), and for a shape that is not one whole run of evidence: the join of
    /// several records' shapes, or one cut to a row (`joined`, `clipped`). A reader must not take nil
    /// to mean there was no input.
    let depth: SessionDepth?
    let label: ActivityLabel
    let credited: [String: TimeInterval]    // AppPurpose raw value to credited seconds
    let fingerprint: ActivityFingerprint?   // nil for .appsOnly
    /// Departures whose return window closed with no return. Phase B reads these; nothing acts on them here.
    let splitCandidates: [Date]
    /// The settings it was derived under, so a stored one is rewritten when they change. nil in a shape
    /// saved before they were kept, or not derived from beats; a stored nil reads as stale.
    var countsWhileWatching: Bool? = nil
    var overridesDigest: String? = nil

    /// A digest of the purpose overrides that holds across launches (FNV-1a over the sorted pairs):
    /// Swift's `Hasher` is seeded afresh each launch, so it cannot be stored.
    static func digest(_ overrides: [String: String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in overrides.sorted(by: { $0.key < $1.key }).map({ "\($0.key)=\($0.value)\n" }).joined().utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

struct DerivationInput {
    let credit: CreditInput
    let bounds: DateInterval
    let countsWhileWatching: Bool           // the session's WorkType.countsWhileWatching
    let isRunning: Bool
    let now: Date
}
