import CoreGraphics
import Foundation

/// Seconds since the last keyboard or mouse event. Reads a timestamp, not event
/// content, so it needs no Input Monitoring grant — verified 2026-08-12: no TCC
/// prompt, no permission entry.
///
/// `.hidSystemState` is the correct source. `.combinedSessionState` returned
/// 44221s on an actively used machine and is unusable for this.
///
/// The event type must be `kCGAnyInputEventType`, not `.null`. `.null` is a
/// specific event type, not a wildcard, and it misses input the wildcard sees:
/// measured side by side on an untouched machine it reported 79s against the
/// wildcard's 40s, with mouse movement 42s ago invisible to it. Roughly double,
/// which meant the three-minute idle trim really fired at about ninety seconds
/// and cut real work out of every total in the app.
struct IdleMonitor {
    /// `CGEventType(rawValue: ~0)` is `kCGAnyInputEventType` — the wildcard the
    /// documentation names for "time since any keyboard, mouse or tablet event".
    private static let anyInput = CGEventType(rawValue: ~0) ?? .null

    var idleSeconds: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.hidSystemState,
                                                eventType: IdleMonitor.anyInput)
    }

    /// The input counters' running total, telling a person from an idle timer
    /// reset with no input behind it. Nil where it is not read: a monitor built
    /// around a fake idle time keeps the rule that a low idle time is a person.
    var inputCount: () -> UInt64? = { nil }

    /// Never trims — used where idle awareness is off.
    static let disabled = IdleMonitor(idleSeconds: { 0 })
    /// The real idle timer and the real input counters.
    static let system = IdleMonitor(inputCount: { InputCounters().total() })
}
