import Foundation

enum PowerSourceKind: String, Codable, Equatable {
    case battery
    case external
    case ups
    case unknown
}

enum PowerChargingState: String, Codable, Equatable {
    case charging
    case notCharging
    case unknown
}

enum PowerCoverageBoundary: String, Codable, Equatable {
    case stretchStarted
    case sourceChanged
    case coverageResumed
    case stretchEnded
}

struct PowerObservation: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let source: PowerSourceKind
    let percentage: Double?
    let charging: PowerChargingState
    let boundary: PowerCoverageBoundary?
    /// The attached adapter's rating, as macOS reports it — 96 for a 96 W
    /// charger. Present only on external power; a sidecar written before this
    /// field existed decodes it as nil.
    let adapterWatts: Int?

    init(id: UUID = UUID(), timestamp: Date, source: PowerSourceKind,
         percentage: Double?, charging: PowerChargingState,
         boundary: PowerCoverageBoundary? = nil, adapterWatts: Int? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.percentage = percentage
        self.charging = charging
        self.boundary = boundary
        self.adapterWatts = adapterWatts
    }

    static func normalised(timestamp: Date, source: PowerSourceKind,
                           currentCapacity: Double?, maximumCapacity: Double?,
                           charging: PowerChargingState,
                           boundary: PowerCoverageBoundary? = nil,
                           adapterWatts: Int? = nil) -> PowerObservation {
        let percentage: Double?
        if let currentCapacity, let maximumCapacity,
           currentCapacity.isFinite, maximumCapacity.isFinite,
           currentCapacity >= 0, maximumCapacity > 0 {
            percentage = min(100, max(0, currentCapacity / maximumCapacity * 100))
        } else {
            percentage = nil
        }
        return PowerObservation(timestamp: timestamp, source: source, percentage: percentage,
                                charging: charging, boundary: boundary, adapterWatts: adapterWatts)
    }
}

struct SessionMetadata: Codable, Equatable, Identifiable {
    let recordID: UUID
    var note: String?
    var power: [PowerObservation]
    var id: UUID { recordID }

    init(recordID: UUID, note: String? = nil, power: [PowerObservation] = []) {
        self.recordID = recordID
        self.note = note
        self.power = power
    }
}

/// Durable ownership transfer after an Away answer. Persistence makes a failed
/// sidecar write replayable even if the process exits before the next refresh.
struct PendingPowerTransfer: Codable, Equatable {
    let sourceID: UUID
    let destinationID: UUID
    let factualBoundary: Date
}

/// One exact sidecar append retained outside that sidecar until its observation
/// UUID is durably present. Queue order prevents a later sample from hiding or
/// overtaking an earlier failed write.
struct PendingPowerObservation: Codable, Equatable {
    let recordID: UUID
    let observation: PowerObservation
    let lastError: String?
}

enum SessionMetadataWriteResult: Equatable {
    case saved
    case failed(String)
}

struct PowerContextSummary: Equatable {
    let headline: String
    let detail: String?
    let symbolName: String
    /// Includes a boundary sample taken immediately after a durable commit
    /// without changing that sample's factual timestamp.
    private static let boundaryTolerance: TimeInterval = 2

    static func make(observations: [PowerObservation], interval: DateInterval) -> PowerContextSummary? {
        let evidence = observations.filter {
            if $0.timestamp >= interval.start && $0.timestamp <= interval.end { return true }
            switch $0.boundary {
            case .stretchStarted:
                return abs($0.timestamp.timeIntervalSince(interval.start)) <= boundaryTolerance
            case .stretchEnded:
                return abs($0.timestamp.timeIntervalSince(interval.end)) <= boundaryTolerance
            case .sourceChanged, .coverageResumed, nil:
                return false
            }
        }.sorted {
            $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString
                : $0.timestamp < $1.timestamp
        }
        guard !evidence.isEmpty else { return nil }

        let sources = Set(evidence.map(\.source))
        let chargingStates = Set(evidence.map(\.charging))
        let headline: String
        if sources.count > 1 || chargingStates.count > 1 {
            headline = "Power changed"
        } else {
            var label: String
            switch evidence[0].source {
            case .battery: label = "Using battery"
            case .external:
                label = evidence[0].charging == .charging ? "Plugged in, charging" : "Plugged in"
                // The charger in use, if macOS named one. The latest reading
                // is the one plugged in now; a change is qualified below.
                if let watts = evidence.compactMap(\.adapterWatts).last {
                    label += " · \(watts) W"
                }
            case .ups: label = "UPS"
            case .unknown: label = "Power recorded"
            }
            let percentages = evidence.compactMap(\.percentage)
            if let first = percentages.first, let last = percentages.last,
               percentages.count > 1 {
                headline = "\(label) · \(formatted(first)) → \(formatted(last))"
            } else if let percentage = percentages.first {
                headline = "\(label) · \(formatted(percentage))"
            } else {
                headline = label
            }
        }

        let lines = qualifications(evidence, sources: sources, chargingStates: chargingStates)
        let detail = lines.isEmpty ? nil : lines.joined(separator: " ")
        let symbolName: String
        if sources.count > 1 { symbolName = "arrow.triangle.2.circlepath" }
        else {
            switch evidence[0].source {
            case .battery: symbolName = "battery.75percent"
            case .external: symbolName = "powerplug"
            case .ups: symbolName = "bolt.horizontal.circle"
            case .unknown: symbolName = "questionmark.circle"
            }
        }
        return PowerContextSummary(headline: headline, detail: detail, symbolName: symbolName)
    }

    private static func formatted(_ percentage: Double) -> String {
        DurationText.wholeSeconds(percentage.rounded()).map { "\($0)%" } ?? "—"
    }

    /// What the headline cannot say on its own: why it reads "Power changed".
    ///
    /// This was one line per observation, which is not a summary — it is the
    /// sampler's log. macOS posts its power notification on every level tick,
    /// roughly once a minute, and each one was tagged `.sourceChanged`, so an
    /// hour on battery rendered as forty-odd rows reading "Battery · 100% ·
    /// source changed" when the source had not changed once.
    ///
    /// Sampling gaps are not qualified here. The headline is first and last
    /// level within the interval and claims nothing about continuity, and the
    /// first attempt at a gap sentence was false in its first real case: a
    /// stretch begun after an Away answer is tagged "coverage resumed" at 0m.
    private static func qualifications(_ evidence: [PowerObservation],
                                       sources: Set<PowerSourceKind>,
                                       chargingStates: Set<PowerChargingState>) -> [String] {
        var lines: [String] = []
        if sources.count > 1 {
            var ordered: [PowerSourceKind] = []
            for observation in evidence where !ordered.contains(observation.source) {
                ordered.append(observation.source)
            }
            lines.append("Power source changed during this session: "
                         + ordered.map(name).joined(separator: ", ") + ".")
        }
        if sources.count == 1, chargingStates.subtracting([.unknown]).count > 1 {
            lines.append("Charging started or stopped during this session.")
        }
        var chargers: [Int] = []
        for watts in evidence.compactMap(\.adapterWatts) where !chargers.contains(watts) {
            chargers.append(watts)
        }
        if chargers.count > 1 {
            lines.append("Charger changed during this session: "
                         + chargers.map { "\($0) W" }.joined(separator: ", then ") + ".")
        } else if let watts = chargers.first, sources.count > 1 {
            // The headline says "Power changed"; the charger is not in it.
            lines.append("Plugged into a \(watts) W charger for part of this session.")
        }
        return lines
    }

    private static func name(_ source: PowerSourceKind) -> String {
        switch source {
        case .battery: return "battery"
        case .external: return "mains power"
        case .ups: return "UPS"
        case .unknown: return "an unrecorded source"
        }
    }
}
