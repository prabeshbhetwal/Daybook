import AppKit
import Foundation
import SwiftUI

private final class FirstRunEvidenceBox {
    var values: Set<StoryRenderEvidence> = []
}

/// The welcome: who sees it, how it moves, what it says, and that each chapter
/// really draws.
enum FirstRunChecks {
    static let tests: [(String, () -> [String])] = [
        ("The welcome is offered to a new Mac only, and forced on request", gate),
        ("Welcome steps wait, report, and never trap the reader", flow),
        ("The tour reads back, jumps by chapter, and ends once however it ends", navigation),
        ("Every welcome chapter and card is complete and counts itself correctly", script),
        ("Each welcome chapter renders its own production evidence", render),
        ("A ring around an edge-flush control stays inside the window", ringStaysOnScreen),
        ("The ring is visible in a still capture, moving or not", ringDraws)
    ]

    // MARK: - That the ring draws

    /// Renders the ring the way the snapshot harness renders everything —
    /// an offscreen hosting view cached to a bitmap — and reads pixels: the
    /// stroke must be the ring's blue, the inside must be lighter than the
    /// wash outside. Both the still ring and the one mid-settle must pass;
    /// a ring that only exists once its animation has finished is absent
    /// from every still and from a reader's first glance.
    private static func ringDraws() -> [String] {
        var failures: [String] = []
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 200)
        let target = CGRect(x: 110, y: 80, width: 100, height: 40)
        let frame = CoachRingGeometry.frame(around: target, within: bounds)
        for animated in [false, true] {
            let label = animated ? "moving ring" : "still ring"
            guard let bitmap = renderRing(rect: target, bounds: bounds, animated: animated) else {
                failures.append("\(label) produced no bitmap"); continue
            }
            let scale = CGFloat(bitmap.pixelsWide) / bounds.width
            func pixel(_ x: CGFloat, _ y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
                guard let c = bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?
                        .usingColorSpace(.sRGB) else { return nil }
                return (c.redComponent, c.greenComponent, c.blueComponent)
            }
            let onStroke = pixel(frame.minX + CoachRingGeometry.lineWidth / 2, frame.midY)
            let inside = pixel(frame.midX, frame.midY)
            let outside = pixel(20, 20)
            guard let onStroke, let inside, let outside else {
                failures.append("\(label): a probe fell outside the bitmap"); continue
            }
            // The stroke is the accent blue: blue well above red.
            if !(onStroke.b > onStroke.r + 0.25) {
                failures.append("\(label): no blue stroke where the ring should be "
                                + "(r \(onStroke.r), g \(onStroke.g), b \(onStroke.b))")
            }
            // The cut-out is lighter than the washed page around it.
            let insideLuma = 0.2126 * inside.r + 0.7152 * inside.g + 0.0722 * inside.b
            let outsideLuma = 0.2126 * outside.r + 0.7152 * outside.g + 0.0722 * outside.b
            if !(insideLuma > outsideLuma + 0.08) {
                failures.append("\(label): the cut-out is not lighter than the wash "
                                + "(inside \(insideLuma), outside \(outsideLuma))")
            }
        }
        return failures
    }

    private static func renderRing(rect: CGRect, bounds: CGRect, animated: Bool) -> NSBitmapImageRep? {
        let view = ZStack(alignment: .topLeading) {
            Color.white
            CoachRing(rect: rect, bounds: bounds, animated: animated)
        }
        .frame(width: bounds.width, height: bounds.height)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: bounds.size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.displayIfNeeded()
        defer { window.orderOut(nil); window.close() }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    // MARK: - Where the ring lands

    private static func ringStaysOnScreen() -> [String] {
        var failures: [String] = []
        let window = CGRect(x: 0, y: 0, width: 980, height: 680)
        let line = CoachRingGeometry.lineWidth

        // The rail: flush against the right edge and the bottom.
        let rail = CGRect(x: 644, y: 60, width: 336, height: 620)
        let ring = CoachRingGeometry.frame(around: rail, within: window)
        if ring.isNull { failures.append("The rail's ring was not drawn at all") }
        if ring.maxX > window.maxX - line || ring.maxY > window.maxY - line {
            failures.append("The rail's ring runs past the window: \(ring)")
        }
        if ring.minX > rail.minX || ring.minY > rail.minY {
            failures.append("The rail's ring does not surround the rail on its free sides: \(ring)")
        }
        // A control with room around it keeps its full inset on every side.
        let button = CGRect(x: 400, y: 300, width: 120, height: 32)
        let around = CoachRingGeometry.frame(around: button, within: window)
        let inset = CoachRingGeometry.inset
        if around != button.insetBy(dx: -inset, dy: -inset) {
            failures.append("A control with room around it lost its inset: \(around)")
        }
        // Something scrolled off screen draws nothing rather than a sliver.
        let gone = CGRect(x: 100, y: -200, width: 200, height: 100)
        if !CoachRingGeometry.frame(around: gone, within: window).isNull {
            failures.append("An off-screen control was still given a ring")
        }
        return failures
    }

    // MARK: - Who sees it

    private static func gate() -> [String] {
        var failures: [String] = []

        func expect(_ got: Bool, _ want: Bool, _ label: String) {
            if got != want { failures.append("\(label): expected \(want), got \(got)") }
        }

        expect(FirstRunGate.shouldWelcome(onboarded: false, hasSessionHistory: false,
                                          hasUsageHistory: false, forced: false),
               true, "A fresh Mac is welcomed")
        expect(FirstRunGate.shouldWelcome(onboarded: true, hasSessionHistory: false,
                                          hasUsageHistory: false, forced: false),
               false, "An answered welcome is not offered again")
        expect(FirstRunGate.shouldWelcome(onboarded: false, hasSessionHistory: true,
                                          hasUsageHistory: false, forced: false),
               false, "Existing sessions suppress the welcome")
        expect(FirstRunGate.shouldWelcome(onboarded: false, hasSessionHistory: false,
                                          hasUsageHistory: true, forced: false),
               false, "Existing app-use history suppresses the welcome")
        expect(FirstRunGate.shouldWelcome(onboarded: true, hasSessionHistory: true,
                                          hasUsageHistory: true, forced: true),
               true, "--onboarding forces the welcome over every other answer")

        let defaults = UserDefaults(suiteName: "com.prabesh.focuscontinuity.firstruncheck")
            ?? .standard
        defaults.removeObject(forKey: "fc.onboarded")
        let store = PersistenceStore(defaults: defaults)
        if store.hasOnboarded { failures.append("A store with no flag reported an answered welcome") }
        store.hasOnboarded = true
        if !PersistenceStore(defaults: defaults).hasOnboarded {
            failures.append("The answered welcome did not survive a fresh store")
        }
        defaults.removeObject(forKey: "fc.onboarded")
        return failures
    }

    // MARK: - How the steps move

    private static func flow() -> [String] {
        var failures: [String] = []

        var progress = FirstRunProgress()
        progress.advance()
        if progress.chapter != .firstSession || progress.card != 0 {
            failures.append("The opener did not lead to the first step: \(progress.chapter) \(progress.card)")
        }
        // A waiting step does not advance on its own, and not on the wrong
        // signal either.
        progress.observe(FirstRunSignals(sessionRunning: true, otherAppRecorded: true))
        if progress.phase != .asking {
            failures.append("A later step's signal completed the step being asked")
        }
        progress.observe(FirstRunSignals(activityFieldEngaged: true))
        if progress.phase != .done { failures.append("Reaching the activity field did not complete step one") }
        if !progress.performed.contains(.openControls) {
            failures.append("A completed step was not recorded as performed")
        }
        // The result note is the point: completing a step must not sweep the
        // card away before it has been read.
        if progress.card != 0 { failures.append("A completed step advanced itself past its own result") }

        var signals = FirstRunSignals(activityFieldEngaged: true)
        progress.advance()
        if progress.task != .startSession || progress.phase != .asking {
            failures.append("Next from a completed step did not open the next one")
        }
        signals.sessionRunning = true
        progress.observe(signals)
        if progress.phase != .done { failures.append("Starting a session did not complete step two") }
        progress.advance()
        if progress.task != nil { failures.append("Step two was not followed by its explanation") }
        progress.advance()
        if progress.task != .useAnotherApp {
            failures.append("The explanation did not lead to step three: \(progress.chapter) \(progress.card)")
        }
        signals.otherAppRecorded = true
        progress.observe(signals)
        if progress.phase != .done { failures.append("A recorded app did not complete step three") }

        // Everything after the steps is read, in order, and ends exactly once.
        var steps = 0
        while !progress.isFinished && steps < 200 { progress.advance(); steps += 1 }
        if !progress.isFinished { failures.append("Advancing never ended the welcome") }
        // Five cards are behind us; each remaining card is one advance, and
        // the last card takes one more to end the welcome.
        let expectedSteps = FirstRunScript.cardCount - 5 + 1
        if steps != expectedSteps {
            failures.append("Finishing took \(steps) advances from step three; expected \(expectedSteps)")
        }

        // Nobody is trapped: a waiting step is steppable, and stepping past it
        // does not claim it was done.
        var stepped = FirstRunProgress()
        stepped.advance()
        if !stepped.isWaiting { failures.append("The first step did not report that it waits") }
        stepped.advance()
        if stepped.task != .startSession {
            failures.append("A waiting step could not be stepped past: \(stepped.chapter) \(stepped.card)")
        }
        if stepped.performed.contains(.openControls) {
            failures.append("A step the reader skipped was recorded as performed")
        }
        return failures
    }

    // MARK: - How the tour is navigated

    private static func navigation() -> [String] {
        var failures: [String] = []

        // Back walks cards, and crosses a chapter boundary to its last card.
        var progress = FirstRunProgress()
        progress.back()
        if progress.chapter != .welcome || progress.card != 0 {
            failures.append("Back from the first card moved somewhere")
        }
        progress.jump(to: .macSaw)
        if progress.chapter != .macSaw || progress.card != 0 {
            failures.append("Jumping to a chapter did not land on its first card")
        }
        progress.back()
        let lastOfFirstSession = FirstRunScript.chapter(.firstSession).cards.count - 1
        if progress.chapter != .firstSession || progress.card != lastOfFirstSession {
            failures.append("Back from a chapter's first card did not reach the previous chapter's last: "
                            + "\(progress.chapter) \(progress.card)")
        }
        if !progress.visited.isSuperset(of: [.welcome, .macSaw, .firstSession]) {
            failures.append("Visited chapters were not all recorded: \(progress.visited)")
        }
        // Jumping into a step whose condition already holds completes it
        // honestly — it *is* done — and never claims one that does not.
        progress.jump(to: .firstSession)
        progress.observe(FirstRunSignals(activityFieldEngaged: true))
        if progress.phase != .done { failures.append("A step already satisfied did not show as done") }
        if progress.performed.contains(.startSession) {
            failures.append("A step never satisfied was marked performed")
        }

        // Skip is an answer.
        var skipped = FirstRunProgress()
        skipped.jump(to: .rail)
        skipped.skip()
        if !skipped.isFinished { failures.append("Skip did not end the welcome") }
        skipped.advance(); skipped.back(); skipped.jump(to: .welcome)
        if skipped.chapter != .rail {
            failures.append("A finished welcome still moved: \(skipped.chapter)")
        }

        // The coach writes the answer down exactly once, however it ends.
        var written = 0
        let coach = FirstRunCoach { written += 1 }
        if coach.isActive { failures.append("A coach never begun reported itself active") }
        coach.advance(); coach.back(); coach.jump(to: .finish)
        if written != 0 { failures.append("An inactive coach wrote an answer") }
        coach.begin()
        if !coach.isActive { failures.append("A begun coach did not report itself active") }
        coach.jump(to: .finish)
        coach.advance()
        if written != 1 { failures.append("Reading through wrote the answer \(written) times, expected once") }
        if coach.isActive { failures.append("A finished welcome stayed on screen") }

        var skips = 0
        let second = FirstRunCoach { skips += 1 }
        second.begin()
        second.skip()
        second.skip()
        if skips != 1 { failures.append("Skip wrote the answer \(skips) times, expected once") }
        return failures
    }

    // MARK: - What it says

    private static func script() -> [String] {
        var failures: [String] = []

        for chapter in FirstRunChapter.allCases {
            let entry = FirstRunScript.chapter(chapter)
            if entry.id != chapter {
                failures.append("\(chapter) has no chapter of its own; it fell back to \(entry.id)")
            }
            if entry.cards.isEmpty { failures.append("\(chapter) has no cards") }
            if chapter.title.isEmpty { failures.append("\(chapter) has no title") }
            for (index, card) in entry.cards.enumerated() {
                let label = "\(chapter) card \(index)"
                if card.sentence.isEmpty || card.body.isEmpty {
                    failures.append("\(label) is missing its sentence or its body")
                }
                if card.forward.isEmpty { failures.append("\(label) has no forward control") }
                if FirstRunScript.eyebrow(chapter: chapter, card: index).isEmpty {
                    failures.append("\(label) resolves to an empty eyebrow")
                }
                if card.task != nil {
                    // A step that waits owes the reader two things: a way past
                    // it, and a word about what changed once they do it.
                    if card.result == nil { failures.append("\(label) waits but never says what changed") }
                    if card.waiting == nil { failures.append("\(label) waits with no way to step past it") }
                    if card.anchor == nil { failures.append("\(label) waits but points at nothing") }
                } else if card.result != nil {
                    failures.append("\(label) has a result but nothing to wait for")
                }
            }
        }

        if FirstRunScript.chapters.count != FirstRunChapter.allCases.count {
            failures.append("The script has \(FirstRunScript.chapters.count) chapters for "
                            + "\(FirstRunChapter.allCases.count) ids")
        }
        if Set(FirstRunScript.chapters.map(\.id)).count != FirstRunScript.chapters.count {
            failures.append("Two entries claim the same chapter")
        }
        let tasks = FirstRunScript.taskCards
        if tasks.count != 3 { failures.append("Expected three steps, got \(tasks.count)") }
        if Set(tasks.map(\.task)).count != tasks.count { failures.append("Two steps wait on the same thing") }
        for (index, step) in tasks.enumerated() {
            let eyebrow = FirstRunScript.eyebrow(chapter: step.chapter, card: step.card)
            if !eyebrow.hasPrefix("Step \(index + 1) of \(tasks.count)") {
                failures.append("\(step.chapter) card \(step.card) counts itself as \"\(eyebrow)\"")
            }
        }
        if FirstRunScript.stepNumber(chapter: .welcome, card: 0) != nil {
            failures.append("A card that asks nothing was given a step number")
        }
        // The sample away card is raised only where the words say it is.
        let previewing = FirstRunScript.chapters.flatMap(\.cards).filter { $0.effect == .previewAwayCard }
        if previewing.count != 1 || FirstRunScript.chapter(.steppingAway).cards.first?.effect != .previewAwayCard {
            failures.append("The away-card rehearsal is not on the first card of Stepping away")
        }
        return failures
    }

    // MARK: - That it draws

    private static func render() -> [String] {
        var failures: [String] = []
        for chapter in FirstRunChapter.allCases {
            var progress = FirstRunProgress()
            progress.jump(to: chapter)
            let frame = renderCard(progress)
            let expected = StoryRenderEvidence.firstRun(chapter)
            if !frame.contains(expected) {
                failures.append("\(chapter) did not draw \(expected.rawValue)")
            }
            let others = Set(FirstRunChapter.allCases.filter { $0 != chapter }
                .map(StoryRenderEvidence.firstRun))
            let bleed = others.intersection(frame)
            if !bleed.isEmpty { failures.append("\(chapter) also drew \(bleed.map(\.rawValue).sorted())") }
        }
        // The completed state is its own reading and must draw the same chapter.
        var done = FirstRunProgress()
        done.advance()
        done.observe(FirstRunSignals(activityFieldEngaged: true))
        if !renderCard(done).contains(.firstRunFirstSession) {
            failures.append("A completed step stopped drawing its chapter")
        }
        return failures
    }

    /// An offscreen render of one card, returning the production evidence it
    /// emitted. An in-process accessibility walk cannot see SwiftUI, so the
    /// evidence seam is what proves which branch drew.
    private static func renderCard(_ progress: FirstRunProgress) -> Set<StoryRenderEvidence> {
        let evidence = FirstRunEvidenceBox()
        let card = WelcomeCoachCard(progress: progress, onForward: {}, onBack: {},
                                    onJump: { _ in }, onSkip: {})
            .frame(width: 560, height: 520, alignment: .bottomLeading)
            .background(Tokens.Colour.ground)
            .onPreferenceChange(StoryRenderEvidenceKey.self) { evidence.values = $0 }
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 520)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.displayIfNeeded()
        window.orderOut(nil)
        window.close()
        return evidence.values
    }
}
