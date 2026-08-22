import AppKit
import Carbon.HIToolbox

/// Global ⌃⌥Space via Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility grant — unlike `NSEvent.addGlobalMonitorForEvents`. Verified:
/// registration returns `noErr` with no TCC prompt.
///
/// Registration failure (another app owns the combination) is logged and
/// ignored; the feature is simply absent and nothing else breaks.
final class HotKeyMonitor {

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var onFire: (() -> Void)?

    private static let signature: OSType = 0x4643_5459   // 'FCTY'

    func register(onFire: @escaping () -> Void) {
        guard hotKeyRef == nil else { return }
        HotKeyMonitor.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyMonitor.onFire?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        guard installStatus == noErr else {
            Diagnostics.log("hot key handler install failed: \(installStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: HotKeyMonitor.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space),
                                         UInt32(controlKey | optionKey),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        if status != noErr {
            Diagnostics.log("hot key registration failed (\(status)); shortcut unavailable")
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        HotKeyMonitor.onFire = nil
    }

    deinit {
        unregister()
    }
}
