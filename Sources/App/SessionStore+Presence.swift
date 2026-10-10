import SwiftUI
import AppKit
import Combine

extension SessionStore {
    var hasScheduledTicker: Bool { ticker != nil }

    /// Wakes are machine events. Keep sampling on the existing ticker, but do
    /// not let the HID reset count as a return.
    func noteMachineWake() {
        powerCoverageLapsed = true
        presenceGate.noteMachineWake()
        deferredAutomationPending = true
    }

    /// Captures the current frontmost app without delivering an activation. A
    /// later unlock may reveal a newer app than an earlier workspace notice, so
    /// both pending candidates are updated together before confirmation.
    func prepareTrackingResume(bundleID: String?, name: String) {
        withRefreshTransaction {
            tracker?.prepareToResume(bundleID: bundleID, name: name)
            if presenceGate.isAwaitingConfirmation {
                pendingWakeActivation = (bundleID, name)
            }
        }
    }

    /// Unlock and explicit returns are direct proof of presence. A waiting app
    /// candidate begins at this instant; an already-active tracker is unchanged.
    @discardableResult
    func confirmPresence(at moment: Date) -> Bool {
        var releasesAutomation = false
        withRefreshTransaction {
            presenceGate.confirm(at: moment)
            tracker?.confirmPresence(at: moment)
            if let pendingWakeActivation {
                engine.transition(on: .appActivated(bundleID: pendingWakeActivation.bundleID,
                                                    name: pendingWakeActivation.name))
                _ = applyLongAwayResult()
                self.pendingWakeActivation = nil
            }
            if deferredAutomationPending {
                deferredAutomationPending = false
                releasesAutomation = true
            }
        }
        if releasesAutomation { onDeferredAutomationReady?() }
        return releasesAutomation
    }

    /// Workspace activation is not proof of presence after wake. The tracker and
    /// coordinator candidates still follow the latest app, while engine state
    /// and automation remain untouched until the gate is confirmed.
    @discardableResult
    func handleApplicationActivation(bundleID: String?, name: String) -> Bool {
        var delivered = false
        withRefreshTransaction {
            if presenceGate.isAwaitingConfirmation {
                tracker?.prepareToResume(bundleID: bundleID, name: name)
                pendingWakeActivation = (bundleID, name)
            } else {
                tracker?.appActivated(bundleID: bundleID, name: name)
                engine.transition(on: .appActivated(bundleID: bundleID, name: name))
                _ = applyLongAwayResult()
                delivered = true
            }
        }
        return delivered
    }

    /// How often the open usage stretch is written to disk, bounding what an
    /// unclean exit can lose.
    private static let flushEverySeconds = 60

    /// How often continuous use is re-checked against the break thresholds.
    private static let breakCheckSeconds = 5

    /// Presence is categorical for the engine: once the gate confirms input,
    /// its age must not be reinterpreted as continued quiet. The tracker still
    /// receives the honest `since` date separately.
    func applyPresenceObservation(_ observation: PresenceObservation) -> TimeInterval {
        switch observation {
        case .active(let since):
            confirmPresence(at: since)
            return 0
        case .quiet(let seconds): return seconds
        }
    }

    /// One sample a second: seconds since the last input, told apart into
    /// idle and watched. Quiet in front of a film, a call or a presentation is
    /// presence, and the engine must not read it as an absence. Watching is
    /// read from powerd at most every five seconds and only once a minute of
    /// quiet has built up — nothing depends on it before then.
    private func observeIdle() {
        let raw = idle.idleSeconds()
        let now = Date()
        let displayAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        let observation = presenceGate.observe(rawIdleSeconds: raw,
                                               at: now,
                                               displayAwake: displayAwake,
                                               screenLocked: screenLocked)
        let quiet = applyPresenceObservation(observation)
        sampleWorkTraffic(now: now, quiet: quiet,
                          screenInUse: displayAwake && !screenLocked && !presenceGate.isAwaitingConfirmation)
        if quiet < 60 {
            // Recent input: nothing to tell apart, and any watching is over.
            watchingCache = nil
            quietSampler.noteInput()
            tracker?.observeIdle(seconds: quiet)
            engine.transition(on: .idleObserved(seconds: quiet))
            return
        }
        let holders: WatchDetector.Reading
        if let cache = watchingCache, now.timeIntervalSince(cache.at) < 5 {
            holders = cache.value
        } else {
            holders = readWatching()
            watchingCache = (now, holders)
        }
        // An agent at work is watched too, but only on a screen someone could
        // be looking at: never locked, asleep, or woken without a person.
        let lastActivity = [lastAgentPing, workTraffic.lastBusy].compactMap { $0 }.max()
        let agentSeen = displayAwake && !screenLocked && !presenceGate.isAwaitingConfirmation
            ? AgentPresence.lastSeen(now: now, quiet: quiet, lastActivity: lastActivity,
                                     frontmostBundleID: engine.currentAppBundleID,
                                     keptAwake: holders.keptAwake,
                                     policy: engine.store.agentQuietPolicy,
                                     countsAppInFront: engine.store.countsAgentAppInFront,
                                     countsKeepAwake: engine.store.countsKeepAwake,
                                     cap: engine.store.longAwayCap)
            : nil
        let reading = quietSampler.read(now: now, quiet: quiet, film: holders.watching, agentSeen: agentSeen,
                                        idlePaused: engine.state == .paused(reason: .idle))
        tracker?.observeIdle(seconds: reading.trackerSeconds)
        engine.transition(on: reading.event)
    }

    /// One network reading every `WorkTraffic.interval` of quiet, so a coding
    /// or AI app at work is known by the time quiet would pause anything.
    /// Only where an agent can still change something — a running session, a
    /// watched pause, the away question — and on a screen in use: an idle
    /// pause or a locked night would otherwise read every 20 seconds for hours,
    /// for nothing. Typing stops the readings; the next quiet starts afresh.
    private func sampleWorkTraffic(now: Date, quiet: TimeInterval, screenInUse: Bool) {
        switch engine.state {
        case .running, .paused(reason: .watching), .awaitingUserDecision: break
        default: return
        }
        guard quiet >= WorkTraffic.interval, quiet < engine.store.longAwayCap, screenInUse, !trafficReadPending,
              engine.store.detectsAgentTraffic, engine.store.agentQuietPolicy != .ignore,
              lastTrafficRead.map({ now.timeIntervalSince($0) >= WorkTraffic.interval }) ?? true
        else { return }
        trafficReadPending = true
        lastTrafficRead = now
        readWorkTraffic { [weak self] reading in
            guard let self else { return }
            self.trafficReadPending = false
            guard let reading else { return }
            let workApps = Set(reading.apps.values.filter(AgentPresence.isWorkApp))
            self.workTraffic.observe(totals: reading.totals,
                                     app: { reading.apps[$0].flatMap { workApps.contains($0) ? $0 : nil } },
                                     at: Date())
        }
    }

    /// The app's one repeating timer: it observes presence, drives engine
    /// transitions, persists checkpoints, updates live figures and evaluates
    /// breaks. It is operational state machinery, not a cosmetic title timer.
    func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.observeIdle()
            // Nothing else writes the open stretch to disk on a schedule, so a
            // crash, a Force Quit or a `kill` took everything since the last app
            // switch with it — `applicationWillTerminate` does not run for any
            // of those. Bounded to a minute now, instead of unbounded.
            if self.tick % SessionStore.flushEverySeconds == 0 {
                if self.tracker?.openSeconds(
                    exceeds: TimeInterval(SessionStore.flushEverySeconds)) == true {
                    self.tracker?.flush()
                }
                // The engine's snapshot has the same problem: `savedAt` is the
                // last app switch, and a relaunch reads everything since it as
                // an absence. A heartbeat bounds that to a minute too.
                if self.engine.state != .idle { self.engine.persist() }
            }
            // Breaks are timed from continuous use, which nothing else observes
            // on a schedule: staying inside one app posts no notification, so a
            // check driven only by refreshes never fired for exactly the person
            // this feature exists for. Every few seconds is enough for a
            // countdown shown in minutes, and keeps the archive walk off 1 Hz.
            if self.tick % SessionStore.breakCheckSeconds == 0 { self.refreshBreak() }
            self.updateTimeDrivenFigures()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
