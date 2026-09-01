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

    init(id: UUID = UUID(), timestamp: Date, source: PowerSourceKind,
         percentage: Double?, charging: PowerChargingState,
         boundary: PowerCoverageBoundary? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.percentage = percentage
        self.charging = charging
        self.boundary = boundary
    }

    static func normalised(timestamp: Date, source: PowerSourceKind,
                           currentCapacity: Double?, maximumCapacity: Double?,
                           charging: PowerChargingState,
                           boundary: PowerCoverageBoundary? = nil) -> PowerObservation {
        let percentage: Double?
        if let currentCapacity, let maximumCapacity,
           currentCapacity.isFinite, maximumCapacity.isFinite,
           currentCapacity >= 0, maximumCapacity > 0 {
            percentage = min(100, max(0, currentCapacity / maximumCapacity * 100))
        } else {
            percentage = nil
        }
        return PowerObservation(timestamp: timestamp, source: source, percentage: percentage,
                         charging: charging, boundary: boundary)
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
            let label: String
            switch evidence[0].source {
            case .battery: label = "Battery"
            case .external:
                label = evidence[0].charging == .charging ? "Plugged in, charging" : "Plugged in"
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

        let needsDetail = sources.count > 1
            || chargingStates.count > 1
            || chargingStates.contains(.unknown)
            || evidence.contains { $0.boundary == .coverageResumed }
            || evidence.contains { $0.percentage == nil }
        let detail = needsDetail ? evidence.map {
            detailLine($0, relativeTo: interval.start)
        }.joined(separator: "\n") : nil
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
        "\(Int(percentage.rounded()))%"
    }

    private static func detailLine(_ observation: PowerObservation, relativeTo start: Date) -> String {
        let source: String
        switch observation.source {
        case .battery: source = "Battery"
        case .external: source = observation.charging == .charging ? "Plugged in, charging" : "Plugged in"
        case .ups: source = "UPS"
        case .unknown: source = "Power source unknown"
        }
        var parts = [source]
        if let percentage = observation.percentage { parts.append(formatted(percentage)) }
        if observation.charging == .unknown { parts.append("charging state unknown") }
        if observation.boundary == .coverageResumed { parts.append("coverage resumed") }
        if observation.boundary == .sourceChanged { parts.append("source changed") }
        let minutes = max(0, Int(observation.timestamp.timeIntervalSince(start) / 60))
        return "\(minutes)m — " + parts.joined(separator: " · ")
    }
}
