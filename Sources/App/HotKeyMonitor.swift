import AppKit
import Carbon.HIToolbox

/// The global chord, ⌃⌥Space unless the user recorded another, via Carbon's
/// `RegisterEventHotKey`, which needs no
/// Accessibility grant — unlike `NSEvent.addGlobalMonitorForEvents`. Verified:
/// registration returns `noErr` with no TCC prompt.
///
/// ⌃⌥Space is also VoiceOver's own VO-Space, "activate this item". Held while
/// VoiceOver runs, it would take that command from every app and start or
/// stop a session instead, so the chord is let go for as long as VoiceOver
/// is on and taken back when it turns off.
///
/// Registration failure (another app owns the combination) is logged and
/// recorded in `status`; the feature is simply absent and nothing else breaks.
final class HotKeyMonitor: ObservableObject {

    enum Status: Equatable {
        /// Not started, or stopped at quit.
        case off
        /// ⌃⌥Space starts and stops sessions.
        case registered
        /// Let go because VoiceOver is running; it comes back when VoiceOver stops.
        case yieldedToVoiceOver
        /// Another app owns the combination, or the handler could not be installed.
        case unavailable
    }

    @Published private(set) var status: Status = .off
    /// The chord held, or nil while the shortcut is turned off.
    private(set) var shortcut: GlobalShortcut? = .standard

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var voiceOverObservation: NSKeyValueObservation?
    private static var onFire: (() -> Void)?

    private static let signature: OSType = 0x4643_5459   // 'FCTY'

    /// Returns whether the chord is held now. False when VoiceOver is running
    /// as well as on failure; `status` says which.
    @discardableResult
    func register(_ shortcut: GlobalShortcut?, onFire: @escaping () -> Void) -> Bool {
        guard handlerRef == nil else { return status == .registered }
        self.shortcut = shortcut
        HotKeyMonitor.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyMonitor.onFire?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        guard installStatus == noErr else {
            Diagnostics.log("hot key handler install failed: \(installStatus)")
            status = .unavailable
            return false
        }

        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { [weak self] _, _ in
            DispatchQueue.main.async { self?.holdUnlessVoiceOverRuns() }
        }
        holdUnlessVoiceOverRuns()
        return status == .registered
    }

    /// Takes a new chord, or none. When macOS refuses the new one (another
    /// app holds it) the old one is taken back and false is returned.
    @discardableResult
    func apply(_ next: GlobalShortcut?) -> Bool {
        let previous = shortcut
        releaseChord()
        shortcut = next
        holdUnlessVoiceOverRuns()
        guard next != nil, handlerRef != nil, status == .unavailable else { return true }
        shortcut = previous
        holdUnlessVoiceOverRuns()
        return false
    }

    private func holdUnlessVoiceOverRuns() {
        guard handlerRef != nil else { return }
        guard let shortcut else {
            releaseChord()
            status = .off
            return
        }
        if NSWorkspace.shared.isVoiceOverEnabled, shortcut.isVoiceOverChord {
            releaseChord()
            status = .yieldedToVoiceOver
            return
        }
        guard hotKeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(signature: HotKeyMonitor.signature, id: 1)
        let result = RegisterEventHotKey(shortcut.keyCode,
                                         shortcut.modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        if result == noErr {
            status = .registered
        } else {
            Diagnostics.log("hot key registration failed (\(result)); shortcut unavailable")
            hotKeyRef = nil
            status = .unavailable
        }
    }

    private func releaseChord() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func unregister() {
        voiceOverObservation?.invalidate()
        voiceOverObservation = nil
        releaseChord()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        HotKeyMonitor.onFire = nil
        status = .off
    }

    deinit {
        unregister()
    }
}
