import CoreGraphics
import Foundation

/// Whether somebody is producing something, consuming something, or gone.
enum InputActivity: String, Equatable {
    case absent, passive, active
}

/// One reading of the system input counters.
struct InputSample: Equatable {
    let at: Date
    let keys: UInt32
    let clicks: UInt32
    let scrolls: UInt32
    let idleSeconds: TimeInterval
}

/// Reads cumulative per-type event *counts* — never event content — so it needs
/// no Input Monitoring grant, the same reasoning that makes `IdleMonitor`
/// permissible. Verified 2026-08-13: no TCC prompt, and the counters advance
/// under real input.
struct InputCounters {
    var keys: () -> UInt32 = {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown)
    }
    var clicks: () -> UInt32 = {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .leftMouseDown)
    }
    var scrolls: () -> UInt32 = {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .scrollWheel)
    }

    static let zero = InputCounters(keys: { 0 }, clicks: { 0 }, scrolls: { 0 })
}

/// Classifies recent input as active, passive or absent over a bounded window.
///
/// Fed at event boundaries — app activation, lock, unlock, wake — never on a
/// timer. A repeating timer would be the only polling in the app and would keep
/// the process off App Nap for the sake of a signal that is only ever consumed
/// when a stretch ends.
///
/// The counters also advance for synthetically posted events, while the idle
/// timer does not. So an absent sample clears the window outright rather than
/// being stored: a delta measured across a gap in which nobody was present
/// would be a lie, and this is the one place that lie could enter the data.
final class InputDensity {

    private var ring: [InputSample] = []

    /// Exposed for the tests; nothing in the app depends on it.
    var sampleCount: Int { ring.count }

    func record(_ sample: InputSample) {
        guard sample.idleSeconds < AppUsageTracker.idleCutoff else {
            ring.removeAll(keepingCapacity: true)
            return
        }
        ring.append(sample)
        if ring.count > FocusConstants.densityRingSize {
            ring.removeFirst(ring.count - FocusConstants.densityRingSize)
        }
    }

    var activity: InputActivity {
        guard let first = ring.first, let last = ring.last else { return .absent }
        // One sample proves a person is present but measures no rate.
        let minutes = last.at.timeIntervalSince(first.at) / 60
        guard ring.count >= 2, minutes > 0 else { return .passive }

        let keysPerMinute = Double(last.keys &- first.keys) / minutes
        let clicksPerMinute = Double(last.clicks &- first.clicks) / minutes

        if keysPerMinute >= FocusConstants.activeKeysPerMinute { return .active }
        // Clicking counts only alongside some typing. Clicks alone are a video
        // player; scrolls and mouse movement never qualify at all.
        if clicksPerMinute >= FocusConstants.activeClicksPerMinute && keysPerMinute > 0 {
            return .active
        }
        return .passive
    }
}
