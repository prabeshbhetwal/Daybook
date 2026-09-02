import Foundation

struct ActivityRule: Codable, Equatable, Identifiable {
    static let defaultStartAfter: TimeInterval = 180
    static let startAfterPresets: [TimeInterval] = [30, 60, 180, 300]

    let id: UUID
    var name: String
    var workType: WorkType
    var bundleIDs: Set<String>
    var isEnabled: Bool
    var startAfter: TimeInterval

    init(id: UUID = UUID(), name: String, workType: WorkType,
         bundleIDs: Set<String>, isEnabled: Bool = true,
         startAfter: TimeInterval = ActivityRule.defaultStartAfter) {
        self.id = id
        self.name = Self.normalisedName(name)
        self.workType = workType
        self.bundleIDs = Set(bundleIDs.compactMap(Self.normalisedBundleID))
        self.isEnabled = isEnabled
        self.startAfter = Self.isValidStartAfter(startAfter) ? startAfter : Self.defaultStartAfter
    }

    static func validateCustomStartAfter(_ text: String) -> Result<TimeInterval, ActivityRuleValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber), let value = Int(trimmed) else {
            return .failure(.notWholeSeconds)
        }
        guard (30...1_800).contains(value) else { return .failure(.outsideAllowedRange) }
        return .success(TimeInterval(value))
    }

    static func normalisedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalisedBundleID(_ value: String) -> String? {
        let normal = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normal.isEmpty ? nil : normal
    }

    static func isValidStartAfter(_ value: TimeInterval) -> Bool {
        value.isFinite && value.rounded(.towardZero) == value && value >= 30 && value <= 1_800
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, workType, bundleIDs, isEnabled, startAfter
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id),
                  name: try values.decode(String.self, forKey: .name),
                  workType: try values.decode(WorkType.self, forKey: .workType),
                  bundleIDs: try values.decode(Set<String>.self, forKey: .bundleIDs),
                  isEnabled: try values.decode(Bool.self, forKey: .isEnabled),
                  startAfter: try values.decode(TimeInterval.self, forKey: .startAfter))
    }
}

enum ActivityRuleValidationError: Error, Equatable {
    case notWholeSeconds
    case outsideAllowedRange
}

extension ActivityRuleValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notWholeSeconds: return "Enter a whole number of seconds."
        case .outsideAllowedRange: return "Choose between 30 and 1,800 seconds."
        }
    }
}

enum AutomationMode: Equatable {
    case off
    case legacyHeuristic
    case activityRules
}

struct ActivityAutomaticAction: Codable, Equatable {
    let ruleID: UUID
    let ruleName: String
    let workType: WorkType
    let evidence: DateInterval
    let reason: String
    let ruleVersion: UInt64
    let generation: UInt64
    let expectedRecordID: UUID?
}

struct AutomaticActivityRecord: Codable, Equatable {
    let action: ActivityAutomaticAction
    let resultingRecordID: UUID
    var reason: String { action.reason }
    var expectedPreviousRecordID: UUID? { action.expectedRecordID }
    func acceptsUndo(for recordID: UUID) -> Bool { resultingRecordID == recordID }
}

enum ActivityAccounting {

    static func contiguousCoverage(_ intervals: [DateInterval], endingAt end: Date,
                                   tolerance: TimeInterval = 1) -> DateInterval? {
        let merged = intervals.filter { $0.duration.isFinite && $0.duration >= 0 }
            .sorted { $0.start < $1.start }
            .reduce(into: [DateInterval]()) { result, interval in
                guard let last = result.last else { result.append(interval); return }
                if interval.start.timeIntervalSince(last.end) <= tolerance {
                    result[result.count - 1] = DateInterval(start: last.start,
                        end: max(last.end, interval.end))
                } else { result.append(interval) }
            }
        return merged.last(where: { $0.start <= end && $0.end >= end.addingTimeInterval(-tolerance) })
            .map { DateInterval(start: $0.start, end: min(end, max(end, $0.end))) }
    }
}
