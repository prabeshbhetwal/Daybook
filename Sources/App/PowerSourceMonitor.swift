import Foundation
import IOKit.ps

protocol PowerSourceMonitoring: AnyObject {
    func observation(at timestamp: Date,
                     boundary: PowerCoverageBoundary?) -> PowerObservation
    func start(_ handler: @escaping (PowerObservation) -> Void)
    func stop()
}

final class PowerSourceMonitor: PowerSourceMonitoring {
    private var handler: ((PowerObservation) -> Void)?
    private var runLoopSource: CFRunLoopSource?

    static func parse(descriptions: [[String: Any]], at timestamp: Date,
                      boundary: PowerCoverageBoundary?) -> PowerObservation {
        let selected = descriptions.first(where: {
            ($0[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType
        }) ?? descriptions.first(where: {
            ($0[kIOPSTypeKey as String] as? String) == kIOPSUPSType
        }) ?? descriptions.first
        guard let selected else {
            return PowerObservation(timestamp: timestamp, source: .unknown, percentage: nil,
                                    charging: .unknown, boundary: boundary)
        }
        let type = selected[kIOPSTypeKey as String] as? String
        let state = selected[kIOPSPowerSourceStateKey as String] as? String
        let source: PowerSourceKind
        if type == kIOPSUPSType { source = .ups }
        else if state == kIOPSBatteryPowerValue { source = .battery }
        else if state == kIOPSACPowerValue { source = .external }
        else { source = .unknown }
        let charging: PowerChargingState
        if let value = selected[kIOPSIsChargingKey as String] as? Bool {
            charging = value ? .charging : .notCharging
        } else { charging = .unknown }
        return PowerObservation.normalised(timestamp: timestamp, source: source,
            currentCapacity: (selected[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue,
            maximumCapacity: (selected[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue,
            charging: charging, boundary: boundary)
    }

    func observation(at timestamp: Date,
                     boundary: PowerCoverageBoundary?) -> PowerObservation {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return PowerObservation(timestamp: timestamp, source: .unknown, percentage: nil,
                                    charging: .unknown, boundary: boundary)
        }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return Self.parse(descriptions: descriptions, at: timestamp, boundary: boundary)
    }

    func start(_ handler: @escaping (PowerObservation) -> Void) {
        guard runLoopSource == nil else { return }
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handler?(monitor.observation(at: Date(), boundary: .sourceChanged))
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        handler = nil
    }
}
