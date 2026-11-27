import Foundation

/// How a counted second is credited (spec section 2). The first rule that matches wins.
/// `agent` is the Agent lane: an agent worked with nobody at the keyboard. Its purpose is
/// the agent app's, for the phase strip, but it is not the person's credit.
enum CreditState: String, Codable { case engaged, held, quietKept, passive, agent }

struct CreditedSlice: Equatable {
    let start: Date
    let end: Date
    /// The app in front.
    let app: String
    let state: CreditState
    /// nil: counted but credited to nothing (passive on an app with no engaged slice yet, inside the grace).
    let purpose: AppPurpose?
    /// The site kind the browser showed; set only with the site signal on, even where a purpose
    /// the person set for the app decided the credit.
    var site: SiteKind? = nil
    /// The app holding the screen awake, for a held slice: the one its purpose was read from.
    var holder: String? = nil
}

struct CreditInput {
    let beats: [Beat]
    /// The session's counted time, from `CountedTime.spans` (below). Nothing outside it is credited.
    let counted: [DateInterval]
    /// Signals on for this derivation: those any beat in the bounds carries (`SignalKind.carried(by:)`).
    /// Sites are read only with `.siteKind` here; the label's counterfactual removes it.
    let signals: Set<SignalKind>
    let purposeOverrides: [String: String]
    /// The session's Agent lane; nil for a session from before it, whose agent time is
    /// still credited to the session's first app as it always was.
    var agent: [AgentSpan]? = nil
}

/// Credits every counted second to what the hands and screen were doing:
/// 1 engaged, 2 held (`ActivityCredit+Held.swift`), 3a quiet-kept, 3b passive.
/// Pure: the same beats, spans and overrides always give the same slices.
enum ActivityCredit {
    /// Any key, or clicks + scrolls ≥ engagedClickScrollPerBeat.
    static func isEngaged(_ slice: BeatSlice) -> Bool {
        slice.keys > 0 || slice.clicks + slice.scrolls >= ActivityConstants.engagedClickScrollPerBeat
    }

    static func credit(_ input: CreditInput) -> [CreditedSlice] {
        let beats = ordered(input.beats)
        guard let firstStart = beats.first.map(opening) else { return [] }
        let overrides = input.purposeOverrides
        let placed = pieces(of: beats)
        let counted = input.counted.sorted { $0.start < $1.start }
        let engaged = placed.filter(\.engaged).map(\.interval)
        let held = heldRuns(beats: beats, counted: counted, engaged: engaged, firstStart: firstStart,
                            overrides: overrides, signals: input.signals)
        let heldSpans = held.map(\.interval)
        let anchor = placed.first(where: \.engaged)?.app
        var quietSince = firstStart
        var engagedApps: Set<String> = []
        // Time the agent worked alongside the person is still theirs here.
        let lanes = (AgentLane.replacing(input.agent) ?? []).sorted { $0.start < $1.start }
        let laneCover = lanes.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }

        func purpose(_ app: String, _ activity: InputActivity) -> AppPurpose {
            PurposeMap.purpose(for: app, activity: activity, overrides: overrides)
        }
        func piecePurpose(_ piece: Piece, _ activity: InputActivity) -> AppPurpose {
            honouredSite(piece.site, app: piece.app, input)?.rule.purpose(activity) ?? purpose(piece.app, activity)
        }
        // Rules 3a and 3b: a quiet second outside every held run.
        func quiet(_ piece: Piece, from start: Date) -> (CreditState, AppPurpose?) {
            if piece.presence == .agent, input.agent == nil { return (.quietKept, purpose(anchor ?? piece.app, .active)) }
            let site = honouredSite(piece.site, app: piece.app, input)
            guard site?.rule.isAmbiguous ?? isAmbiguous(piece.app, overrides) else {
                return (.quietKept, piecePurpose(piece, .passive))
            }
            guard start.timeIntervalSince(quietSince) < ActivityConstants.watchGrace else {
                return (.passive, piecePurpose(piece, .passive))
            }
            return (.passive, engagedApps.contains(piece.app) ? piecePurpose(piece, .active) : nil)
        }

        var slices: [CreditedSlice] = []
        for piece in placed {
            // What the browser showed, kept even when the person's purpose decided the credit.
            let site = input.signals.contains(.siteKind) ? piece.site : nil
            for span in cut(piece.interval, by: counted) where span.by != nil {
                for part in cut(span.part, by: laneCover) {
                    if let lane = part.by {
                        slices.append(CreditedSlice(start: part.part.start, end: part.part.end, app: piece.app, state: .agent,
                                                    purpose: purpose(lanes[lane].app ?? anchor ?? piece.app, .active), site: site))
                        continue
                    }
                    if piece.engaged {
                        slices.append(CreditedSlice(start: part.part.start, end: part.part.end, app: piece.app,
                                                    state: .engaged, purpose: piecePurpose(piece, .active), site: site))
                        continue
                    }
                    for bit in cut(part.part, by: heldSpans) {
                        let (state, credited) = bit.by.map { (CreditState.held, held[$0].purpose as AppPurpose?) }
                            ?? quiet(piece, from: bit.part.start)
                        slices.append(CreditedSlice(start: bit.part.start, end: bit.part.end, app: piece.app,
                                                    state: state, purpose: credited, site: site,
                                                    holder: bit.by.map { held[$0].holder }))
                    }
                }
            }
            if piece.engaged {
                quietSince = piece.interval.end
                engagedApps.insert(piece.app)
            }
        }
        return slices
    }

    /// Ambiguous in the map and not overridden: only these are read by behaviour (rule 3b).
    /// An app the map does not list has a purpose that does not depend on behaviour, so it is fixed.
    static func isAmbiguous(_ app: String, _ overrides: [String: String]) -> Bool {
        PurposeMap.isAmbiguous(app) && PurposeMap.override(for: app, in: overrides) == nil
    }

    /// One slice of one beat, placed in time.
    struct Piece {
        let interval: DateInterval
        let app: String
        let engaged: Bool
        let presence: BeatPresence
        let site: SiteKind?
    }

    /// Where recording began in the beat.
    static func opening(_ beat: Beat) -> Date { beat.start.addingTimeInterval(TimeInterval(beat.offset)) }

    /// In time order. Two beats can share a grid start with different offsets, so never by start alone.
    static func ordered(_ beats: [Beat]) -> [Beat] {
        beats.sorted { (opening($0), $0.end) < (opening($1), $1.end) }
    }

    /// Every slice of ordered beats placed in time. A clock stepped back can leave two
    /// beats overlapping; a second already placed is not placed again.
    static func pieces(of beats: [Beat]) -> [Piece] {
        var pieces: [Piece] = []
        var placed = Date.distantPast
        for beat in beats {
            var at = opening(beat)
            for slice in beat.slices {
                let end = at.addingTimeInterval(TimeInterval(slice.seconds))
                let start = max(at, placed)
                if start < end {
                    pieces.append(Piece(interval: DateInterval(start: start, end: end), app: slice.app,
                                        engaged: isEngaged(slice), presence: beat.presence, site: slice.site))
                    placed = end
                }
                at = end
            }
        }
        return pieces
    }

    /// `interval` cut at the edges of `cover` (sorted by start): each part with the index
    /// of the cover interval holding it, or nil where none does.
    static func cut(_ interval: DateInterval, by cover: [DateInterval]) -> [(part: DateInterval, by: Int?)] {
        var parts: [(part: DateInterval, by: Int?)] = []
        var at = interval.start
        func add(_ end: Date, _ by: Int?) {
            if at < end { parts.append((DateInterval(start: at, end: end), by)) }
            at = max(at, end)
        }
        for (index, span) in cover.enumerated() where span.end > at && span.start < interval.end {
            add(span.start, nil)
            add(min(span.end, interval.end), index)
        }
        add(interval.end, nil)
        return parts
    }
}

/// What the engine counted. `DaySession.spans` are stretch bounds and include pauses,
/// so they are not this. Each record's start to end minus its `pausedSpans`. A record
/// with nil `pausedSpans` (older, or untrusted) is its bounds minus each run of `.paused`
/// or `.watchPause` beats, every run first extended back to the end of the last engaged
/// slice before it: the engine backdates a pause to where the quiet began, after beats
/// were already written as quiet.
///
/// Read from beats, a pause is known to slice resolution only, so it can count up to about
/// 29 s at its start (the engine backdates to the last keypress; the last engaged slice ends
/// at the end of its slice) and about 15 s at a resume that the engine did not. Manual, away
/// and break pauses are backdated the same way, though the engine starts them where they were
/// asked for: that removes counted time, never adds it.
enum CountedTime {
    static func spans(records: [(bounds: DateInterval, paused: [DateInterval]?)], beats: [Beat]) -> [DateInterval] {
        let fromBeats = records.contains { $0.paused == nil } ? backdatedPauses(beats) : []
        return records.flatMap { record in
            ActivityCredit.cut(record.bounds, by: (record.paused ?? fromBeats).sorted { $0.start < $1.start })
                .compactMap { $0.by == nil ? $0.part : nil }
        }.sorted { $0.start < $1.start }
    }

    /// Runs of paused beats, each reaching back to the end of the last engaged slice or the
    /// pause before it, whichever is later; with neither, to the record's start.
    private static func backdatedPauses(_ beats: [Beat]) -> [DateInterval] {
        var pauses: [DateInterval] = []
        var quietSince = Date.distantPast
        var run: DateInterval?
        for piece in ActivityCredit.pieces(of: ActivityCredit.ordered(beats)) {
            if piece.presence == .paused || piece.presence == .watchPause {
                run = DateInterval(start: run?.start ?? quietSince, end: piece.interval.end)
                continue
            }
            if let ended = run {
                pauses.append(ended)
                quietSince = ended.end
                run = nil
            }
            if piece.engaged { quietSince = piece.interval.end }
        }
        return pauses + (run.map { [$0] } ?? [])
    }
}
