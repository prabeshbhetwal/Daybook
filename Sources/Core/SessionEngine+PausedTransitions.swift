import Foundation

extension SessionEngine {
    /// §3.1 rows for `.paused`. The `.watching` rows come first and win.
    func transitionFromPaused(on event: SessionEvent) -> Bool? {
        var forceEmit = false
        switch (state, event) {

        // .paused(.watching) — presence without input; input ends it quietly
        case (.paused(.watching), .appActivated(let bundleID, let name)):
            if isSelf(bundleID) { break }
            recordApp(bundleID: bundleID, name: name)
            endWatchingPause()
        case (.paused(.watching), .watchingObserved):
            break // still watching
        case (.paused(.watching), .idleObserved(let seconds)):
            if seconds < store.idlePauseThreshold {
                // Input is back, or the watching has only just ended.
                endWatchingPause()
            } else {
                // The watching ended a while ago and nobody has touched the
                // machine since. From here it is an ordinary idle pause,
                // measured from when the watching ended — not from the last
                // keypress before the film, which would put the film into the
                // question asked on return.
                let ended = now().addingTimeInterval(-seconds)
                endWatchingPause(endingAt: ended)
                enterPause(reason: .idle, at: ended)
            }
        case (.paused(.watching), .awayBegan(let trigger)):
            // A lock or sleep during the watching: the watched stretch closes
            // here and the absence begins now, so the question on return is
            // about the time away, not the film before it.
            endWatchingPause()
            recordAway(trigger)
        case (.paused(.watching), .awayEnded):
            // A display waking mid-film says the user was there all along.
            endWatchingPause()
        case (.paused(.watching), .manualResume):
            endWatchingPause()

        // .paused
        case (.paused(let reason), .appActivated(let bundleID, let name)):
            if isSelf(bundleID) { break }
            recordApp(bundleID: bundleID, name: name)
            cancelDwell()
            if reason == .idle {
                // Any activation is input, and input is the user back. An idle
                // pause is the app's own observation rather than the user's
                // act, so its end is resolved like any absence the app
                // observed: ended past the cap, asked about past the
                // threshold, resumed quietly below it. Touching a work app
                // after the cap starts a fresh one, as it does from `.idle`.
                if absenceOutgrewCap() {
                    _ = completeLongAway(intent: categories.category(for: bundleID) == .work
                        ? .beginFreshSession : .endOnly)
                } else {
                    endIdlePause()
                }
            } else if categories.category(for: bundleID) == .work {
                if absenceOutgrewCap() {
                    // Coming back to work after an absence past the cap: the
                    // old session ended where they left, and touching a work
                    // app is the same signal that starts one from `.idle`. The
                    // thread carries over, exactly as answering "I was away"
                    // would keep it.
                    _ = completeLongAway(intent: .beginFreshSession)
                } else if reason == .away {
                    endDeclaredAway()
                } else {
                    leavePause()
                }
            }
            // .neutral and .breakTime leave a deliberate pause untouched (D5)
        case (.paused, .overrideApplied(let bundleID)):
            if currentAppBundleID == bundleID,
               categories.category(for: bundleID) == .work {
                leavePause()
            }
        case (.paused(let reason), .manualResume):
            if absenceOutgrewCap() {
                _ = completeLongAway(intent: .beginFreshSession)
            } else if reason == .away {
                endDeclaredAway()
            } else {
                leavePause()
            }
        case (.paused, .awayBegan(let trigger)):
            recordAway(trigger)
        case (.paused(let reason), .awayEnded):
            // Already paused, so the pause accounts for the away time — unless
            // the absence began *before* the pause did. A lid closed at 15:50
            // opens an away; the idle sampler, which cannot see through sleep
            // (HID idle does not advance while the machine is off), may
            // back-date its pause only to 17:19; the absence is still the
            // earlier of the two. Dropping the interval here left 89 minutes
            // of closed lid standing as work.
            let lockedFor = awayInterval.map { self.interval(from: $0.start) } ?? 0
            if let interval = awayInterval, let began = pauseStartDate, interval.start < began {
                pauseStartDate = interval.start
            }
            awayInterval = nil
            // Unless the pause is an unattended one that the lock has now run
            // past the cap. That is the ordinary overnight: input stops, the
            // session pauses itself, the display sleeps and locks, and the
            // next event is this unlock in the morning. Left to the ticker,
            // the first sample after waking already sees fresh input — the
            // unlock itself — and would merge the whole night back into a
            // surviving session. Same rule as the lock path in `resolve`:
            // ended where input stopped.
            if absenceOutgrewCap() {
                _ = completeLongAway(intent: .endOnly)
            } else if lockedFor >= store.longAwayCap, let began = pauseStartDate {
                // A break-app pause is the user present, so the cap leaves it
                // alone. A lock past the cap is the user gone: Netflix, then
                // the night, must not resume from the evening when Xcode comes
                // up in the morning. Ended where the pause began.
                endStretch(leftAt: began)
            } else if reason == .idle {
                // Unlocking is the user back. The idle pause ends the way an
                // observed absence does — asked about past the threshold.
                endIdlePause()
            }
        case (.paused, .resetSession):
            guard archiveCurrentSession() else { onStateChanged?(state); return nil }
            beginFreshSession()
            forceEmit = true
        case (.paused, .markedAway):
            // Already stopped, but the reason matters: it changes what the menu
            // bar says and, through the coordinator, whether the background
            // recorder keeps running. Restamping `pauseStartDate` via
            // `enterPause` would silently turn the pause so far back into work.
            cancelDwell()
            state = .paused(reason: .away)
        case (.paused(let reason), .idleObserved(let seconds)):
            // An absence opened by a lock or a sleep and never closed by a
            // wake folds in first, so the cap and the question measure from
            // where it truly began.
            let unattended = max(seconds, awayInterval.map { self.interval(from: $0.start) } ?? 0)
            if seconds < FocusConstants.awayDebounce, let interval = awayInterval {
                if let began = pauseStartDate, interval.start < began {
                    pauseStartDate = interval.start
                }
                awayInterval = nil
            }
            // The cap is judged first, whatever this sample says. By the time
            // the first sample after a long absence arrives the user has
            // usually already touched the machine — that is often what woke
            // the ticker — so a "they are back, resume" rule evaluated first
            // folded the whole absence into a surviving session. The absence
            // is measured from the pause's own start, and past the cap the
            // session ended where input stopped, as the lock path rules in
            // `resolve(away:)`. This is also the lid-open overnight: no lock,
            // no wake event, only samples.
            if absenceOutgrewCap() {
                _ = completeLongAway(intent: .endOnly)
            } else if unattended >= store.longAwayCap, let began = pauseStartDate {
                // A break-app pause with nobody touching the machine, or a
                // lock never closed by a wake, past the cap: the user left.
                endStretch(leftAt: began)
            } else if reason == .idle, seconds < store.idlePauseThreshold {
                // Only an idle pause lifts itself. A pause the user pressed
                // stays pressed until they say otherwise — the app must not
                // overrule a deliberate act just because a key was struck.
                endIdlePause()
            }
        case (.paused, .launch), (.paused, .manualPause),
             (.paused, .dwellExpired), (.paused, .decision), (.paused, .watchingObserved):
            break // documented no-op
        default:
            break // unreachable: every row for this state is listed above
        }
        return forceEmit
    }
}
