import Foundation

/// Leisure blocks as Codex's review of 1.3.9 found them: quiet in a paused player is not listening, and a
/// block is named after the holder its time was credited to.
enum LeisureEvidenceChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A paused player left in front with nothing holding the screen is not a listening block", idlePlayerIsNoBlock),
        ("A block names the holder its time was credited to, not the first holder by name", blockNamesCreditedHolder),
        ("A long pause between two held stretches makes two blocks, not one across the pause", longPauseSplits),
        ("A block waits while a short quiet tail may still be a holder not read yet", shortTailWaits),
    ]

    private static func blocks(_ steps: [BeatTrace.Step], nowAfter: TimeInterval = 120,
                               edit: (inout Beat) -> Void = { _ in }) -> [LeisureBlock] {
        var beats = BeatTrace.beats(steps, from: SelfTest.base)
        for index in beats.indices { edit(&beats[index]) }
        let end = beats.map(\.end).max() ?? SelfTest.base
        return LeisureFinder.blocks(beats: beats, sessions: [], autoModeOn: true, after: .distantPast,
                                    now: end.addingTimeInterval(nowAfter))
    }

    private static func idlePlayerIsNoBlock() -> [String] {
        var problems: [String] = []
        let found = blocks([ActivityTraces.step("com.spotify.client", 12, .none)])
        expect(found.isEmpty, "twelve quiet minutes in a paused player are \(found)", &problems)
        let playing = blocks([ActivityTraces.step("com.spotify.client", 1, .none),
                              ActivityTraces.step("com.spotify.client", 11, .none, holder: "com.spotify.client"),
                              ActivityTraces.step("com.spotify.client", 6, .none)])
        expect(playing.count == 1, "a held run with a quiet lead-in is one block, got \(playing)", &problems)
        if let block = playing.first {
            SelfTest.expectClose(block.end.timeIntervalSince(SelfTest.base), 12 * 60,
                                 "the block ends when the holding stops, not after the quiet tail", &problems)
        }
        return problems
    }

    private static func blockNamesCreditedHolder() -> [String] {
        var problems: [String] = []
        let vlc = "org.videolan.vlc", teams = "com.microsoft.teams2"
        let found = blocks([ActivityTraces.step(vlc, 12, .none, holder: vlc)]) { beat in
            if !(beat.watchedApps ?? []).isEmpty { beat.watchedApps = [teams, vlc] }
        }
        expect(found.count == 1 && found.first?.bundleID == vlc,
               "VLC in front and Teams behind, both holding, names \(found.map(\.bundleID))", &problems)
        return problems
    }

    private static func longPauseSplits() -> [String] {
        var problems: [String] = []
        let player = "com.spotify.client"
        let found = blocks([ActivityTraces.step(player, 11, .none, holder: player),
                            ActivityTraces.step(player, 10, .none),
                            ActivityTraces.step(player, 11, .none, holder: player)])
        expect(found.count == 2, "eleven held, ten paused, eleven held minutes are \(found.count) blocks", &problems)
        if let second = found.last {
            SelfTest.expectClose(second.start.timeIntervalSince(SelfTest.base), 20 * 60,
                                 "the second block starts a minute before its holding, not across the pause", &problems)
        }
        return problems
    }

    private static func shortTailWaits() -> [String] {
        var problems: [String] = []
        let player = "com.spotify.client"
        let held = SelfTest.base.addingTimeInterval(12 * 60)
        let found = blocks([ActivityTraces.step(player, 12, .none, holder: player),
                            ActivityTraces.step(player, 1, .none, holder: player)], nowAfter: 30) { beat in
            if beat.end > held { beat.watchedApps = nil }
        }
        expect(found.isEmpty, "a block was written thirty seconds after a minute not read yet: \(found)", &problems)
        return problems
    }
}
