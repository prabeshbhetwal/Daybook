import Foundation

/// What the existing sampler read for most of a beat's seconds. Recorded, never decided here.
enum BeatPresence: String, Codable { case input, quiet, watched, agent, watchPause, paused }

/// One app's stretch of a beat, with the input counts read while it was in front.
struct BeatSlice: Codable, Equatable {
    /// Bundle identifier; "" when none was in front.
    let app: String
    var seconds: Int
    var keys: Int
    var clicks: Int
    var scrolls: Int
    /// What kind of site the browser showed for this stretch; nil when none was read.
    var site: SiteKind? = nil

    private enum CodingKeys: String, CodingKey {
        case app = "a", seconds = "d", keys = "k", clicks = "c", scrolls = "w", site = "y"
    }
}

extension BeatSlice {
    /// A kind this build does not know reads as none, so the beat line still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(app: try container.decode(String.self, forKey: .app),
                  seconds: try container.decode(Int.self, forKey: .seconds),
                  keys: try container.decode(Int.self, forKey: .keys),
                  clicks: try container.decode(Int.self, forKey: .clicks),
                  scrolls: try container.decode(Int.self, forKey: .scrolls),
                  site: (try? container.decode(String.self, forKey: .site)).flatMap(SiteKind.init(rawValue:)))
    }
}

/// A compact record of one 30-second cell of the day: the evidence a later
/// reader weighs, never a verdict. Stored a line each, with short keys. `Core` only.
struct Beat: Codable, Equatable {
    static let schemaVersion = 1

    let version: Int
    /// A multiple of 30 seconds from the reference date, so no calendar is involved.
    let start: Date
    /// Seconds into the cell where recording began; 0 unless the beat opened late.
    var offset: Int
    /// In the order they were in front, from `start + offset`.
    var slices: [BeatSlice]
    var presence: BeatPresence
    /// Sorted; nil when the sampler did not read holders in this beat.
    var watchedApps: [String]?

    private enum CodingKeys: String, CodingKey {
        case version = "v", start = "t", offset = "f", slices = "s", presence = "p"
        case watchedApps = "h"
    }

    init(start: Date, offset: Int = 0, slices: [BeatSlice], presence: BeatPresence,
         watchedApps: [String]? = nil) {
        self.version = Self.schemaVersion
        self.start = start
        self.offset = offset
        self.slices = slices
        self.presence = presence
        self.watchedApps = watchedApps
    }

    /// A partial beat ends early.
    var end: Date {
        start.addingTimeInterval(TimeInterval(offset + slices.reduce(0) { $0 + $1.seconds }))
    }

    /// floor(timeIntervalSinceReferenceDate / 30) * 30; no calendar involved.
    static func gridStart(for date: Date) -> Date {
        let length = ActivityConstants.beatLength
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / length).rounded(.down) * length)
    }

    /// A line from a newer schema fails here, so `JournalFile.replay` passes it over.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Beat schema \(version) is not one this build reads")
        }
        self.version = version
        start = Date(timeIntervalSinceReferenceDate: TimeInterval(try container.decode(Int.self, forKey: .start)))
        let offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        let slices = try container.decode([BeatSlice].self, forKey: .slices)
        // The recorder keeps every second inside its cell and every count a UInt32 delta. A line that
        // does not is damaged: passed over here, because sums over its slices (`end`, the credit) would overflow.
        let cell = Int(ActivityConstants.beatLength), counts = 0...Int(UInt32.max)
        guard (0...cell).contains(offset),
              slices.allSatisfy({ (0...cell).contains($0.seconds) && counts.contains($0.keys)
                                  && counts.contains($0.clicks) && counts.contains($0.scrolls) }),
              offset + slices.reduce(0, { $0 + $1.seconds }) <= cell else {
            throw DecodingError.dataCorruptedError(forKey: .slices, in: container,
                                                   debugDescription: "A beat holds more than its cell, or a count no counter reaches")
        }
        self.offset = offset
        self.slices = slices
        presence = try container.decode(BeatPresence.self, forKey: .presence)
        watchedApps = try container.decodeIfPresent([String].self, forKey: .watchedApps)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(Int(start.timeIntervalSinceReferenceDate.rounded()), forKey: .start)
        if offset != 0 { try container.encode(offset, forKey: .offset) }
        try container.encode(slices, forKey: .slices)
        try container.encode(presence, forKey: .presence)
        try container.encodeIfPresent(watchedApps, forKey: .watchedApps)
    }
}
