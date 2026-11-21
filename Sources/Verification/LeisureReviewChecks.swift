import Foundation

/// Leisure blocks as the review of PR 119 found them: one across midnight shows on both days, and one held
/// by a player while another app was in front names the player.
enum LeisureReviewChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A leisure block across midnight shows its part on each day, however short that part is", acrossMidnight),
        ("A block held by a player while another app is in front names the player", heldNamesHolder),
    ]

    private static func acrossMidnight() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: false, auto: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: r.clock.value)
            guard let before = calendar.dateInterval(of: .day, for: midnight.addingTimeInterval(-60)),
                  let after = calendar.dateInterval(of: .day, for: midnight) else { return ["no days"] }
            let block = LeisureBlock(id: UUID(), start: midnight.addingTimeInterval(-480), end: midnight.addingTimeInterval(480),
                                     bundleID: LeisureBlockChecks.player, activity: .media)
            r.store.leisureStore.add([block])
            let late = r.store.leisureBlocks(on: before), early = r.store.leisureBlocks(on: after)
            expect(late.count == 1 && late.first?.start == block.start && late.first?.end == midnight && late.first?.id == block.id,
                   "the evening shows \(late)", &problems)
            expect(early.count == 1 && early.first?.start == midnight && early.first?.end == block.end && early.first?.id == block.id,
                   "the morning shows \(early)", &problems)
            return problems
        }
    }

    private static func heldNamesHolder() -> [String] {
        var problems: [String] = []
        let player = LeisureBlockChecks.player
        let beats = BeatTrace.beats([ActivityTraces.step(ActivityTraces.messaging, 12, .none, holder: player)],
                                    from: SelfTest.base)
        let end = beats.map(\.end).max() ?? SelfTest.base
        let found = LeisureFinder.blocks(beats: beats, sessions: [], autoModeOn: true, after: .distantPast,
                                         now: end.addingTimeInterval(120))
        expect(found.count == 1 && found.first?.bundleID == player,
               "a block held by \(player) with chat in front is \(found)", &problems)
        return problems
    }
}
