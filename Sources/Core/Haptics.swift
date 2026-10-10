import Foundation

/// The trackpad's three feedback patterns, named here because Core cannot
/// import AppKit; the App layer maps them to `NSHapticFeedbackManager`'s.
enum TrackpadPattern: Equatable {
    case generic, levelChange, alignment
}

/// MX Master 4 waveform ids (Solaar's `HapticWaveForms`). Each one used here
/// was played on the mouse and felt on 2026-10-10.
enum MouseWaveform {
    static let dampStateChange: UInt8 = 1
    static let subtleCollision: UInt8 = 4
    static let happyAlert: UInt8 = 5
    static let completed: UInt8 = 7
}

/// A moment that pulses. Asking for you plays happy alert; good news,
/// completed; for your information or confirming an action, damp state
/// change; a small step under your hand, subtle collision.
enum HapticMoment: CaseIterable, Equatable {
    case breakDue, awayQuestion, goalReached, notice, sessionToggled, zoomStep, tileDropped

    /// The daily goal has its own pulse; every other reward is a notice.
    init(reward: RewardKind) {
        self = reward == .goalReached ? .goalReached : .notice
    }

    var mouseWaveform: UInt8 {
        switch self {
        case .breakDue, .awayQuestion: return MouseWaveform.happyAlert
        case .goalReached: return MouseWaveform.completed
        case .notice, .sessionToggled: return MouseWaveform.dampStateChange
        case .zoomStep, .tileDropped: return MouseWaveform.subtleCollision
        }
    }

    var trackpadPattern: TrackpadPattern {
        switch self {
        case .zoomStep: return .levelChange
        case .tileDropped: return .alignment
        default: return .generic
        }
    }
}

/// HID++ 2.0 long reports, as an MX Master 4 connected over Bluetooth speaks
/// them. Logitech has not published feature 0x19B0 (haptics); the layout
/// follows OpenLogi and Solaar and was checked against the mouse.
enum HIDPP {
    static let longReportID: UInt8 = 0x11
    static let shortReportID: UInt8 = 0x10
    /// The device index for a device paired directly rather than through a receiver.
    static let directDevice: UInt8 = 0xFF
    static let reportLength = 20
    static let hapticFeature: (UInt8, UInt8) = (0x19, 0xB0)

    /// `[0x11, 0xFF, feature, function << 4 | softwareID, parameters…]`, zero-padded.
    /// The software id tells our replies from those of other HID++ clients,
    /// such as Logi Options+.
    static func request(feature: UInt8, function: UInt8, softwareID: UInt8,
                        parameters: [UInt8] = []) -> [UInt8] {
        var report = [longReportID, directDevice, feature, function << 4 | (softwareID & 0x0F)]
        report += parameters.prefix(reportLength - report.count)
        return report + [UInt8](repeating: 0, count: reportLength - report.count)
    }

    enum Reply: Equatable {
        /// The bytes after the function byte.
        case answer([UInt8])
        case error(UInt8)
        /// Mouse movement, another client's reply, or anything too short.
        case unrelated
    }

    static func reply(_ report: [UInt8], to request: [UInt8]) -> Reply {
        guard report.count >= 7, request.count >= 4,
              report[0] == shortReportID || report[0] == longReportID,
              report[1] == directDevice else { return .unrelated }
        let feature = request[2], function = request[3]
        if (report[2] == 0x8F || report[2] == 0xFF) && report[3] == feature && report[4] == function {
            return .error(report[5])
        }
        if report[2] == feature && report[3] == function { return .answer(Array(report[4...])) }
        return .unrelated
    }
}

/// Function 1 of feature 0x19B0: whether the mouse plays haptics, and how strongly.
struct HapticConfiguration: Equatable {
    /// Bit 0 of the first byte. The byte is a bit field: the tested mouse
    /// reports 3 with haptics on, so comparing the whole byte to 1 would
    /// refuse a mouse that is switched on.
    let isEnabled: Bool
    /// 0–100, set in Logi Options+. Daybook never writes it.
    let intensity: UInt8

    init?(payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        isEnabled = payload[0] & 1 == 1
        intensity = payload[1]
    }
}

/// Function 0 of feature 0x19B0: which waveforms this mouse can play.
struct HapticCapabilities: Equatable {
    /// Bit n set: waveform n is offered. Bytes 4–7 of the payload, big-endian.
    let waveformMask: UInt32

    init?(payload: [UInt8]) {
        guard payload.count >= 8 else { return nil }
        waveformMask = payload[4...7].reduce(0) { $0 << 8 | UInt32($1) }
    }

    func supports(_ waveform: UInt8) -> Bool {
        waveform < 32 && waveformMask & (1 << UInt32(waveform)) != 0
    }
}

enum MouseHaptics {
    /// Only send a play the mouse will act on: haptics on, a strength above
    /// zero, and a waveform it offers.
    static func playable(configuration: HapticConfiguration, capabilities: HapticCapabilities,
                         waveform: UInt8) -> Bool {
        configuration.isEnabled && configuration.intensity > 0 && capabilities.supports(waveform)
    }

    /// A send that fails usually means the mouse slept and came back as a new
    /// device. Find it again and send once more, so the first pulse after a
    /// return (the away question, as often as not) is not the one lost.
    static func sendRetryingOnce(_ attempt: () -> Bool, reconnect: () -> Bool) -> Bool {
        attempt() || (reconnect() && attempt())
    }
}
