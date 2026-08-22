#!/usr/bin/env swift
import CoreGraphics
import Foundation

/// Prints what each idle source reports, so the figure the app trusts can be
/// checked against the machine you are sitting at.
///
/// This exists because `CGEventSource.secondsSinceLastEventType` silently
/// returns a useless value for the wrong event type. `.null` is a specific
/// event type, not a wildcard: measured on an untouched machine it froze at
/// 184.6s across repeated reads while `kCGAnyInputEventType` advanced normally
/// from 49.8s. The app believed the Mac was permanently idle and trimmed 91
/// minutes out of a 2.6-hour day.
///
/// Run with:  swift scripts/idle-probe.swift
/// Leave the machine untouched for a minute; every figure should climb together.
let anyInput = CGEventType(rawValue: ~0) ?? .null
for tick in 1...5 {
    let any = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    let null = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)
    let key = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    let move = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
    print(String(format: "%d  any %7.1f   null %7.1f   key %7.1f   move %7.1f",
                 tick, any, null, key, move))
    if tick < 5 { Thread.sleep(forTimeInterval: 3) }
}
print("\n'any' is the one the app uses. If 'null' is frozen while 'any' climbs,")
print("that is the defect this script was written to catch.")
