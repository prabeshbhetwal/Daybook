import AppKit
import Foundation
import SwiftUI

private final class FirstRunEvidenceBox {
    var values: Set<StoryRenderEvidence> = []
}

/// The welcome: who sees it, how it moves, what it says, and that each card
/// really draws.
enum FirstRunChecks {
    static let tests: [(String, () -> [String])] = [
        ("The welcome is offered to a new Mac only, and forced on request", gate),
        ("Welcome steps wait, report, and never trap the reader", flow),
        ("Every welcome card is complete and counts itself correctly", script),
        ("Each welcome card renders its own production evidence", render)
    ]

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
        // The two that matter on the build which first ships a welcome: a Mac
        // with a record has plainly met the app, whatever the flag says.
        expect(FirstRunGate.shouldWelcome(onboarded: false, hasSessionHistory: true,
                                          hasUsageHistory: false, forced: false),
               false, "Existing sessions suppress the welcome")
        expect(FirstRunGate.shouldWelcome(onboarded: false, hasSessionHistory: false,
                                          hasUsageHistory: true, forced: false),
               false, "Existing app-use history suppresses the welcome")
        expect(FirstRunGate.shouldWelcome(onboarded: true, hasSessionHistory: true,
                                          hasUsageHistory: true, forced: true),
               true, "--onboarding forces the welcome over every other answer")

        // The flag is durable, and absent means never asked.
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

    // MARK: - How it moves

    private static func flow() -> [String] {
        var failures: [String] = []

        // A waiting step does not advance on its own, and does not advance on
        // the wrong signal either.
        var progress = FirstRunProgress()
        progress.advance()
        if progress.beat != .controls {
            failures.append("The opener did not lead to the first step: \(progress.beat)")
        }
        progress.observe(FirstRunSignals(sessionRunning: true, otherAppRecorded: true))
        if progress.phase != .asking {
            failures.append("A later step's signal completed the step being asked")
        }
        progress.observe(FirstRunSignals(sessionControlsVisible: true))
        if progress.phase != .done {
            failures.append("Opening the controls did not complete the step waiting on it")
        }
        if !progress.performed.contains(.openControls) {
            failures.append("A completed step was not recorded as performed")
        }
        // The result note is the point of the step: completing it must not also
        // sweep the card away before it has been read.
        if progress.beat != .controls {
            failures.append("A completed step advanced itself past its own result")
        }

        // Every remaining step, in order, satisfied by the real signal.
        var signals = FirstRunSignals(sessionControlsVisible: true)
        progress.advance()
        if progress.beat != .start || progress.phase != .asking {
            failures.append("Next from a completed step did not open the next one")
        }
        signals.sessionRunning = true
        progress.observe(signals)
        if progress.phase != .done { failures.append("Starting a session did not complete step two") }
        progress.advance()
        signals.otherAppRecorded = true
        progress.observe(signals)
        if progress.phase != .done { failures.append("A recorded app did not complete step three") }
        progress.advance()
        if progress.beat != .spans { failures.append("The steps did not lead to the spans card") }
        progress.advance()
        if progress.beat != .finish { failures.append("The spans card did not lead to the last") }
        if progress.isFinished { failures.append("The last card was finished before it was read") }
        progress.advance()
        if !progress.isFinished { failures.append("The last card did not end the welcome") }

        // Nobody is trapped: a step nobody can manage is still steppable, and
        // stepping past it does not claim it was done.
        var stepped = FirstRunProgress()
        stepped.advance()
        if !stepped.isWaiting { failures.append("The first step did not report that it waits") }
        stepped.advance()
        if stepped.beat != .start {
            failures.append("A waiting step could not be stepped past: \(stepped.beat)")
        }
        if stepped.performed.contains(.openControls) {
            failures.append("A step the reader skipped was recorded as performed")
        }

        // Skip is an answer.
        var skipped = FirstRunProgress()
        skipped.skip()
        if !skipped.isFinished { failures.append("Skip did not end the welcome") }
        skipped.advance()
        if skipped.beat != .welcome {
            failures.append("A finished welcome still moved: \(skipped.beat)")
        }

        // The coach writes the answer down exactly once, however it ends.
        var written = 0
        let coach = FirstRunCoach { written += 1 }
        if coach.isActive { failures.append("A coach that was never begun reported itself active") }
        coach.advance()
        if written != 0 { failures.append("An inactive coach wrote an answer") }
        coach.begin()
        if !coach.isActive { failures.append("A begun coach did not report itself active") }
        coach.skip()
        if written != 1 { failures.append("Skip wrote the answer \(written) times, expected once") }
        if coach.isActive { failures.append("A skipped welcome stayed on screen") }

        var readThrough = 0
        let second = FirstRunCoach { readThrough += 1 }
        second.begin()
        for _ in FirstRunBeat.allCases { second.advance() }
        if readThrough != 1 {
            failures.append("Reading through wrote the answer \(readThrough) times, expected once")
        }
        if second.isActive { failures.append("A finished welcome stayed on screen") }
        return failures
    }

    // MARK: - What it says

    private static func script() -> [String] {
        var failures: [String] = []

        for beat in FirstRunBeat.allCases {
            let card = FirstRunScript.card(for: beat)
            if card.beat != beat {
                failures.append("\(beat) has no card of its own; it fell back to \(card.beat)")
            }
            if FirstRunScript.eyebrow(for: beat).isEmpty {
                failures.append("\(beat) resolves to an empty eyebrow")
            }
            if card.sentence.isEmpty || card.body.isEmpty {
                failures.append("\(beat) is missing its sentence or its body")
            }
            if card.forward.isEmpty { failures.append("\(beat) has no forward control") }
            if card.task != nil {
                // A step that waits owes the reader two things: a way past it,
                // and a word about what changed once they do it.
                if card.result == nil { failures.append("\(beat) waits but never says what changed") }
                if card.waiting == nil { failures.append("\(beat) waits with no way to step past it") }
                if card.anchor == nil { failures.append("\(beat) waits but points at nothing") }
                if card.eyebrow != nil {
                    failures.append("\(beat) writes its own eyebrow over the step count")
                }
            } else {
                if card.eyebrow == nil { failures.append("\(beat) has neither a step count nor an eyebrow") }
                if card.result != nil { failures.append("\(beat) has a result but nothing to wait for") }
            }
        }

        if FirstRunScript.cards.count != FirstRunBeat.allCases.count {
            failures.append("The script has \(FirstRunScript.cards.count) cards for "
                            + "\(FirstRunBeat.allCases.count) beats")
        }
        if Set(FirstRunScript.cards.map(\.beat)).count != FirstRunScript.cards.count {
            failures.append("Two cards claim the same beat")
        }
        if Set(FirstRunScript.cards.compactMap(\.task)).count != FirstRunScript.actionBeats.count {
            failures.append("Two steps wait on the same thing")
        }

        // The counter is derived, so it cannot drift from the steps it counts.
        let steps = FirstRunScript.actionBeats
        if steps.count != 3 { failures.append("Expected three steps, got \(steps.count)") }
        for (index, beat) in steps.enumerated() {
            let expected = "Step \(index + 1) of \(steps.count)"
            if FirstRunScript.eyebrow(for: beat) != expected {
                failures.append("\(beat) counts itself as "
                                + "\"\(FirstRunScript.eyebrow(for: beat))\", expected \"\(expected)\"")
            }
        }
        if FirstRunScript.stepNumber(for: .welcome) != nil {
            failures.append("A card that asks nothing was given a step number")
        }
        return failures
    }

    // MARK: - That it draws

    private static func render() -> [String] {
        var failures: [String] = []
        var progress = FirstRunProgress()

        for beat in FirstRunBeat.allCases {
            if progress.beat != beat {
                failures.append("Walking the welcome reached \(progress.beat), expected \(beat)")
                break
            }
            let frame = renderCard(progress)
            let expected = StoryRenderEvidence.firstRun(beat)
            if !frame.contains(expected) {
                failures.append("\(beat) did not draw \(expected.rawValue)")
            }
            let others = Set(FirstRunBeat.allCases.filter { $0 != beat }
                .map(StoryRenderEvidence.firstRun))
            let bleed = others.intersection(frame)
            if !bleed.isEmpty {
                failures.append("\(beat) also drew \(bleed.map(\.rawValue).sorted())")
            }
            progress.advance()
        }

        // The completed state is its own reading and must draw the same card.
        var done = FirstRunProgress()
        done.advance()
        done.observe(FirstRunSignals(sessionControlsVisible: true))
        if !renderCard(done).contains(.firstRunControls) {
            failures.append("A completed step stopped drawing its card")
        }
        return failures
    }

    /// An offscreen render of one card, returning the production evidence it
    /// emitted. An in-process accessibility walk cannot see SwiftUI, so the
    /// evidence seam is what proves which branch drew.
    private static func renderCard(_ progress: FirstRunProgress) -> Set<StoryRenderEvidence> {
        let evidence = FirstRunEvidenceBox()
        let card = WelcomeCoachCard(progress: progress, onForward: {}, onSkip: {})
            .frame(width: 520, height: 420, alignment: .bottomLeading)
            .background(Tokens.Colour.ground)
            .onPreferenceChange(StoryRenderEvidenceKey.self) { evidence.values = $0 }
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
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
