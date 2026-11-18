import Foundation

/// The system's running input counts, read as they are; each wraps at 2^32.
struct CounterReading: Equatable {
    let keys: UInt32
    let clicks: UInt32
    let scrolls: UInt32
}

/// Cuts the 1 Hz ticker's readings into 30-second beats. `Core` only: it reads no clock and
/// no counter itself. The caller passes every reading, and the closures given to `tick` run
/// only when a beat closes, so a beat costs one read.
///
/// Every time inside a beat is a whole second from its grid start, each boundary rounded
/// once and shared by the slice that ends there and the one that begins, so a beat's slices
/// are contiguous and no second is counted twice.
struct BeatRecorder {
    /// A tick later than this after the last one means ticks were lost: sleep, lock or a stall.
    private static let tickGap: TimeInterval = 2

    private struct OpenSlice {
        let app: String
        let opened: Date
        /// When `baseline` was read: the idle guard measures from here, not from `opened`,
        /// which a late tick can put up to a second earlier.
        let baselineAt: Date
        let baseline: CounterReading
    }

    /// A beat in progress always has a slice open.
    private struct OpenBeat {
        let start: Date
        let offset: Int
        var closed: [BeatSlice] = []
        var slice: OpenSlice
        var ticks: [BeatPresence: Int] = [:]
        /// The last non-empty holder set seen, and whether holders were read at all.
        var holders: Set<String>?
        var holdersRead = false
    }

    private var beat: OpenBeat?
    private var lastTick: Date?
    private var frontApp = ""
    /// Where the last beat handed back ended. After a stop or a clock step back of up to a beat,
    /// no beat opens before it, so no second is recorded twice.
    private var recordedThrough: Date?

    /// The front app changed. Closes the open slice at `at`.
    mutating func activate(app: String?, at: Date, counters: CounterReading, idleSeconds: TimeInterval) {
        let name = app ?? ""
        guard name != frontApp else { return }
        frontApp = name
        // Past the edge, or after lost ticks, the next tick closes this beat and opens the
        // new app's slice in the one after it: opening one here would span the gap.
        guard var open = beat, let last = lastTick, at.timeIntervalSince(last) <= Self.tickGap,
              at < Self.edge(of: open) else { return }
        let cut = max(at, open.slice.opened)
        open.closed.append(Self.close(open.slice, in: open.start, at: cut, readAt: at, reading: counters,
                                      idle: idleSeconds, unseen: 0))
        open.slice = OpenSlice(app: name, opened: cut, baselineAt: at, baseline: counters)
        beat = open
    }

    /// One ticker second. Returns the beat that closed, if a grid edge or a gap was crossed.
    /// `counters` and `idleSeconds` are called only when a beat closes.
    mutating func tick(at: Date, presence: BeatPresence, watchedApps: Set<String>?,
                       counters: () -> CounterReading, idleSeconds: () -> TimeInterval) -> Beat? {
        var finished: Beat?
        var reading: CounterReading?  // a closing reading is the next slice's baseline
        var opened = at
        if let open = beat, let last = lastTick {
            let edge = Self.edge(of: open)
            let lost = at < last || at.timeIntervalSince(last) > Self.tickGap
            if lost || at >= edge {
                let now = counters()
                finished = Self.finish(open, cut: lost ? last : edge, readAt: at, reading: now,
                                       idle: idleSeconds(), unseen: Self.unseen(at, since: last))
                reading = now
                beat = nil
                if let end = finished?.end { recordedThrough = end }
                // The next beat begins where this one ended, not when the late tick arrived.
                if !lost { opened = edge }
            }
        }
        // A clock stepped back: wait until time passes what is already recorded. A step of more
        // than a beat means the earlier time was the wrong one (a clock a day ahead, corrected),
        // so record from here rather than go quiet until the wrong time comes round.
        if beat == nil, let through = recordedThrough, opened < through {
            if through.timeIntervalSince(opened) <= ActivityConstants.beatLength { return finished }
            recordedThrough = nil
        }
        var current: OpenBeat
        if let open = beat {
            current = open
        } else {
            let start = Beat.gridStart(for: opened)
            current = OpenBeat(start: start, offset: Self.second(opened, in: start),
                               slice: OpenSlice(app: frontApp, opened: opened, baselineAt: at,
                                                baseline: reading ?? counters()))
        }
        current.ticks[presence, default: 0] += 1
        if let held = watchedApps {
            current.holdersRead = true
            if !held.isEmpty { current.holders = held }
        }
        beat = current
        lastTick = at
        return finished
    }

    /// Recording stops. Returns the partial beat, if any, with the presence and holders seen so far.
    mutating func stop(at: Date, counters: CounterReading, idleSeconds: TimeInterval) -> Beat? {
        defer { beat = nil; lastTick = nil }
        guard let open = beat, let last = lastTick else { return nil }
        let lost = at.timeIntervalSince(last) > Self.tickGap
        let finished = Self.finish(open, cut: lost ? last : min(at, Self.edge(of: open)), readAt: at,
                                   reading: counters, idle: idleSeconds,
                                   unseen: Self.unseen(at, since: last))
        if let end = finished?.end { recordedThrough = end }
        return finished
    }

    // MARK: Closing

    private static func edge(of beat: OpenBeat) -> Date {
        beat.start.addingTimeInterval(ActivityConstants.beatLength)
    }

    /// Whole seconds from the beat's start, kept inside the cell.
    private static func second(_ date: Date, in start: Date) -> Int {
        min(max(Int(date.timeIntervalSince(start).rounded()), 0), Int(ActivityConstants.beatLength))
    }

    /// How long the ticks had been silent at `at`, when that is a beat or more (sleep, lock, a long
    /// stall). A shorter silence, such as one skipped timer fire, is zero: the typing it saw stays.
    private static func unseen(_ at: Date, since last: Date) -> TimeInterval {
        let silence = at.timeIntervalSince(last)
        return silence >= ActivityConstants.beatLength ? silence : 0
    }

    /// The slice up to `cut`, with the counts it was in front for. `idle` is the system idle
    /// clock at `readAt`: at least the time since the baseline was read means no real input
    /// reached the slice, so any counts are an agent's or a remote session's, never the person's.
    /// `unseen` is the long silence before the reading; input newer than that came in the gap,
    /// not the slice, so its counts go (real typing just before the stall too).
    private static func close(_ slice: OpenSlice, in start: Date, at cut: Date, readAt: Date,
                              reading: CounterReading, idle: TimeInterval, unseen: TimeInterval) -> BeatSlice {
        let real = idle < readAt.timeIntervalSince(slice.baselineAt) && idle >= unseen
        func delta(_ now: UInt32, _ before: UInt32) -> Int { real ? Int(now &- before) : 0 }
        return BeatSlice(app: slice.app,
                         seconds: max(second(cut, in: start) - second(slice.opened, in: start), 0),
                         keys: delta(reading.keys, slice.baseline.keys),
                         clicks: delta(reading.clicks, slice.baseline.clicks),
                         scrolls: delta(reading.scrolls, slice.baseline.scrolls))
    }

    /// The beat as stored; nil when it held no seconds.
    private static func finish(_ open: OpenBeat, cut: Date, readAt: Date, reading: CounterReading,
                               idle: TimeInterval, unseen: TimeInterval) -> Beat? {
        let last = close(open.slice, in: open.start, at: cut, readAt: readAt, reading: reading,
                         idle: idle, unseen: unseen)
        let slices = fold(open.closed + [last])
        guard slices.contains(where: { $0.seconds > 0 }) else { return nil }
        let unread: [String]? = open.holdersRead ? [] : nil
        return Beat(start: open.start, offset: open.offset, slices: slices, presence: majority(open.ticks),
                    watchedApps: open.holders?.sorted() ?? unread)
    }

    /// Left to right, a slice under `flickFold` joins the one before it, or the one after it when
    /// it comes first; a beat's only slice stays. Then neighbours in one app merge.
    private static func fold(_ slices: [BeatSlice]) -> [BeatSlice] {
        var kept: [BeatSlice] = []
        var carried: BeatSlice?
        for var slice in slices {
            if let before = carried { slice.absorb(before); carried = nil }
            if Double(slice.seconds) >= ActivityConstants.flickFold {
                kept.append(slice)
            } else if kept.isEmpty {
                carried = slice
            } else {
                kept[kept.count - 1].absorb(slice)
            }
        }
        if let only = carried { kept.append(only) }
        var merged: [BeatSlice] = []
        for slice in kept {
            if let previous = merged.last, previous.app == slice.app {
                merged[merged.count - 1].absorb(slice)
            } else {
                merged.append(slice)
            }
        }
        return merged
    }

    /// Most ticker seconds wins; a tie goes to the earlier of this order.
    private static func majority(_ ticks: [BeatPresence: Int]) -> BeatPresence {
        var best = BeatPresence.quiet
        var most = 0
        for presence in [BeatPresence.paused, .watchPause, .agent, .watched, .quiet, .input] {
            let count = ticks[presence] ?? 0
            if count > most { best = presence; most = count }
        }
        return best
    }
}

private extension BeatSlice {
    mutating func absorb(_ other: BeatSlice) {
        seconds += other.seconds
        keys += other.keys
        clicks += other.clicks
        scrolls += other.scrolls
    }
}
