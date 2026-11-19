import Foundation

/// Beats from the ticker. What `observeIdle()` read each second is cut into 30-second beats and
/// written to the day's file. Evidence only: nothing here reads back into the engine, the tracker,
/// the presence gate or the sampler, so recording changes nothing a session counts.
extension SessionStore {
    /// "Record app use" is on, and a session is not idle or automatic sessions are on. With app use
    /// not recorded, which app was in front is kept nowhere, beats included.
    var recordsBeats: Bool {
        activityEvidence.enabled && engine.store.isUsageTrackingEnabled
            && (engine.state != .idle || engine.store.autoSessionsEnabled)
    }

    /// What `observeIdle()` read this second, named for the beat; `watched` is nil when it did not read
    /// holders. The engine's own state comes first: a pause is a pause whatever the sampler saw.
    func noteBeatReading(_ read: BeatPresence, watched: Set<String>?) {
        switch engine.state {
        case .paused(reason: .watching): activityEvidence.lastPresence = .watchPause
        case .paused, .awaitingUserDecision, .idle: activityEvidence.lastPresence = .paused
        case .running: activityEvidence.lastPresence = read
        }
        activityEvidence.lastWatched = watched
    }

    /// Called by runTick right after observeIdle. Appends any beat that closed.
    func recordBeatTick(at now: Date) {
        let evidence = activityEvidence
        guard evidence.enabled else { return }
        pruneBeatsOncePerDay(at: now)
        guard recordsBeats else { return endBeatRecording(at: now) }
        if !evidence.recording {
            evidence.recording = true
            // No count of timeouts or read in flight outlasts the recording before this one (R9).
            evidence.siteReader?.reset()
            // A launch seeds the engine with the app in front without telling the recorder, and
            // activations in the stretch before this one were not passed on.
            noteBeatActivation(bundleID: engine.currentAppBundleID, at: now)
        }
        let closed = evidence.recorder.tick(at: now, presence: evidence.lastPresence, watchedApps: evidence.lastWatched,
                                            counters: { evidence.reading }, idleSeconds: idle.idleSeconds)
        append(closed)
        // Each edge asks again, whether or not the app changed: an answer the recorder dropped near one
        // is asked for within a beat.
        if closed != nil { requestSiteRead(app: engine.currentAppBundleID, at: now) }
    }

    /// Recording has ended (the session stopped, a setting went off) or the app is quitting: the partial
    /// beat is written, once, so a quit or an update does not lose up to 29 seconds. Reads nothing when
    /// nothing was being recorded, so an idle ticker reads no counters.
    func endBeatRecording(at now: Date) {
        let evidence = activityEvidence
        guard evidence.recording else { return }
        evidence.recording = false
        evidence.siteReader?.reset()
        append(evidence.recorder.stop(at: now, counters: evidence.reading, idleSeconds: idle.idleSeconds()))
    }

    /// Called where handleApplicationActivation delivers an activation, and where delivery resumes after
    /// a stretch without it (a wake or lock waiting for the person, a break), so no second accrues to an
    /// app that is no longer in front. Only while recording. Daybook's own window is not an app the
    /// session was in, as for the engine and the usage tracker.
    func noteBeatActivation(bundleID: String?, at now: Date) {
        guard recordsBeats, bundleID != FocusConstants.bundleIdentifier else { return }
        let evidence = activityEvidence
        evidence.recorder.activate(app: bundleID, at: now, counters: evidence.reading,
                                   idleSeconds: idle.idleSeconds())
        requestSiteRead(app: bundleID, at: now)
    }

    private func append(_ beat: Beat?) {
        guard let beat else { return }
        do { try activityEvidence.archive.append(beat) } catch { ActivityEvidence.noteAppendFailure(error) }
    }

    /// Evidence expires: the first tick or refresh of each local day removes what is past its retention.
    /// A refresh runs at launch and when "Record app use" is switched off, when no tick may come.
    func pruneBeatsOncePerDay(at now: Date) {
        let day = periodCalendar.startOfDay(for: now)
        guard activityEvidence.enabled, activityEvidence.lastPruneDay != day else { return }
        activityEvidence.lastPruneDay = day
        activityEvidence.archive.prune(olderThan: ActivityConstants.defaultBeatRetentionDays, now: now)
    }
}
