import Foundation

/// The power state in effect for one stretch of time, as one small mark: a
/// symbol and a level. Read from the latest recorded observation at or before
/// the end of that time, so a change part-way through shows its outcome.
///
/// Takes no `Design` dependency: it hands back a symbol name and text.
struct PowerReading: Equatable {
    let symbolName: String
    /// "84%", or empty when macOS gave no level.
    let level: String
    /// Said in place of the symbol, which VoiceOver cannot read.
    let spoken: String

    /// Nil when nothing was recorded by `date`: a reading from after the
    /// moment would claim a state nobody saw then.
    static func at(_ date: Date, in observations: [PowerObservation]) -> PowerReading? {
        guard let observation = observations
            .filter({ $0.timestamp <= date })
            .max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        return PowerReading(observation)
    }

    /// The reading each visit ended on, kept only where it differs from the
    /// visit before it in time: a run of visits at 91% says 91% once. Gaps
    /// neither show a reading nor break the run.
    static func changes(across intervals: [RecordedActivity.Interval],
                        in observations: [PowerObservation]) -> [String: PowerReading] {
        var marks: [String: PowerReading] = [:]
        var last: PowerReading?
        for interval in intervals.sorted(by: { $0.start < $1.start }) where !interval.isGap {
            guard let reading = at(interval.end, in: observations), reading != last else { continue }
            marks[interval.id] = reading
            last = reading
        }
        return marks
    }

    init(_ observation: PowerObservation) {
        // A stored level is decoded verbatim; one past `Int` reads as unknown.
        let percent = observation.percentage.flatMap { DurationText.wholeSeconds($0.rounded()) }
        level = percent.map { "\($0)%" } ?? ""
        let state: String
        switch (observation.source, observation.charging) {
        case (_, .charging):
            symbolName = "bolt.fill"
            state = "Charging"
        case (.external, _):
            symbolName = "powerplug"
            state = "Plugged in"
        case (.battery, _):
            symbolName = Self.batterySymbol(percent)
            state = "On battery"
        case (.ups, _):
            symbolName = "bolt.horizontal.circle"
            state = "On UPS"
        case (.unknown, _):
            symbolName = "questionmark.circle"
            state = "Power unknown"
        }
        spoken = level.isEmpty ? state : "\(state), \(level)"
    }

    /// The battery glyph nearest the level, so the picture agrees with the number.
    private static func batterySymbol(_ percent: Int?) -> String {
        guard let percent else { return "battery.50percent" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
