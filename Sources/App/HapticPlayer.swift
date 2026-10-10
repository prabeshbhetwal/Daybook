import AppKit
import SwiftUI

/// Where the mouse link stands, as Try reports it.
enum MouseLinkStatus: Equatable {
    case closed, ready, noMouse, hapticsOff, notPermitted, noReply

    /// The line under Settings' Try button. The trackpad always gets the
    /// pulse; it is felt only under a resting finger, which the system does
    /// not report, so each line says where the pulse went, not what was felt.
    var tryMessage: String {
        switch self {
        case .ready:
            return "Sent to the MX Master 4 and the trackpad."
        case .noMouse, .closed:
            return "No MX Master 4 connected over Bluetooth. Sent to the trackpad: rest a finger on it to feel the pulse."
        case .hapticsOff:
            return "The MX Master 4 has haptics turned off. Turn them on in Logi Options+."
        case .notPermitted:
            return "macOS blocked access to the mouse. Allow Daybook in System Settings › Privacy & Security › Input Monitoring."
        case .noReply:
            return "The MX Master 4 did not answer. Move it to wake it, then try again."
        }
    }
}

/// The mouse half of the player: the MX Master 4 in the app, a fake in checks.
protocol MouseHapticLink: AnyObject {
    func open()
    func close()
    /// Fire and forget; silent when the mouse cannot play it.
    func play(_ waveform: UInt8)
    /// Reads the mouse afresh, then reports on the main thread.
    func rediscover(completion: @escaping (MouseLinkStatus) -> Void)
}

/// Sends each haptic moment to the trackpad and the mouse while the setting
/// is on. Whichever device has the person's hand on it is felt; the other
/// pulse goes nowhere. Every failure is silent: haptics accompany a notice
/// that is already on screen, they never carry it alone.
final class HapticPlayer {
    private let isEnabled: () -> Bool
    private let mouse: MouseHapticLink
    private let trackpad: (TrackpadPattern) -> Void

    init(isEnabled: @escaping () -> Bool, mouse: MouseHapticLink,
         trackpad: @escaping (TrackpadPattern) -> Void = HapticPlayer.performOnTrackpad) {
        self.isEnabled = isEnabled
        self.mouse = mouse
        self.trackpad = trackpad
    }

    /// Opening when the switch turns on puts any macOS permission prompt
    /// beside the switch, not at a random notice later.
    func setEnabled(_ on: Bool) {
        if on { mouse.open() } else { mouse.close() }
    }

    func play(_ moment: HapticMoment) {
        guard isEnabled() else { return }
        trackpad(moment.trackpadPattern)
        mouse.play(moment.mouseWaveform)
    }

    /// The Try button: the goal pulse on both devices, and what the mouse said.
    func tryPulse(completion: @escaping (MouseLinkStatus) -> Void) {
        trackpad(HapticMoment.goalReached.trackpadPattern)
        mouse.rediscover { [mouse] status in
            if status == .ready { mouse.play(MouseWaveform.completed) }
            completion(status)
        }
    }

    /// Felt only while a finger rests on the trackpad: the system drops the
    /// pulse otherwise, so there is nothing to check for first.
    static func performOnTrackpad(_ pattern: TrackpadPattern) {
        let perform = {
            MainActor.assumeIsolated {
                NSHapticFeedbackManager.defaultPerformer.perform(pattern.feedbackPattern,
                                                                 performanceTime: .now)
            }
        }
        if Thread.isMainThread { perform() } else { DispatchQueue.main.async(execute: perform) }
    }
}

private extension TrackpadPattern {
    var feedbackPattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .generic: return .generic
        case .levelChange: return .levelChange
        case .alignment: return .alignment
        }
    }
}

private struct HapticsKey: EnvironmentKey {
    static let defaultValue: (HapticMoment) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Set on the main window's root; a no-op everywhere else, so fixtures,
    /// the gallery and snapshots never pulse.
    var haptics: (HapticMoment) -> Void {
        get { self[HapticsKey.self] }
        set { self[HapticsKey.self] = newValue }
    }
}
